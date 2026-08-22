# Runtime-free C ABI fixture for the first iOS Simulator integration step.
#
# Keep this module deliberately small: it uses only builtin scalar and pointer
# types, does not import std, allocate, initialize Mojo runtime state, or
# return Mojo-owned values.  That makes its object usable while the iOS static
# runtime and core stdlib work are still in progress.

@export("mojo_add")
def mojo_add(lhs: Int64, rhs: Int64) abi("C") -> Int64:
    return lhs + rhs


@export("mojo_hello_utf8")
def mojo_hello_utf8(
    output: UnsafePointer[UInt8, MutAnyOrigin], capacity: Int64
) abi("C") -> Int64:
    # "Hello from Mojo on iOS." is 23 ASCII bytes.  The function returns the
    # required byte count whether or not the caller supplied enough capacity.
    comptime message_length = 23
    if capacity <= 0:
        return message_length

    var count = capacity if capacity < message_length else message_length
    var i: Int64 = 0
    while i < count:
        if i == 0:
            output[i] = 72  # H
        elif i == 1:
            output[i] = 101  # e
        elif i == 2:
            output[i] = 108  # l
        elif i == 3:
            output[i] = 108  # l
        elif i == 4:
            output[i] = 111  # o
        elif i == 5:
            output[i] = 32  # space
        elif i == 6:
            output[i] = 102  # f
        elif i == 7:
            output[i] = 114  # r
        elif i == 8:
            output[i] = 111  # o
        elif i == 9:
            output[i] = 109  # m
        elif i == 10:
            output[i] = 32  # space
        elif i == 11:
            output[i] = 77  # M
        elif i == 12:
            output[i] = 111  # o
        elif i == 13:
            output[i] = 106  # j
        elif i == 14:
            output[i] = 111  # o
        elif i == 15:
            output[i] = 32  # space
        elif i == 16:
            output[i] = 111  # o
        elif i == 17:
            output[i] = 110  # n
        elif i == 18:
            output[i] = 32  # space
        elif i == 19:
            output[i] = 105  # i
        elif i == 20:
            output[i] = 79  # O
        elif i == 21:
            output[i] = 83  # S
        elif i == 22:
            output[i] = 46  # .
        i += 1

    return message_length
