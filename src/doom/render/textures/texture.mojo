from .color import Color


trait Texture(Copyable, Movable, Deinitable, Writable):
    comptime size = 16
    comptime colors = 8

    def __getitem__(self, x: Float64, y: Int) -> Color:
        ...
