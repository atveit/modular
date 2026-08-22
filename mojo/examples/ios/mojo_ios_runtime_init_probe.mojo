# D7 diagnostic: record the native symbol names used by the checked-in
# std.runtime.initialize_runtime implementation. The pinned Mojo binary cannot
# directly import this checkout's std.runtime package, so this source keeps the
# calls explicit rather than claiming to compile or type-check that public API.
# It is deliberately not linked or executed: the symbols currently enter the
# desktop AsyncRT CPU-device/thread-pool implementation.

from std.ffi import external_call


@export("mojo_ios_runtime_initialize_probe")
def mojo_ios_runtime_initialize_probe() abi("C"):
    # Int is only a pointer-width carrier for symbol emission on arm64. The
    # checked-in stdlib uses OptionalPointer; this fixture does not validate
    # the public API's type-level ABI or call semantics.
    _ = external_call[
        "KGEN_CompilerRT_AsyncRT_GetCurrentCPUDevice",
        Int,
    ]()
    var created_runtime = external_call[
        "KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice",
        Int,
    ]()
    external_call["KGEN_CompilerRT_AsyncRT_ReleaseCPUDevice", NoneType](
        created_runtime
    )
