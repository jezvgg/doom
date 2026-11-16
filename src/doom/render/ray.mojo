from std.math import cos, sin


@fieldwise_init
struct Ray(Copyable, Movable, Writable):
    var x: Float64
    var y: Float64
    var angle: Float64


@fieldwise_init
struct Hit(Copyable, Movable, Writable):
    var ray: Ray
    var distance: Float64


struct RayAxis(Copyable, Movable, Writable):
    var pos: Int
    var direction: Float64
    var step: Int
    var distance: Float64

    def __init__(out self, var pos: Float64, var direction: Float64):
        self.pos = Int(pos)
        self.direction = direction
        self.step = 1 if direction >= 0.0 else -1
        self.distance = (Float64(self.pos + (self.step + 1) / 2) - pos) / direction

    def update(mut self) -> Float64:
        var dist = self.distance.copy()
        self.distance += 1.0 / abs(self.direction)
        self.pos += self.step
        return dist
