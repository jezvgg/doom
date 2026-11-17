"""Веб-сервер: Litestar + websocket, движок doom.mojo как библиотека.

Архитектура — «тонкий клиент, толстый сервер»:

    браузер ──(ввод, JSON)──▶ сервер ──(кадр, binary)──▶ браузер

* Сервер владеет миром: у каждого подключения свой `Player` в одном общем
  `Map`, поэтому игроки видят друг друга спрайтами.
* 30 раз в секунду сервер двигает всех игроков, рейкастит кадр для каждого
  и отправляет его одним бинарным сообщением.
* Клиент не считает ничего: он рисует присланные пиксели 128x128 и шлёт
  состояние клавиш.

Формат кадра (`web/world.py: HEADER` + RGB):

    0..3    float32  x игрока
    4..7    float32  y игрока
    8..11   float32  угол игрока
    12..15  uint32   сколько игроков в мире
    16..    W*H*3 байта RGB, построчно

Запуск:

    mojo build src/doom/export.mojo --emit shared-lib -o src/doom/export.so -I src/doom
    python -m web.server            # http://127.0.0.1:8000
"""

import array
import asyncio
import time
from pathlib import Path

try:
    # очередь отправки ядра (TIOCOUTQ) — только Linux, там и живёт сервер
    import fcntl
    import termios

    _TIOCOUTQ = getattr(termios, "TIOCOUTQ", None)
except ImportError:  # pragma: no cover — не POSIX: останется только буфер транспорта
    fcntl = None
    _TIOCOUTQ = None

import uvicorn
from litestar import Litestar, MediaType, Response, WebSocket, get, websocket
from litestar.exceptions import WebSocketDisconnect

from .world import TICK_HZ, World

STATIC_DIR = Path(__file__).parent / "static"
HOST = "127.0.0.1"
PORT = 8000

# один мир на процесс: все сессии видят общий уровень
world = World()


# ---------------------------------------------------------------------------
# статика
# ---------------------------------------------------------------------------


@get("/", media_type=MediaType.HTML, include_in_schema=False)
async def index() -> Response:
    return Response(content=(STATIC_DIR / "index.html").read_bytes(), media_type=MediaType.HTML)


@get("/app.js", media_type="application/javascript", include_in_schema=False)
async def app_js() -> Response:
    return Response(
        content=(STATIC_DIR / "app.js").read_bytes(),
        media_type="application/javascript",
    )


# ---------------------------------------------------------------------------
# игровой websocket
# ---------------------------------------------------------------------------


@websocket("/ws")
async def game_socket(socket: WebSocket) -> None:
    """Принимает ввод игрока; кадры отправляет отправитель сессии."""
    await socket.accept()
    session = world.join(socket, socket.query_params.get("name", ""))
    session.sender = asyncio.create_task(sender_loop(session))
    try:
        while True:
            message = await socket.receive_json()
            session.input.update(message)
    except WebSocketDisconnect:
        pass
    finally:
        world.leave(session.id)


# ---------------------------------------------------------------------------
# отправка кадров: своя задача на сессию, тик в сокеты не пишет
# ---------------------------------------------------------------------------
#
# Раньше тик делал `await socket.send_bytes(frame)` по очереди на каждую
# сессию. Если чей-то канал встал (потеря пакетов, спящая вкладка, мобильный
# интернет), этот `await` блокировал тик — и замирали все, а отставший клиент
# получал потом пачку «прошлых» кадров.
#
# Теперь тик только кладёт кадр в ячейку сессии (`Session.push`, не ждёт),
# а отправляет отдельная задача. Отставший клиент выбрасывает кадры: картинка
# у него дёргается, зато остаётся в реальном времени и никого не тормозит.

# сколько байт может ждать в буфере сокета, прежде чем кадры начинаем выбрасывать:
# 48 КБ — это примерно секунда видео при штатных 30 кадрах в секунду
SOFT_BACKLOG = 48 * 1024
# столько — уже не «плохой канал», а мёртвый сокет: сессию закрываем
HARD_BACKLOG = 512 * 1024
# сколько ждём одну запись, прежде чем считать, что канал встал
SEND_TIMEOUT = 2.0
# сколько секунд буфер не опускается до SOFT_BACKLOG — клиент не читает
DEAD_AFTER = 15.0
# как часто просыпаемся, когда кадров нет (проверка живости)
IDLE_POLL = 1.0


