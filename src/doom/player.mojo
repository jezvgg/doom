from std.math import cos, sin
from ray import Ray


@fieldwise_init
struct Player(Copyable):
    comptime speed = 0.1
    var ray: Ray

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
