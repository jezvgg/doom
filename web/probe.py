"""Безголовый клиент для проверки сервера: подключается, читает кадры,
двигает игрока и печатает статистику.

    python -m web.server &            # поднять сервер
    python -m web.probe               # два «игрока» и проверка кадров
"""

import asyncio
import time

import websockets

from .world import FRAME_BYTES, HEADER, TICK_HZ

URL = "ws://127.0.0.1:8000/ws?name={name}"


async def player(name, moves, out):
    """Один бот: слушает кадры, шлёт ввод по расписанию moves."""
    async with websockets.connect(URL.format(name=name)) as socket:
        start = time.perf_counter()
        received = 0
        positions = []

        while True:
            raw = await socket.recv()
            assert isinstance(raw, bytes), "сервер должен присылать бинарные кадры"
            received += 1
            x, y, angle, players, stamp = HEADER.unpack_from(raw, 0)
            if received == 1:
                out[name] = {"first": (x, y, angle, players), "bytes": len(raw), "stamp": stamp}
                assert len(raw) == FRAME_BYTES, f"кадр {len(raw)} != {FRAME_BYTES}"
            assert stamp >= out[name]["stamp"], "время кадра пошло назад"
            out[name]["stamp"] = stamp

            elapsed = time.perf_counter() - start
            if moves and elapsed >= moves[0][0]:
                _, payload = moves.pop(0)
                await socket.send(payload)
            if moves and elapsed >= 3.0:
                positions.append((x, y, angle, players))
            if elapsed > 3.0 and not moves:
                break

        out[name]["last"] = (x, y, angle, players)
        out[name]["frames"] = received
        out[name]["path"] = positions


async def main():
    out = {}
    moves_a = [
        (0.6, '{"f": 1}'),
        (1.2, '{"f": 0}'),
        (1.4, '{"r": 1}'),
        (1.9, '{"r": 0, "f": 1}'),
    ]
    started = time.perf_counter()
    await asyncio.gather(player("alpha", moves_a, out), player("beta", [], out))
    elapsed = time.perf_counter() - started

    for name, info in out.items():
        first = info["first"]
        last = info["last"]
        print(
            f"{name}: кадров {info['frames']:3d} ({info['frames'] / elapsed:5.1f}/с, "
            f"ожидали ~{TICK_HZ}/с), размер {info['bytes']} байт"
        )
        print(
            f"   старт x={first[0]:.2f} y={first[1]:.2f} angle={first[2]:.2f} | "
            f"финиш x={last[0]:.2f} y={last[1]:.2f} angle={last[2]:.2f} | игроков {last[3]}"
        )
        assert info["bytes"] == FRAME_BYTES
        assert last[3] == 2, "оба клиента должны видеть друг друга"

    alpha = out["alpha"]
    moved = alpha["last"][0] != alpha["first"][0] or alpha["last"][1] != alpha["first"][1]
    turned = abs(alpha["last"][2] - alpha["first"][2]) > 0.1
    print(f"движение: {'да' if moved else 'НЕТ'}, поворот: {'да' if turned else 'НЕТ'}")
    assert moved and turned, "ввод не дошёл до сервера"
    print("ok")


if __name__ == "__main__":
    asyncio.run(main())
