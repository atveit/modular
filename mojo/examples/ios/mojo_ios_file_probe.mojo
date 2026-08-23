# Bounded iOS standard-library file probe.
#
# The caller owns and supplies a nul-terminated path inside its application
# sandbox. Only a scalar status crosses the C ABI.

from std.ffi import CStringSlice
from std.os import getenv, setenv, unsetenv


@export("mojo_ios_environment_roundtrip")
def mojo_ios_environment_roundtrip() abi("C") -> Int64:
    if not setenv("MOJO_IOS_ENVIRONMENT_PROBE", "set-by-mojo"):
        return 1
    if getenv("MOJO_IOS_ENVIRONMENT_PROBE") != "set-by-mojo":
        return 2
    if not unsetenv("MOJO_IOS_ENVIRONMENT_PROBE"):
        return 3
    if getenv("MOJO_IOS_ENVIRONMENT_PROBE", "missing") != "missing":
        return 4
    return 0


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
