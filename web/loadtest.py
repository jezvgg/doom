"""Нагрузка «как в жизни»: нормальные игроки + игроки с вставшим каналом.

Проверяет главное свойство сервера — один клиент с плохим каналом не должен
тормозить остальных. Гонять можно и по живому сайту:

    python -m web.loadtest                                   # 2 хороших + 2 зависших, 20 c
    python -m web.loadtest --url wss://doom.jezv.ru/ws --good 3 --bad 4 --seconds 30

Хорошие клиенты читают каждый кадр и мерят паузы; «зависшие» подключаются и
перестают читать — их сокеты наполняются, как при пропаже мобильного интернета.
Печатается сводка: минимальный fps хороших клиентов, худшая пауза и сколько
кадров сервер отбросил зависшим (если клиент дожил до конца — сессия жива).
"""

import argparse
import asyncio
import base64
import os
import socket
import struct
import time
from urllib.parse import urlparse

import websockets

from .world import FRAME_BYTES, HEADER, TICK_HZ


async def good_player(url, name, seconds, out):
    """Читает всё подряд и запоминает интервалы между кадрами."""
    gaps = []
    last = None
    received = 0
    drawn_ages = []
    offset = None
    async with websockets.connect(f"{url}?name={name}") as socket:
        start = time.perf_counter()
        while time.perf_counter() - start < seconds:
            left = seconds - (time.perf_counter() - start)
            try:
                raw = await asyncio.wait_for(socket.recv(), timeout=left)
            except asyncio.TimeoutError:
                break
            now = time.perf_counter()
            received += 1
            if last is not None:
                gaps.append(now - last)
            last = now
            stamp = HEADER.unpack_from(raw, 0)[4] if isinstance(raw, bytes) else 0
            recv_ms = now * 1000
            offset = recv_ms - stamp if offset is None else min(offset, recv_ms - stamp)
            drawn_ages.append(recv_ms - stamp - offset)
        end = time.perf_counter()

    gaps.sort()
    tail = end - last if last else seconds
    out[name] = {
        "frames": received,
        "fps": round(received / seconds, 1),
        "max_gap_ms": round(max(gaps[-1] if gaps else 0.0, tail) * 1000),
        "stale_frames": sum(1 for age in drawn_ages if age > 250),
    }


async def raw_socket(url, name, seconds, out):
    """Клиент, который перестаёт читать: канал «встал», сервер этого не знает."""
    parsed = urlparse(url)
    port = parsed.port or (443 if parsed.scheme in ("wss", "https") else 80)
    host = parsed.hostname or "127.0.0.1"
    hostport = f"{host}:{port}"

    reader, writer = await asyncio.open_connection(host, port, ssl=True if parsed.scheme == "wss" else None)
    key = base64.b64encode(os.urandom(16)).decode()
    path = (parsed.path or "/") + f"?name={name}"
    writer.write(
        (
            f"GET {path} HTTP/1.1\r\nHost: {hostport}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode()
    )
    await writer.drain()
    head = await reader.readuntil(b"\r\n\r\n")
    if b"101" not in head.split(b"\r\n")[0]:
        out[name] = {"error": head.split(b"\r\n")[0].decode("latin1", "replace")}
        writer.close()
        return

    # молчим: не читаем ни байта, пока идёт замер
    await asyncio.sleep(seconds)
    # и только потом забираем то, что успело накопиться
    tail_bytes = 0
    try:
        while True:
            chunk = await asyncio.wait_for(reader.read(1 << 16), timeout=0.5)
            if not chunk:
                break
            tail_bytes += len(chunk)
    except asyncio.TimeoutError:
        pass
    out[name] = {"buffered_frames": round(tail_bytes / FRAME_BYTES, 1)}
    writer.close()


async def loadtest(url: str, good: int, bad: int, seconds: float):
    out: dict = {}
    tasks = [good_player(url, f"good{i}", seconds, out) for i in range(good)]
    tasks += [raw_socket(url, f"bad{i}", seconds, out) for i in range(bad)]
    await asyncio.gather(*tasks)

    goods = [info for name, info in out.items() if name.startswith("good")]
    if not goods:
        return out
    worst = min(info["fps"] for info in goods)
    gap = max(info["max_gap_ms"] for info in goods)
    print(f"хороших клиентов: {len(goods)}, худший fps {worst} (тикаем на {TICK_HZ})")
    print(f"худшая пауза между кадрами: {gap} мс")
    stale = sum(info["stale_frames"] for info in goods)
    print(f"кадров, пришедших из прошлого (старше 250 мс): {stale}")
    print(f"исправны: {'да' if worst >= TICK_HZ * 0.9 and gap < 500 else 'НЕТ'}")
    return out


def main():
    summary = (__doc__ or "").strip().splitlines()[0]
    parser = argparse.ArgumentParser(description=summary)
    parser.add_argument("--url", default="ws://127.0.0.1:8000/ws")
    parser.add_argument("--good", type=int, default=2)
    parser.add_argument("--bad", type=int, default=2)
    parser.add_argument("--seconds", type=float, default=20.0)
    args = parser.parse_args()
    asyncio.run(loadtest(args.url, args.good, args.bad, args.seconds))


if __name__ == "__main__":
    main()
