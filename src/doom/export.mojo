"""Python-расширение движка doom.mojo: наружу торчат ровно четыре класса.

    Map()                        — уровень (стены + сущности) за ArcPointer
    Player(x, y, angle)          — игрок; move_*/rotate_* возвращают НОВЫЙ Player
    Engine(map)                  — коллизии
    Renderer(map)                — рисует кадр в hex-RGB строку

Всё остальное (Ray, Hit, Color, Screen, текстуры, Raycaster) — внутренние
детали движка и в Python не попадает: Renderer/Engine сами собирают себе
Raycaster и BricksTexture из переданного Map.

Сборка:

    mojo build src/doom/export.mojo --emit shared-lib -o src/doom/export.so -I src/doom

импорт из Python: `from doom import export`.

Наружу торчит только PyInit_export с abi("C") — его ищет CPython. Всё
остальное регистрируется в PythonModuleBuilder, и Mojo сам генерирует
C-обёртки, поэтому зарегистрированные функции могут быть `raises`:
ошибка Mojo превращается в Python-исключение.

Два ограничения Python-биндингов в Mojo 1.2, из-за которых рядом с каждым
типом живёт маленький адаптер Py<Имя>: зарегистрированный тип обязан
реализовывать Writable (`__repr__`), а функции-методы обязаны быть
`@staticmethod` и принимать `self_ptr: Pointer[Self]`.
"""

from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.memory import ArcPointer
from std.origin import MutUnsafeAnyOrigin
from std.os import abort

from engine import Engine
from map import Map
from pixels import screen_to_hex
from player import Player
from render.ray import Ray
from render.raycaster import Raycaster
from render.render import Renderer
from render.screen import Screen
from render.textures.bricks import BricksTexture


comptime MapArg = ArcPointer[Map[Player]]
comptime LevelMap = Map[Player]
comptime BrickRenderer = Renderer[BricksTexture]


# ---------------------------------------------------------------------------
# Map — уровень. В Mojo это Map[Player] за ArcPointer, поэтому один и тот же
# уровень видят Raycaster, Renderer и Engine (у них внутри ArcPointer).
# ---------------------------------------------------------------------------


