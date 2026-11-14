from std.math import cos, sin, sqrt
from std.collections import BitSet

from map import Map
from player import Player
from screen import Screen
from ray import Ray


struct Raycaster:
    comptime FOV: Float64 = 3.14159 / 3.0
    comptime depth: Float64 = 5.0
    comptime step: Float64 = 0.01
    var map: Map


    def __init__(out self, var map: Map):
        self.map = map^


    def cast(self, _ray: Ray) -> Float64:
        var start = _ray.copy()
        var ray = _ray.copy()
        for _ in range(Int64(self.depth / self.step)):
            ray.x += cos(ray.angle) * self.step
            ray.y += sin(ray.angle) * self.step
            if  (ray.x <= 0 or ray.x >= Map.size) or \
                (ray.y <= 0 or ray.y >= Map.size) or \
                self.map[Int(ray.x), Int(ray.y)]:
                    break

        return sqrt((ray.x - start.x) ** 2 + (ray.y - start.y) ** 2)


    def render(self, player: Player) -> Screen:
        var screen = Screen()
        var rays = Array[Ray, screen.width](fill=player.ray)

        for i in range(screen.width):
            rays[i].angle = player.ray.angle - (self.FOV / 2.0) + ((self.FOV / screen.width) * Float64(i))
            var distance = self.cast(rays[i])
            var floor = Int(Float64(screen.height) / 2.0 - Float64(screen.height) / distance / 2.0)
            for height in range(screen.height):
                if (height > floor and height <= screen.height - floor and distance <= self.depth):
                    screen.value[height][i] = Int8((self.depth - distance) / self.depth * 16.0)

        return screen^