def _find_transport(obj, depth=0, seen=None):
    """Ищет asyncio-транспорт в объекте сокета (Litestar его не отдаёт наружу).

    Транспорт нужен только для одной цифры — сколько байт ещё висит в очереди
    отправки. У Litestar он лежит за двумя замыканиями
    (`socket.send.closure[function].closure[method].__self__.transport`), поэтому
    и обход рекурсивный. Если фреймворк/сервер поменяются, функция просто вернёт
    `None` — останется очередь на один кадр и таймаут записи.
    """
    if obj is None or depth > 6:
        return None
    if seen is None:
        seen = set()
    if id(obj) in seen:
        return None
    seen.add(id(obj))

    if hasattr(obj, "get_write_buffer_size") and hasattr(obj, "get_extra_info"):
        return obj

    candidates = []
    for attr in ("send", "receive", "__self__", "_socket", "transport"):
        value = getattr(obj, attr, None)
        if value is not None and value is not obj:
            candidates.append(value)
    for cell in getattr(obj, "__closure__", None) or ():
        try:
            candidates.append(cell.cell_contents)
        except ValueError:
            continue

    for value in candidates:
        found = _find_transport(value, depth + 1, seen)
        if found is not None:
            return found
    return None


def _kernel_queue(transport) -> int:
    """Байты в очереди отправки ядра: то, что сервер уже записал, но клиент не забрал."""
    if _TIOCOUTQ is None or fcntl is None:
        return 0
    try:
        raw = transport.get_extra_info("socket")
        if raw is None:
            return 0
        queued = array.array("i", [0])
        fcntl.ioctl(raw.fileno(), _TIOCOUTQ, queued, True)
        return int(queued[0])
    except Exception:
        # не Linux или сокет уже закрыт: остаётся только буфер транспорта
        return 0


def _backlog(socket) -> int:
    """Сколько байт отдано в сокет, но ещё не подтверждено клиентом (0 — не знаем).

    Считаем обе очереди: буфер транспорта и очередь ядра (TIOCOUTQ). Вторая
    важнее: на быстром канале данные сразу уходят в ядро, и буфер транспорта
    остаётся пустым, даже если клиент давно не читает.
    """
    transport = _find_transport(socket)
    if transport is None:
        return 0
    try:
        buffered = int(transport.get_write_buffer_size())
    except Exception:
        buffered = 0
    return buffered + _kernel_queue(transport)


async def sender_loop(session) -> None:
    """Шлёт кадры одной сессии в её темпе; при перегрузке канала кадры выбрасывает."""
    socket = session.socket
    last_ok = time.monotonic()
    try:
        while not session.closed:
            try:
                frame = await asyncio.wait_for(session.outbox.get(), timeout=IDLE_POLL)
            except asyncio.TimeoutError:
                frame = None

            backlog = _backlog(socket)
            if backlog > HARD_BACKLOG:
                break
            if backlog > SOFT_BACKLOG and time.monotonic() - last_ok > DEAD_AFTER:
                # канал не тянет уже давно: держать сессию смысла нет
                break
            if frame is None:
                continue
            if backlog > SOFT_BACKLOG:
                # канал отстаёт: свежий кадр в мусор, а не в очередь на полминуты
                session.dropped += 1
                continue
            try:
                await asyncio.wait_for(socket.send_bytes(frame), timeout=SEND_TIMEOUT)
            except (asyncio.TimeoutError, WebSocketDisconnect):
                break
            except Exception:
                # клиент отвалился между тиком и отправкой
                break
            last_ok = time.monotonic()
    finally:
        session.closed = True
        if session.dropped:
            # видно в логах сервиса: у кого канал не тянет и насколько
            print(
                f"doom: сессия {session.id} ({session.name}) закрыта, "
                f"отброшено кадров: {session.dropped}",
                flush=True,
            )
        if world.leave(session.id) is not None:
            # закрываем сокет, чтобы цикл приёма ввода тоже завершился
            try:
                await socket.close()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# тик-цикл: единственное место, где идёт рассылка кадров
# ---------------------------------------------------------------------------


async def tick_loop() -> None:
    period = 1.0 / TICK_HZ
    deadline = time.perf_counter()
    while True:
        world.update()

        for session_id, frame in world.frames().items():
            session = world.sessions.get(session_id)
            if session is None:
                continue
            # не ждём отправку: свой темп у каждой сессии
            session.push(frame)

        deadline += period
        delay = deadline - time.perf_counter()
        if delay < 0:
            # не копим долг, если тик не успел: иначе «догоняющие» кадры пачкой
            deadline = time.perf_counter()
            delay = 0.0
        await asyncio.sleep(delay)


_tick_task: asyncio.Task | None = None


async def start_ticking() -> None:
    global _tick_task
    _tick_task = asyncio.create_task(tick_loop())


async def stop_ticking() -> None:
    global _tick_task
    if _tick_task is not None:
        _tick_task.cancel()
        try:
            await _tick_task
        except asyncio.CancelledError:
            pass
        _tick_task = None


app = Litestar(
    route_handlers=[index, app_js, game_socket],
    on_startup=[start_ticking],
    on_shutdown=[stop_ticking],
)


if __name__ == "__main__":
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
