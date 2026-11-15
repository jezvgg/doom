from std.math import cos, floor, sin

from raycaster import Raycaster
from screen import Screen
from player import Player
from texture import Texture


@fieldwise_init
struct Renderer:
    var caster: Raycaster
    var texture: Texture

    def render_view(self, player: Player) -> Screen:
        var screen = Screen()
        var hits = self.caster.cast_view(player)

        for i, hit in enumerate(hits):

            var side = hit.ray.x - floor(hit.ray.x) == 0
            var texX = hit.ray.y - floor(hit.ray.y) if side else hit.ray.x - floor(hit.ray.x)
            if (side and cos(hit.ray.angle) > 0.0) or
                (not side and sin(hit.ray.angle) < 0.0):
                texX = 1.0 - texX

            var _floor = Int(Float64(screen.height) / 2.0 - Float64(screen.height) / hit.distance / 2.0)
            var wall_height = screen.height - _floor * 2

            for height in range(screen.height):
                var texY = ((height - _floor) * 16 // wall_height) & 15
                if (height > _floor and height <= screen.height - _floor and hit.distance <= self.caster.depth):
                    var color = self.texture[texX, texY]
                    color.value = UInt8((self.caster.depth - hit.distance) / self.caster.depth * Float64(color.value))
                    screen[height, i] = color

        return screen^
