from std.math import cos, sin
from ray import Ray


@fieldwise_init
struct Player:
    comptime speed = 0.1
    var ray: Ray

    def move_forward(mut self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.x += cos(self.ray.angle) * self.speed
        ray_out.y += sin(self.ray.angle) * self.speed
        return ray_out^

    def move_backward(mut self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.x -= cos(self.ray.angle) * self.speed
        ray_out.y -= sin(self.ray.angle) * self.speed
        return ray_out^

    def rotate_right(mut self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.angle += 0.03
        return ray_out^

    def rotate_left(mut self) -> Ray:
        var ray_out = self.ray.copy()
        ray_out.angle -= 0.03
        return ray_out^
