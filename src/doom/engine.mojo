from std.math import floor
from std.memory import ArcPointer

from map import Map
from player import Player
from render.raycaster import Raycaster


@fieldwise_init
struct Engine(Writable):
    comptime min_distance = 0.05
    var map: ArcPointer[Map[Player]]
    var caster: Raycaster

    def check_collision(self, player: Player) -> Bool:
        return self.caster.cast(player.ray.copy()).distance < 0.1
