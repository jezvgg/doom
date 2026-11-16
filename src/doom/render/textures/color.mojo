struct Color(Copyable, Movable):
    var hue: UInt8
    var saturation: UInt8
    var value: UInt8
    var invisible: Bool


    def __init__(
        out self,
        var hue: UInt8,
        var saturation: UInt8,
        var value: UInt8,
        var invisible: Bool = False,
    ):
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.invisible = invisible

    comptime NONE = Color(0, 0, 0)
    comptime SKY = Self.NONE
    comptime FLOOR = Self.NONE
