from std.math import cos, floor, sin
from std.memory import ArcPointer

from map import Map
from player import Player
from .screen import Screen
from .ray import Ray, RayAxis, Hit



struct Raycaster:
    comptime FOV: Float64 = 3.14159 / 3.0
    comptime depth: Float64 = 8.0
    var map: ArcPointer[Map[Player]]


    def __init__(out self, var map: ArcPointer[Map[Player]]):
        self.map = map^


    def cast(self, var ray: Ray) -> Hit:
        var axisx = RayAxis(ray.x, cos(ray.angle))
        var axisy = RayAxis(ray.y, sin(ray.angle))

        var dist: Float64 = 0
        while not (self.map[][axisx.pos, axisy.pos] or dist >= self.depth):
            if axisx.distance < axisy.distance:
                dist = axisx.update()
            else:
                dist = axisy.update()

        dist = min(dist, self.depth)
        ray.x += cos(ray.angle) * dist
        ray.y += sin(ray.angle) * dist
        return Hit(ray^, dist)


    def cast_view(self, player: Player) -> Array[Hit, Screen.width]:
        var hits = Array[Hit, Screen.width](uninitialized=True)

        for i in range(Screen.width):
            var ray = player.ray.copy()
            ray.angle -= (self.FOV / 2.0) - ((self.FOV / Screen.width) * Float64(i))
            hits[i] = self.cast(ray^)

        return hits^
