# Compile-only iOS standard-library coverage. This source intentionally uses
# APIs that need a runtime/libc implementation when executed; it is never
# linked or run by this fixture.

from std.io import print
from std.math import sqrt
from std.sys._libc_errno import get_errno
from std.time import perf_counter_ns


@export("mojo_ios_stdlib_compile_coverage")
def mojo_ios_stdlib_compile_coverage(value: Int64) abi("C") -> Int64:
    # Builtins and explicit SIMD construction.
    var lanes = SIMD[DType.int32, 4](Int32(value))
    _ = lanes

    # Math, Darwin clock/libc errno, and formatting/output lowering.
    _ = sqrt(Float32(16.0))
    _ = get_errno()
    _ = perf_counter_ns()
    print("Mojo iOS stdlib compile coverage", end="")
    return value
