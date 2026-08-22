# D6 static-runtime link probe. Unlike the runtime-free smoke fixture, this
# deliberately allocates a String so the emitted object has a small, inspectable
# CompilerRT dependency surface. It has no Mojo `main`; the native C host owns
# process startup and calls the exported function.

from std.collections.string import String


@export("mojo_ios_runtime_string_length")
def mojo_ios_runtime_string_length(value_to_format: Int64) abi("C") -> Int64:
    # The caller-controlled value prevents compile-time folding; the fixed
    # suffix exceeds inline storage, so construction must allocate.
    var value = String(
        value_to_format,
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    )
    return Int64(value.byte_length())
