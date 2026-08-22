# D7 diagnostic: compile the checked-in public std.runtime API and inspect its
# native dependencies. It is deliberately not linked or executed: the symbols
# currently enter the desktop AsyncRT CPU-device/thread-pool implementation.

from std.runtime import initialize_runtime


@export("mojo_ios_runtime_initialize_probe")
def mojo_ios_runtime_initialize_probe() abi("C"):
    initialize_runtime()
