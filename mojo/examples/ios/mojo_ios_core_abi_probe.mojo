# N5 C-ABI hardening fixture. Mojo owns the storage behind the typed pointer;
# native callers must treat it as an opaque handle and call destroy exactly
# once. No Mojo layout or Error crosses the ABI.

from std.memory import Allocation, Layout, OptionalPointer, alloc, dealloc


@export("mojo_ios_handle_create")
def mojo_ios_handle_create(
    value: Int64
) abi("C") -> Pointer[Int64, MutUntrackedOrigin]:
    var allocation = alloc(Layout[Int64].single())
    allocation.unsafe_ptr()[] = value
    return allocation^.unsafe_leak()


@export("mojo_ios_handle_read")
def mojo_ios_handle_read(
    handle: OptionalPointer[Int64, MutUntrackedOrigin],
    output: OptionalPointer[Int64, MutAnyOrigin],
) abi("C") -> Int32:
    if not handle or not output:
        return 1
    output.value()[] = handle.value()[]
    return 0


@export("mojo_ios_handle_destroy")
def mojo_ios_handle_destroy(
    handle: OptionalPointer[Int64, MutUntrackedOrigin]
) abi("C") -> Int32:
    if not handle:
        return 1
    dealloc(
        Allocation(
            unsafe_owned_ptr=handle.value(),
            layout=Layout[Int64].single(),
        )
    )
    return 0


@export("mojo_ios_checked_double")
def mojo_ios_checked_double(
    value: Int64, output: OptionalPointer[Int64, MutAnyOrigin]
) abi("C") -> Int32:
    try:
        if not output:
            raise Error("output pointer is null")
        if value < 0:
            raise Error("value must be non-negative")
        output.value()[] = value * 2
        return 0
    except:
        return 2


@export("mojo_ios_dead_strip_sentinel")
def mojo_ios_dead_strip_sentinel() abi("C") -> Int64:
    return 0x5EED
