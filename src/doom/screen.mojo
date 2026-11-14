
struct Screen:
    comptime height = 128
    comptime width = 128
    var value: Array[Array[Int8, Self.height], Self.width]

    def __init__(out self):
        self.value = Array[Array[Int8, self.height], self.width]()
