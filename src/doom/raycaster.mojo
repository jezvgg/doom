from std.math import floor
from std.collections import BitSet

from map import Map
from player import Player
from screen import Screen
from ray import Ray, RayDDA



struct Raycaster:
    comptime FOV: Float64 = 3.14159 / 3.0
    comptime depth: Float64 = 5.0
    var map: Map


    def __init__(out self, var map: Map):
        self.map = map^


    def cast(self, var _ray: Ray) -> Float64:
        var ray = RayDDA(_ray^)
        var dist: Float64 = 0
        while not (self.map[ray.x.pos, ray.y.pos] or dist >= self.depth):
            if ray.x.distance < ray.y.distance:
                dist = ray.x.update()
            else:
                dist = ray.y.update()
        return min(dist, self.depth)


    def render(self, player: Player) -> Screen:
        var screen = Screen()

        for i in range(screen.width):
            var ray = player.ray.copy()
            ray.angle -= (self.FOV / 2.0) - ((self.FOV / screen.width) * Float64(i))
            var distance = self.cast(ray^)
            var _floor = Int(Float64(screen.height) / 2.0 - Float64(screen.height) / distance / 2.0)
            for height in range(screen.height):
                if (height > _floor and height <= screen.height - _floor and distance <= self.depth):
                    screen.value[i][height] = Int8((self.depth - distance) / self.depth * 16.0)

        return screen^
