from std.python import Python, PythonObject
from std.memory import ArcPointer

from engine import Engine
from map import Map
from player import Player
from render.ray import Ray
from render.raycaster import Raycaster
from render.render import Renderer
from render.screen import Screen
from render.textures.bricks import BricksTexture
from render.textures.player import PlayerTexture

# во сколько раз увеличить 128x128 при показе в окне
comptime SCALE: Int = 4

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

# какие клавиши зажаты: w s a d left right -> строка из '0'/'1'
comptime KEYS_PY: String = "lambda pg: (lambda ks: ''.join('1' if ks[k] else '0' for k in (pg.K_w, pg.K_s, pg.K_a, pg.K_d, pg.K_LEFT, pg.K_RIGHT)))(pg.key.get_pressed())"

# «пора закрывать окно»: крестик или Esc
comptime QUIT_PY: String = "lambda pg: any(e.type == pg.QUIT or (e.type == pg.KEYDOWN and e.key == pg.K_ESCAPE) for e in pg.event.get())"


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


def screen_to_image(
    fromhex: PythonObject,
    frombytes: PythonObject,
    screen: Screen,
) raises -> PythonObject:
    """Screen -> pygame.Surface 128x128, три байта (RGB) на пиксель.

    Пиксель (col, row) берём из screen.hue/saturation/value[row][col] —
    внешний массив по высоте (строки), внутренний по ширине (столбцы), как
    объявлено в Screen. Байты собираем в порядке строк (сверху вниз, слева
    направо) — этого ждёт image.frombytes с форматом "RGB".

    Каналы читаются как `Int(x) & 0xFF`: это одинаково работает и с UInt8,
    и с Int8 (где 200 лежит как -56), так что переполнение знака не превращает
    светлые участки в чёрные.

    Почему hex, а не список: Mojo умеет отдать в Python только строку, а
    bytes.fromhex раскладывает ASCII-пары в настоящий bytes быстрее, чем
    PythonObject-кортеж из 49152 чисел. Палитра больше не нужна — цвет
    считается здесь, поэтому set_palette из кадра убран.
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
    var raw = fromhex(hex)
    return frombytes(raw, Python.tuple(Screen.width, Screen.height), "RGB")


def draw_pixels(
    win: PythonObject,
    fromhex: PythonObject,
    frombytes: PythonObject,
    scale: PythonObject,
    screen: Screen,
) raises:
    """Один кадр: Screen -> поверхность 128x128 -> растяжка SCALE -> окно."""
    var img = screen_to_image(fromhex, frombytes, screen)
    var big = scale(img, Python.tuple(Screen.width * SCALE, Screen.height * SCALE))
    _ = win.blit(big, Python.tuple(0, 0))


def main() raises:
    var player = Player(Ray(4.5, 4.5, 0.0))
    var map = ArcPointer(Map[Player]())
    map[].entities.append(Player(Ray(4.5, 4.5, 0.0)))
    var renderer = Renderer(Raycaster(map), BricksTexture())
    var engine = Engine(map, Raycaster(map))

    # ---------- окно pygame ----------
    var pg = Python.import_module("pygame")
    _ = pg.init()
    var win = pg.display.set_mode(Python.tuple(Screen.width * SCALE, Screen.height * SCALE))
    _ = pg.display.set_caption("doom.mojo")

    # Python-функции создаём один раз, а не каждый кадр
    var fromhex = Python.evaluate("bytes.fromhex")
    var frombytes = pg.image.frombytes
    var scale = pg.transform.scale

    var keys = Python.evaluate(KEYS_PY)
    var quit_requested = Python.evaluate(QUIT_PY)

    draw_pixels(win, fromhex, frombytes, scale, renderer.render_view(player))
    _ = pg.display.flip()

    # ---------- игровой цикл ----------
    while String(quit_requested(pg)) != "True":
        var pressed = String(keys(pg))  # 6 символов: w s a d left right
        var changed = False

        # W — вперёд: новый ray -> коллизия -> если всё ок, присваиваем
        if pressed[byte=0] == "1":
            var candidate = player.move_forward()
            if not engine.check_collision(Player(candidate.copy())):
                player.ray = candidate^
                changed = True

        # S — назад: то же самое
        if pressed[byte=1] == "1":
            var candidate = player.move_backward()
            if not engine.check_collision(Player(candidate.copy())):
                player.ray = candidate^
                changed = True

        # A / стрелка влево — поворот (позиция не меняется)
        if pressed[byte=2] == "1" or pressed[byte=4] == "1":
            player.ray = player.rotate_left()
            changed = True

        # D / стрелка вправо — поворот
        if pressed[byte=3] == "1" or pressed[byte=5] == "1":
            player.ray = player.rotate_right()
            changed = True

        if changed:
            draw_pixels(win, fromhex, frombytes, scale, renderer.render_view(player))
            _ = pg.display.flip()

        _ = pg.time.delay(16)
