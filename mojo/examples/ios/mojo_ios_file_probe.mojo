# Bounded iOS standard-library file probe.
#
# The caller owns and supplies a nul-terminated path inside its application
# sandbox. Only a scalar status crosses the C ABI.

from std.ffi import CStringSlice


@export("mojo_ios_file_roundtrip")
def mojo_ios_file_roundtrip(
    path: Pointer[Int8, ImmutAnyOrigin]
) abi("C") -> Int64:
    try:
        var path_string = String(CStringSlice(unsafe_from_ptr=path))
        with open(path_string, "w") as output:
            output.write_bytes("Hello from a Mojo iOS file.".as_bytes())

        with open(path_string, "r") as input:
            var contents = input.read()
            if contents == "Hello from a Mojo iOS file.":
                return 0
            return 2
    except:
        return 1
