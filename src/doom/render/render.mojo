from std.math import cos, floor, sin, atan2

from .raycaster import Raycaster
from .screen import Screen
from player import Player
from .textures.texture import Texture


@fieldwise_init
struct Renderer[T: Texture](Movable):
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
        sort(self.caster.map[].entities,
            cmp_fn = lambda (p1: Player, p2: Player) -> Float64:
            sqrt((player.ray.x - p1.ray.x) ** 2 + (player.ray.y - p1.ray.y) ** 2) * cos(player.ray.angle - p1.ray.angle)
            )

        for entity in self.caster.map[].entities:
            var dx = entity.ray.x - player.ray.x
            var dy = entity.ray.y - player.ray.y
            var ca = cos(player.ray.angle)
            var sa = sin(player.ray.angle)

            var depth   =  dx * ca + dy * sa
            var lateral = -dx * sa + dy * ca

            if depth <= 0.2 or depth >= 8.0: continue

            var centerX = (atan2(lateral, depth) + self.caster.FOV / 2.0) / self.caster.FOV * Float64(screen.width)
            var sprite_width = atan2(entity.width / 2.0, depth) / self.catser.FOV * Float64(Screen.width)

            for width in range(centerX - sprite_width, centerX + sprite_width):
                if depth > hits[i].distance * cos(hits[i].ray.angle - player.ray.angle):
                    continue

                var bottom = Float64(Screen.height) / 2.0 + Float64(Screen.height) / (2.0 * depth)
                var sprite_height = entity.width * Float64(Screen.height) / depth
                var top = _floor - sprite_height
                var texX = (width - (centerX - sprite_width)) / sprite_width

                for height in range(top, bottom):
                    var texY = ((height - _floor) * entity.texture.height // sprite_height) & 15
                    var color = entity.texture(texX, texY)
                    color.value = UInt8((self.caster.depth - depth) / self.caster.depth * Float64(color.value))
                    screen[height, i] = color

        return screen^
