from render.textures.color import Color


trait Entity(Deinitable, Movable):
    comptime width: Float64 = 0.75

    def texture(self, width: Int, u: Float64) -> Color:
        ...
