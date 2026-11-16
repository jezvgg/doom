from .textures.color import Color


@fieldwise_init
struct Screen:
    comptime height = 128
    comptime width = 128
    comptime Row = Array[UInt8, Self.width]
    var hue: Array[Self.Row, Self.height]
    var saturation: Array[Self.Row, Self.height]
    var value: Array[Self.Row, Self.height]


    def __init__(out self):
        self.hue = Array[Self.Row, Self.height](fill=Self.Row(fill=0))
        self.saturation = Array[Self.Row, Self.height](fill=Self.Row(fill=0))
        self.value = Array[Self.Row, Self.height](fill=Self.Row(fill=0))


    def __getitem__(self, height: Int, width: Int) -> Color:
        return Color(
            self.hue[height][width],
            self.saturation[height][width],
            self.value[height][width]
        )

    def __setitem__(mut self, height: Int, width: Int, color: Color):
        self.hue[height][width] = color.hue
        self.saturation[height][width] = color.saturation
        self.value[height][width] = color.value
