@fieldwise_init
struct Color(Copyable, Movable):
    var hue: UInt8
    var saturation: UInt8
    var value: UInt8

    comptime NONE = Color(0, 0, 0)
    comptime SKY = Self.NONE
    comptime FLOOR = Self.NONE
