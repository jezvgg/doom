from std.math import cos, sin

from render.ray import Ray
from entity import Entity
from render.textures.player import PlayerTexture
from render.textures.color import Color


struct Player(Entity, Copyable):
    comptime speed = 0.1
    var ray: Ray
    var _texture: PlayerTexture

    def __init__(out self, var ray: Ray):
        self.ray = ray^
        self._texture = PlayerTexture()

    def move_forward(self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.x += cos(self.ray.angle) * self.speed
        ray_out.y += sin(self.ray.angle) * self.speed
        return ray_out^

    def move_backward(self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.x -= cos(self.ray.angle) * self.speed
        ray_out.y -= sin(self.ray.angle) * self.speed
        return ray_out^

    def rotate_right(self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.angle += 0.03
        return ray_out^

    def rotate_left(self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.angle -= 0.03
        return ray_out^

    @inline(.always)
    def texture(self, width: Int, u: Float64) -> Color:
        return self._texture[u, width].copy()
