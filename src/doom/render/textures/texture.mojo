from .color import Color


trait Texture(Copyable, Movable, Deinitable):
    comptime size = 16
    comptime colors = 8

    # x — горизонтальная доля ширины тайла 0..1, y — номер строки 0..size-1
    def __getitem__(self, x: Float64, y: Int) -> Color:
        ...
