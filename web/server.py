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

import asyncio
import time
from pathlib import Path

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
    """Принимает ввод игрока; кадры отправляет фоновый тик-цикл."""
    await socket.accept()
    session = world.join(socket, socket.query_params.get("name", ""))
    try:
        while True:
            message = await socket.receive_json()
            session.input.update(message)
    except WebSocketDisconnect:
        pass
    finally:
        world.leave(session.id)


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
            try:
                await session.socket.send_bytes(frame)
            except Exception:
                # клиент мог отвалиться между тиком и отправкой
                world.leave(session_id)

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
