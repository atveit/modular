# Compile-only import inventory for every top-level stdlib package. Importing a
# package does not establish runtime support for its APIs; this catches target
# parsing/lowering regressions and keeps unsupported packages visible.

import std._plugin
import std.algorithm
import std.atomic
import std.base64
import std.benchmark
import std.bit
import std.builtin
import std.collections
import std.compile
import std.complex
import std.documentation
import std.ffi
import std.format
import std.gpu
import std.hashlib
import std.io
import std.iter
import std.itertools
import std.logger
import std.math
import std.memory
import std.origin
import std.os
import std.pathlib
import std.prelude
import std.pwd
import std.python
import std.random
import std.reflection
import std.runtime
import std.stat
import std.subprocess
import std.sys
import std.tempfile
import std.testing
import std.time
import std.traits
import std.utils


@export("mojo_ios_stdlib_package_inventory")
def mojo_ios_stdlib_package_inventory() abi("C") -> Int64:
    return 38
