# Bounded iOS serial standard-library probe.
#
# The caller owns and supplies a nul-terminated path inside its application
# sandbox. Only a scalar status crosses the C ABI.

from std.collections import List
from std.ffi import CStringSlice
from std.io import print
from std.os import getenv, makedirs, setenv, unsetenv
from std.os.path import dirname, exists, join
from std.sys._libc_errno import ErrNo, get_errno, set_errno
from std.time import perf_counter_ns


@export("mojo_ios_serial_stdlib_roundtrip")
def mojo_ios_serial_stdlib_roundtrip() abi("C") -> Int64:
    var values = List[Int]()
    for value in range(1, 6):
        values.append(value)

    var total = 0
    for value in values:
        total += value
    if total != 15:
        return 1

    var formatted = "Mojo iOS serial total: {}".format(total)
    if formatted != "Mojo iOS serial total: 15":
        return 2

    if perf_counter_ns() <= 0:
        return 3

    set_errno(ErrNo.EPERM)
    if get_errno() != ErrNo.EPERM:
        return 4
    set_errno(ErrNo.SUCCESS)

    try:
        with open("/mojo-ios-probe/does-not-exist", "r") as missing:
            _ = missing.read()
        return 5
    except:
        if get_errno() != ErrNo.ENOENT:
            return 6

    print("MOJO_IOS_SERIAL_STDLIB_OUTPUT_PASS")
    return 0


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
        var parent = dirname(path_string)
        if join(dirname(parent), "nested", "payload.txt") != path_string:
            return 3
        makedirs(parent, exist_ok=True)
        if not exists(parent):
            return 4
        with open(path_string, "w") as output:
            output.write_bytes("Hello from a Mojo iOS file.".as_bytes())

        with open(path_string, "r") as input:
            var contents = input.read()
            if contents == "Hello from a Mojo iOS file.":
                return 0
            return 5
    except:
        return 6
