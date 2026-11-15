from std.math import floor

from map import Map
from player import Player
from raycaster import Raycaster


@fieldwise_init
struct Engine:
    comptime min_distance = 0.05
    var map: Map
    var caster: Raycaster

    def check_collision(self, player: Player) -> Bool:
        var mut_player = player.copy()
        return self.caster.cast(mut_player.ray.copy()) < 0.1
