"""Мир сервера: состояние сессий, тик игры и сборка кадров.

Mojo-движок используется как библиотека (`from doom import export`). Важно,
что объекты движка — value-типы: `Player` не мутируется методами, а
возвращает нового, поэтому состояние игрока живёт в сессии и на каждом тике
переприсваивается.

Один `Renderer`/`Engine` обслуживает все сессии: у них общий `Map` (внутри
`ArcPointer`), а `render_view(player)` принимает игрока аргументом — значит
рейкаст считается от позиции конкретного игрока, без копий уровня.
"""

import asyncio
import math
import struct
import time
import uuid

from doom import export as ext

# частота тика и рассылки кадров
TICK_HZ = 30

# заголовок бинарного кадра: x, y, угол игрока, число игроков в мире,
# время кадра на сервере (мс по монотонным часам, только для сравнения с приходом)
HEADER = struct.Struct("<fffII")
FRAME_WIDTH = 128
FRAME_HEIGHT = 128
FRAME_BYTES = HEADER.size + FRAME_WIDTH * FRAME_HEIGHT * 3

# одна клавиша = один шаг/поворот за тик; движение в player.mojo фиксированное
INPUT_KEYS = {"f": "forward", "b": "backward", "l": "left", "r": "right"}


class Input:
    """Что зажато у конкретного игрока."""

    __slots__ = ("forward", "backward", "left", "right")

    def __init__(self):
        self.forward = False
        self.backward = False
        self.left = False
        self.right = False

    def update(self, message):
        """Применяет `{"f": true, ...}` от клиента; мусор игнорируется."""
        if not isinstance(message, dict):
            return
        for short, name in INPUT_KEYS.items():
            if short in message:
                setattr(self, name, bool(message[short]))

    def reset(self):
        self.forward = self.backward = self.left = self.right = False


class Session:
    """Один подключённый игрок.

    Кадры не пишутся в сокет из тика: они попадают в `outbox` — ячейку на один
    кадр, а отправитель сессии (`web/server.py: sender_loop`) забирает их в её
    собственном темпе. Поэтому медленный клиент выбрасывает кадры, но не
    тормозит остальных и не копит «прошлое» в буфере сокета.
    """

    __slots__ = ("id", "name", "player", "socket", "input", "outbox", "dropped", "closed", "sender")

    def __init__(self, session_id, name, player, socket):
        self.id = session_id
        self.name = name
        self.player = player
        self.socket = socket
        self.input = Input()
        self.outbox = asyncio.Queue(maxsize=1)  # только самый свежий кадр
        self.dropped = 0                        # кадры, выброшенные неотправленными
        self.closed = False
        self.sender: asyncio.Task | None = None

    def push(self, frame):
        """Кладёт кадр в ячейку, выбрасывая непереданный старый. Не ждёт."""
        try:
            self.outbox.put_nowait(frame)
            return
        except asyncio.QueueFull:
            pass
        try:
            self.outbox.get_nowait()  # устаревший кадр: клиент всё равно его не увидит
        except asyncio.QueueEmpty:
            pass
        self.dropped += 1
        try:
            self.outbox.put_nowait(frame)
        except asyncio.QueueFull:
            pass


def spawn_points(level):
    """Свободные клетки карты -> точки спавна в их центрах, лицом к центру."""
    spots = []
    for y in range(1, ext.Map.size() - 1):
        for x in range(1, ext.Map.size() - 1):
            if level.is_wall(x, y):
                continue
            # соседи тоже должны быть свободны, иначе родимся вплотную к стене
            if level.is_wall(x - 1, y) or level.is_wall(x + 1, y):
                continue
            if level.is_wall(x, y - 1) or level.is_wall(x, y + 1):
                continue
            angle = math.atan2(8.0 - (y + 0.5), 8.0 - (x + 0.5))
            spots.append((x + 0.5, y + 0.5, angle))
    return spots


class World:
    """Общий мир: карта, игроки и кадры для каждого из них."""

    def __init__(self):
        self.level = ext.Map()
        self.engine = ext.Engine(self.level)
        self.renderer = ext.Renderer(self.level)
        self.sessions: dict[str, Session] = {}
        self.spawns = spawn_points(self.level) or [(1.5, 1.5, 0.0)]
        self._spawn_index = 0

    # ------------------------------------------------------------------
    # подключение/отключение
    # ------------------------------------------------------------------

    def join(self, socket, name=""):
        session_id = uuid.uuid4().hex[:8]
        x, y, angle = self.spawns[self._spawn_index % len(self.spawns)]
        self._spawn_index += 1
        session = Session(
            session_id=session_id,
            name=name or f"player-{session_id}",
            player=ext.Player(x, y, angle),
            socket=socket,
        )
        self.sessions[session_id] = session
        self._sync_entities()
        return session

    def leave(self, session_id):
        session = self.sessions.pop(session_id, None)
        if session is not None:
            session.closed = True
            session.input.reset()
            # отправитель сессии больше не нужен (себя отменять не надо)
            if session.sender is not None and session.sender is not asyncio.current_task():
                session.sender.cancel()
            self._sync_entities()
        return session

    # ------------------------------------------------------------------
    # тик
    # ------------------------------------------------------------------

    def update(self):
        """Двигает всех игроков по их вводу. Возвращает число живых сессий."""
        for session in self.sessions.values():
            session.player = self._step(session.player, session.input)
        self._sync_entities()
        return len(self.sessions)

    def _step(self, player, input):
        # поворот меняет только луч — коллизия тут не нужна
        if input.left:
            player = player.rotate_left()
        if input.right:
            player = player.rotate_right()

        if input.forward:
            player = self._try_move(player.move_forward(), player)
        elif input.backward:
            player = self._try_move(player.move_backward(), player)
        return player

    def _try_move(self, candidate, current):
        """Player — value-тип: пробуем кандидата, при коллизии остаёмся на месте."""
        return current if self.engine.check_collision(candidate) else candidate

    def _sync_entities(self):
        """Все игроки — спрайты уровня, чтобы их видели друг у друга."""
        self.level.clear_entities()
        for session in self.sessions.values():
            self.level.add_entity(session.player)

    # ------------------------------------------------------------------
    # кадры
    # ------------------------------------------------------------------

    def frame(self, session):
        """Кадр для одного игрока: заголовок + RGB-пиксели 128x128."""
        player = session.player
        pixels = bytes.fromhex(self.renderer.render(player))
        # время сервера нужно клиенту, чтобы не рисовать кадры из прошлого,
        # которые вылились из буфера после обрыва канала
        stamp = int(time.monotonic() * 1000) & 0xFFFFFFFF
        return HEADER.pack(player.x(), player.y(), player.angle(), len(self.sessions), stamp) + pixels

    def frames(self):
        """Кадры для всех сессий: {id: bytes}."""
        return {session.id: self.frame(session) for session in self.sessions.values()}
