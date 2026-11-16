from std.math import cos, floor, sin, atan2

from .raycaster import Raycaster
from .screen import Screen
from player import Player
from .textures.texture import Texture


@fieldwise_init
struct Renderer[T: Texture](Movable, Writable):
    var caster: Raycaster
    var texture: Self.T


    def render_view(self, player: Player) -> Screen:
        var screen = Screen()
        var hits = self.caster.cast_view(player)

        for i, hit in enumerate(hits):

            var side = hit.ray.x - floor(hit.ray.x) == 0
            var texX = hit.ray.y - floor(hit.ray.y) if side else hit.ray.x - floor(hit.ray.x)
            if (side and cos(hit.ray.angle) > 0.0) or
                (not side and sin(hit.ray.angle) < 0.0):
                texX = 1.0 - texX

            var perp_distance = hit.distance * cos(hit.ray.angle - player.ray.angle)
            var _floor = Int(Float64(screen.height) / 2.0 - Float64(screen.height) / perp_distance / 2.0)
            var wall_height = screen.height - _floor * 2

            for height in range(screen.height):
                if not (height > _floor and height <= screen.height - _floor and hit.distance <= self.caster.depth):
                    continue
                var texY = ((height - _floor) * 16 // wall_height) & 15
                var color = self.texture[texX, texY]
                color.value = UInt8((self.caster.depth - hit.distance) / self.caster.depth * Float64(color.value))
                screen[height, i] = color

        # Entities drawing
        # Player view
        sort(self.caster.map[].entities[:],
            lambda (p1: Player, p2: Player) -> Bool:
            ((player.ray.x - p1.ray.x) ** 2 + (player.ray.y - p1.ray.y) ** 2) >
            ((player.ray.x - p2.ray.x) ** 2 + (player.ray.y - p2.ray.y) ** 2)
            )

        for entity in self.caster.map[].entities:
            var dx = entity.ray.x - player.ray.x
            var dy = entity.ray.y - player.ray.y
            var ca = cos(player.ray.angle)
            var sa = sin(player.ray.angle)

            var depth   =  dx * ca + dy * sa
            var lateral = -dx * sa + dy * ca

            if depth <= 0.2 or depth >= self.caster.depth: continue

            var centerX = (atan2(lateral, depth) + self.caster.FOV / 2.0) / self.caster.FOV * Float64(screen.width)
            var sprite_width = 2.0 * atan2(entity.width / 2.0, depth) / self.caster.FOV * Float64(Screen.width)
            var left = centerX - sprite_width / 2.0

            for width in range(Int(left), Int(left + sprite_width)):
                if width < 0 or width >= Screen.width:
                    continue
                if depth > hits[width].distance * cos(hits[width].ray.angle - player.ray.angle):
                    continue

                var bottom = Float64(Screen.height) / 2.0 + Float64(Screen.height) / (2.0 * depth)
                var sprite_height = entity.width * Float64(Screen.height) / depth
                var top = bottom - sprite_height
                var texX = (Float64(width) - left) / sprite_width

                for height in range(Int(top), Int(bottom)):
                    if height < 0 or height >= Screen.height:
                        continue
                    var texY = Int((Float64(height) - top) * 16.0 / sprite_height) & 15
                    var color = entity.texture(texY, texX)
                    if color.invisible: continue
                    color.value = UInt8((self.caster.depth - depth) / self.caster.depth * Float64(color.value))
                    screen[height, width] = color

        return screen^
