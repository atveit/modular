# Symbol-only probe: Error construction/formatting without throwing across C.

@export("mojo_ios_error_symbol_probe")
def mojo_ios_error_symbol_probe(value: Int64) abi("C") -> Int64:
    var error = Error("iOS error probe value=", value)
    _ = error
    return value
