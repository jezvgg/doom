from std.python import Python, PythonObject

from engine import Engine
from map import Map
from player import Player
from raycaster import Raycaster
from ray import Ray
from screen import Screen

# во сколько раз увеличить 128x128 при показе в окне
comptime SCALE: Int = 4

# сколько ступеней яркости пишет raycaster: Screen.value = Int8((depth - distance) / depth * GRAY_SHADES).
# 0 — пусто, 1..GRAY_SHADES — стена. В картинке ступень тянется на 0..255.
comptime GRAY_SHADES: Int = 16

# "00", "01", ... "ff" — hex-пара по индексу палитры (0..255)
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


def screen_to_image(
    fromhex: PythonObject,
    frombytes: PythonObject,
    screen: Screen,
) raises -> PythonObject:
    """Screen -> pygame.Surface 128x128, ровно один байт (индекс палитры) на пиксель.

    Пиксель (col, row) берём из screen.value[col][row]: так объявлен Screen —
    внешний массив по ширине (столбцы), внутренний по высоте (строки).
    Байты собираем в порядке строк (сверху вниз, слева направо) — этого ждёт image.frombytes.

    Почему hex: Mojo умеет отдать в Python только строку; bytes.fromhex превращает
    ASCII-пары в настоящий bytes за ~0.01 мс на 16384 пикселя.
    Когда появятся текстуры — сюда же приходит номер цвета/текселя, а set_palette
    раскрашивает индексы настоящей палитрой, без пересборки формата.
    """
    var hex = String()
    for row in range(Screen.height):
        for col in range(Screen.width):
            var level = Int(screen.value[col][row])
            var idx = level * 255 // GRAY_SHADES
            if idx < 0:
                idx = 0
            elif idx > 255:
                idx = 255
            var begin = idx * 2
            hex += HEXPAIRS[byte=begin:begin + 2]
    var raw = fromhex(hex)
    return frombytes(raw, Python.tuple(Screen.width, Screen.height), "P")


def draw_pixels(
    win: PythonObject,
    fromhex: PythonObject,
    frombytes: PythonObject,
    set_palette: PythonObject,
    scale: PythonObject,
    screen: Screen,
) raises:
    """Один кадр: пиксели Screen -> поверхность 128x128 -> растяжка SCALE -> окно."""
    var img = screen_to_image(fromhex, frombytes, screen)
    _ = set_palette(img)
    var big = scale(img, Python.tuple(Screen.width * SCALE, Screen.height * SCALE))
    _ = win.blit(big, Python.tuple(0, 0))


def main() raises:
    var player = Player(Ray(4.5, 4.5, 0.0))
    var caster = Raycaster(Map())
    var engine = Engine(Map(), Raycaster(Map()))

    # ---------- окно pygame ----------
    var pg = Python.import_module("pygame")
    _ = pg.init()
    var win = pg.display.set_mode(Python.tuple(Screen.width * SCALE, Screen.height * SCALE))
    _ = pg.display.set_caption("doom.mojo")

    # Python-функции создаём один раз, а не каждый кадр
    var fromhex = Python.evaluate("bytes.fromhex")
    var frombytes = pg.image.frombytes
    # индексы 0..255 -> серый: 0 = чёрный фон, 255 = белый. Для текстур заменить на свою палитру.
    var set_palette = Python.evaluate("lambda img: img.set_palette([(i, i, i) for i in range(256)])")
    var scale = pg.transform.scale

    var keys = Python.evaluate(KEYS_PY)
    var quit_requested = Python.evaluate(QUIT_PY)

    draw_pixels(win, fromhex, frombytes, set_palette, scale, caster.render(player))
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
            draw_pixels(win, fromhex, frombytes, set_palette, scale, caster.render(player))
            _ = pg.display.flip()

        _ = pg.time.delay(16)