struct PyMap:
    @staticmethod
    def init(out self: MapArg, args: PythonObject, kwargs: PythonObject) raises:
        self = ArcPointer(LevelMap())

    @staticmethod
    def is_wall(
        self_ptr: Pointer[mut=True, MapArg, MutUnsafeAnyOrigin], x_obj: PythonObject, y_obj: PythonObject
    ) raises -> PythonObject:
        return PythonObject(Bool(self_ptr[][][Int(py=x_obj), Int(py=y_obj)]))

    @staticmethod
    def add_entity(
        self_ptr: Pointer[mut=True, MapArg, MutUnsafeAnyOrigin], player_obj: PythonObject
    ) raises:
        var player = player_obj.downcast_value_ptr[Player]()
        self_ptr[][].entities.append(player[].copy())

    @staticmethod
    def entities_count(
        self_ptr: Pointer[mut=True, MapArg, MutUnsafeAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(len(self_ptr[][].entities))

    @staticmethod
    def entity(
        self_ptr: Pointer[mut=True, MapArg, MutUnsafeAnyOrigin], index_obj: PythonObject
    ) raises -> PythonObject:
        return PythonObject(alloc=self_ptr[][].entities[Int(py=index_obj)].copy())

    @staticmethod
    def clear_entities(self_ptr: Pointer[mut=True, MapArg, MutUnsafeAnyOrigin]) raises:
        self_ptr[][].entities.clear()


# ---------------------------------------------------------------------------
# Player — вся математика движения из player.mojo.
#
# Player — value-тип: move_forward/rotate_left и т.п. НЕ меняют игрока, а
# возвращают нового. Поэтому кадр в Python выглядит так:
#     candidate = player.move_forward()
#     if not engine.check_collision(candidate): player = candidate
# ---------------------------------------------------------------------------


struct PyPlayer:
    @staticmethod
    def init(out self: Player, args: PythonObject, kwargs: PythonObject) raises:
        if len(args) != 3:
            raise Error("Player(x, y, angle) takes exactly 3 arguments")
        self = Player(Ray(Float64(py=args[0]), Float64(py=args[1]), Float64(py=args[2])))

    @staticmethod
    def x(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        return PythonObject(self_ptr[].ray.x)

    @staticmethod
    def y(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        return PythonObject(self_ptr[].ray.y)

    @staticmethod
    def angle(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        return PythonObject(self_ptr[].ray.angle)

    @staticmethod
    def move_forward(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        var player = self_ptr[].copy()
        player.ray = player.move_forward()
        return PythonObject(alloc=player^)

    @staticmethod
    def move_backward(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        var player = self_ptr[].copy()
        player.ray = player.move_backward()
        return PythonObject(alloc=player^)

    @staticmethod
    def rotate_left(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        var player = self_ptr[].copy()
        player.ray = player.rotate_left()
        return PythonObject(alloc=player^)

    @staticmethod
    def rotate_right(self_ptr: Pointer[mut=True, Player, MutUnsafeAnyOrigin]) raises -> PythonObject:
        var player = self_ptr[].copy()
        player.ray = player.rotate_right()
        return PythonObject(alloc=player^)


# ---------------------------------------------------------------------------
# Engine — коллизии. Raycaster собирается сам из того же Map.
# ---------------------------------------------------------------------------


struct PyEngine:
    @staticmethod
    def init(out self: Engine, args: PythonObject, kwargs: PythonObject) raises:
        if len(args) != 1:
            raise Error("Engine(map) takes exactly 1 argument")
        var map_ptr = args[0].downcast_value_ptr[MapArg]()
        self = Engine(map_ptr[].copy(), Raycaster(map_ptr[].copy()))

    @staticmethod
    def check_collision(
        self_ptr: Pointer[mut=True, Engine, MutUnsafeAnyOrigin], player_obj: PythonObject
    ) raises -> PythonObject:
        var player = player_obj.downcast_value_ptr[Player]()
        return PythonObject(self_ptr[].check_collision(player[].copy()))


# ---------------------------------------------------------------------------
# Renderer — Raycaster + BricksTexture собираются сами; Screen остаётся
# внутри, наружу отдаём готовый кадр в виде hex-RGB строки (6 символов на
# пиксель, построчно), из неё Python делает bytes.fromhex(...).
# ---------------------------------------------------------------------------


struct PyRenderer:
    @staticmethod
    def init(out self: BrickRenderer, args: PythonObject, kwargs: PythonObject) raises:
        if len(args) != 1:
            raise Error("Renderer(map) takes exactly 1 argument")
        var map_ptr = args[0].downcast_value_ptr[MapArg]()
        self = BrickRenderer(Raycaster(map_ptr[].copy()), BricksTexture())

    @staticmethod
    def render(
        self_ptr: Pointer[mut=True, BrickRenderer, MutUnsafeAnyOrigin], player_obj: PythonObject
    ) raises -> PythonObject:
        var player = player_obj.downcast_value_ptr[Player]()
        var screen = self_ptr[].render_view(player[].copy())
        return PythonObject(screen_to_hex(screen))

    @staticmethod
    def width() raises -> PythonObject:
        return PythonObject(Screen.width)

    @staticmethod
    def height() raises -> PythonObject:
        return PythonObject(Screen.height)


# ---------------------------------------------------------------------------
# Модуль
# ---------------------------------------------------------------------------


@export
def PyInit_export() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("export")

        _ = (
            m.add_type[MapArg]("Map")
            .def_py_init[PyMap.init]()
            .def_method[PyMap.is_wall]("is_wall")
            .def_method[PyMap.add_entity]("add_entity")
            .def_method[PyMap.entities_count]("entities_count")
            .def_method[PyMap.entity]("entity")
            .def_method[PyMap.clear_entities]("clear_entities")
        )
        _ = (
            m.add_type[Player]("Player")
            .def_py_init[PyPlayer.init]()
            .def_method[PyPlayer.x]("x")
            .def_method[PyPlayer.y]("y")
            .def_method[PyPlayer.angle]("angle")
            .def_method[PyPlayer.move_forward]("move_forward")
            .def_method[PyPlayer.move_backward]("move_backward")
            .def_method[PyPlayer.rotate_left]("rotate_left")
            .def_method[PyPlayer.rotate_right]("rotate_right")
        )
        _ = (
            m.add_type[Engine]("Engine")
            .def_py_init[PyEngine.init]()
            .def_method[PyEngine.check_collision]("check_collision")
        )
        _ = (
            m.add_type[BrickRenderer]("Renderer")
            .def_py_init[PyRenderer.init]()
            .def_method[PyRenderer.render]("render")
            .def_staticmethod[PyRenderer.width]("width")
            .def_staticmethod[PyRenderer.height]("height")
        )

        return m.finalize()
    except e:
        abort(String("error creating export module: ", e))
