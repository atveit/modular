# Runtime-backed iOS probe. Unlike mojo_ios_smoke.mojo, this deliberately uses
# String concatenation and integer formatting, which require the Mojo runtime.

@export("mojo_runtime_string_byte_count")
def mojo_runtime_string_byte_count(value: Int64) abi("C") -> Int64:
    var text = String("allocation-") + String(value)
    return Int64(text.byte_length())
