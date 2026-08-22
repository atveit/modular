# Symbol-only probe: std.ffi._Global lazy storage initialization. This is not
# an ABI, synchronization, link, or execution test.

from std.ffi import _Global


def _initialize_global_value() -> Int64:
    return 0


comptime _GLOBAL_VALUE = _Global["mojo_ios_global_symbol_probe", _initialize_global_value]


@export("mojo_ios_global_symbol_probe")
def mojo_ios_global_symbol_probe() abi("C") -> Int64:
    try:
        var value = _GLOBAL_VALUE.get_or_create_ptr()
        value[] += 1
        return value[]
    except:
        return -1
