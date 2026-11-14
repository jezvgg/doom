from std.collections import List
from std.python import Python, PythonObject

from engine import Engine
from map import Map
from player import Player
from raycaster import Raycaster
from ray import Ray
from screen import Screen

# во сколько раз увеличить 128x128 при показе в окне
comptime SCALE: Int = 4

# сколько ступеней яркости пишет raycaster: Screen.value = Int8(distance / depth * GRAY_SHADES).
# 0 — пусто (рисуем чёрным фоном), 1..GRAY_SHADES — стена, дальше ярче.
# В окне ступень растягиваем на весь диапазон 0..255: level * 255 // GRAY_SHADES.
comptime GRAY_SHADES: Int = 16

# какие клавиши зажаты: w s a d left right -> строка из '0'/'1'
comptime KEYS_PY: String = "lambda pg: ''.join('1' if k else '0' for k in (pg.key.get_pressed()[pg.K_w], pg.key.get_pressed()[pg.K_s], pg.key.get_pressed()[pg.K_a], pg.key.get_pressed()[pg.K_d], pg.key.get_pressed()[pg.K_LEFT], pg.key.get_pressed()[pg.K_RIGHT]))"

# «пора закрывать окно»: крестик или Esc. Считается в Python, Mojo читает результат.
comptime QUIT_PY: String = "lambda pg: any(e.type == pg.QUIT or (e.type == pg.KEYDOWN and e.key == pg.K_ESCAPE) for e in pg.event.get())"


def draw_screen(
    win: PythonObject,
    draw_rect: PythonObject,
    clear: PythonObject,
    colors: List[PythonObject],
    screen: Screen,
) raises:
    """Screen -> окно: каждый непрерывный отрезок столбца с одинаковой яркостью = один прямоугольник.

    Пиксели в Python не перегоняем вообще: 128 столбцов -> несколько десятков draw.rect.
    """
    _ = clear(win)

    for col in range(Screen.width):
        var row = 0
        while row < Screen.height:
            var level = Int(screen.value[row][col])
            if level == 0:
                row += 1
                continue
            # тянем отрезок, пока яркость не изменится
            var start = row
            while row < Screen.height and Int(screen.value[row][col]) == level:
                row += 1
            var shade = level * 255 // GRAY_SHADES
            if shade > 255:
                shade = 255
            _ = draw_rect(
                win,
                colors[shade],
                Python.tuple(col * SCALE, start * SCALE, SCALE, (row - start) * SCALE),
            )


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
    var draw_rect = pg.draw.rect
    var clear = Python.evaluate("lambda win: win.fill((0, 0, 0))")
    # 256 готовых кортежей цвета: (0,0,0), (1,1,1), ... (255,255,255).
    # держим их списком Mojo, чтобы не боксить int и не лезть в Python на каждый прямоугольник
    var colors = List[PythonObject]()
    for i in range(256):
        colors.append(Python.tuple(i, i, i))

    draw_screen(win, draw_rect, clear, colors, caster.render(player))
    _ = pg.display.flip()

    # ---------- игровой цикл ----------
    var keys = Python.evaluate(KEYS_PY)
    var quit_requested = Python.evaluate(QUIT_PY)

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

        # A / стрелка влево — поворот (коллизия не нужна, позиция не меняется)
        if pressed[byte=2] == "1" or pressed[byte=4] == "1":
            player.ray = player.rotate_left()
            changed = True

        # D / стрелка вправо — поворот
        if pressed[byte=3] == "1" or pressed[byte=5] == "1":
            player.ray = player.rotate_right()
            changed = True

        # перерисовываем только если игрок реально сдвинулся/повернулся
        if changed:
            draw_screen(win, draw_rect, clear, colors, caster.render(player))
            _ = pg.display.flip()

        _ = pg.time.delay(16)

    _ = pg.quit()
