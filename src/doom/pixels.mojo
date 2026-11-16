from render.screen import Screen


# "00", "01", ... "ff" — hex-пара по значению байта (0..255)
comptime HEXPAIRS: String = (
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"
    "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f"
    "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f"
    "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
    "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
    "c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf"
    "e0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
)


def hsv_to_rgb(hue: Int, saturation: Int, brightness: Int) -> Tuple[Int, Int, Int]:
    """HSV (0..255 в каждом канале) -> RGB (0..255).

    hue 0..255 — полный круг (0 = красный, 85 = зелёный, 170 = синий).
    saturation == 0 даёт серый: (v, v, v) — именно этот путь и работает сейчас,
    пока рендер пишет только яркость.
    """
    var v = brightness
    if v < 0:
        v = 0
    elif v > 255:
        v = 255
    var s = saturation
    if s <= 0:
        return (v, v, v)
    if s > 255:
        s = 255

    # hue -> окружность из 6 секторов; f — положение внутри сектора 0..1
    var h6 = Float64(hue % 256) / 256.0 * 6.0
    var sector = Int(h6) % 6
    var f = h6 - Float64(Int(h6))

    # p — самый тёмный канал, q/t — промежуточные (стандартная формула HSV->RGB)
    var p = v * (255 - s) // 255
    var q = v * (255 - Int(Float64(s) * f)) // 255
    var t = v * (255 - Int(Float64(s) * (1.0 - f))) // 255

    if sector == 0:
        return (v, t, p)
    elif sector == 1:
        return (q, v, p)
    elif sector == 2:
        return (p, v, t)
    elif sector == 3:
        return (p, q, v)
    elif sector == 4:
        return (t, p, v)
    return (v, p, q)


def screen_to_hex(ref screen: Screen) -> String:
    """Screen -> строка из 3 hex-байт (RGB) на пиксель, построчно.

    Отдельно от pygame: этим же путём пользуется Python-расширение
    (см. pyext.mojo), которому нужен только буфер, без pygame.
    """
    var hex = String()
    for row in range(Screen.height):
        for col in range(Screen.width):
            var r, g, b = hsv_to_rgb(
                Int(screen.hue[row][col]) & 0xFF,
                Int(screen.saturation[row][col]) & 0xFF,
                Int(screen.value[row][col]) & 0xFF,
            )
            hex += HEXPAIRS[byte=r * 2:r * 2 + 2]
            hex += HEXPAIRS[byte=g * 2:g * 2 + 2]
            hex += HEXPAIRS[byte=b * 2:b * 2 + 2]
    return hex^
