# iOS static CompilerRT implementation map

## Purpose and current boundary

This is the device-independent D6 implementation map for an app-safe Mojo
runtime on iOS. It is an engineering inventory, not a claim that the static
runtime is already shipped. The current iOS tracer can link runtime-free
`@export` functions; normal Mojo programs still select the desktop
`libKGENCompilerRTShared.dylib` path and therefore cannot be treated as iOS
runtime support.

The iOS hand-off should remain `--emit static-lib`: the compiler emits target
objects, archives them, and the application linker supplies the iPhoneOS or
iPhoneSimulator SDK. Do not make the host-oriented executable driver copy a
macOS dynamic runtime into an iOS app.

## What exists today

- The static-library hand-off is already represented in
  `KGEN/tools/mojo/Build/mojo-build.cpp` (the `--emit static-lib` path around
  the archive-producing build action).
- `KGEN/BUILD.bazel` currently defines one desktop-oriented `CompilerRT`
  shared-library target. Its source glob includes every file in
  `lib/CompilerRT`, and its dependencies include AsyncRT, profiling, MLRT
  device context, configuration, filesystem, threading, and optional Tracy.
- That target produces `KGENCompilerRTShared`, which is the wrong deployment
  shape for an iOS app: it is a host runtime DSO with install-name, loader,
  and dependency assumptions that do not belong in the initial static package.
- The repository's `std.runtime.initialize_runtime()` path calls AsyncRT
  CPUDevice symbols. An exported function that only writes a caller-owned
  buffer or performs a small allocation must not implicitly initialize the
  complete AsyncRT process runtime.
- `KGEN/BUILD.bazel` now contains the explicit `//KGEN:CompilerRTIOSStatic`
  source-list seed. Its `MemoryIOS.cpp` member is libc-only and is compiled
  against the iPhoneSimulator SDK by the link diagnostic; the Bazel archive
  itself is a host build artifact and must not be treated as an iOS archive.

## Candidate first static target

The explicit target avoids reusing the shared-library glob. It is named
`CompilerRTIOSStatic` and keeps its source and dependency policy reviewable:

| Component | Initial status | Reason |
|---|---|---|
| `Initialize.cpp` | Include | Idempotent runtime registration symbol |
| `Globals.cpp` | Include after iOS ABI check | Mojo globals and teardown; validate locking and process lifetime |
| `Memory.cpp` | Replaced for first probe | `MemoryIOS.cpp` provides only `posix_memalign`/`free` entry points; the desktop TCMalloc implementation remains out of the iOS target |
| `Support.cpp` | Include | bfloat conversion helpers; verify libc/compiler builtins on both SDKs |
| System/printing | Small explicit subset | Keep only symbols required by the supported stdlib; avoid environment/configuration and global fault handlers initially |
| AsyncRT | Later D6/D7 increment | Required for `initialize_runtime()`, async, and threading; add only after a static CPUDevice dependency graph is isolated |
| Python, JIT, compiler services | Exclude | Not part of an app runtime |
| `RangeBridge.cpp`, `Tracing.cpp`, `TracyBridge.cpp` | Exclude initially | Profiling/plugin loaders and desktop instrumentation are not required for the first app-safe library |
| `BinaryID.cpp` | Exclude initially | Desktop binary identity is not an app execution dependency |
| desktop MLRT/device context | Exclude initially | Avoid pulling MAX/device-driver code into the core iOS runtime |

`MemoryIOS.cpp` is intentionally separate rather than copied blindly: the
desktop default allocator is supplied by AsyncRT TCMalloc globals. The first
implementation provides the same exported allocation symbols with
`posix_memalign`/`free`, and the probe compiles it for the iPhoneSimulator SDK.
This is still only an allocator/link seam; it does not establish a complete
static runtime or make `initialize_runtime()` available.

## ABI inventory before linking

For every candidate Mojo export, capture undefined symbols from the emitted
object before attempting an iOS link. A symbol is admitted to the first static
target only when its implementation and SDK availability are known. Keep
separate manifests for the repository-pinned compiler and any independently
installed compiler; do not merge symbol names across compiler/stdlib versions.

The original independent probe used Mojo `1.0.0b1`, not the repository-pinned
compiler. Its String object referenced a different runtime ABI, including
allocator/free, globals, argv/stack-trace/printing, AsyncRT, and libc symbols.
Those names are useful as a diagnostic warning, not as the implementation
contract for this checkout.

Reproduce a manifest with the compiler under test:

```sh
mojo build \
  --target-triple arm64-apple-ios17.0-simulator \
  --target-cpu apple-m1 \
  -I mojo/stdlib \
  --emit object \
  mojo/stdlib/test/collections/string/test_string_stable.mojo \
  -o /tmp/test_string_stable.o
nm -u /tmp/test_string_stable.o | sort
```

Record the compiler path/version, stdlib revision, target triple, SDK, and
the complete undefined-symbol output beside the result. If the compiler or
stdlib cannot compile the probe, record that as a provenance/toolchain block;
do not substitute an installed nightly silently.

## Link and Simulator gates

The explicit target is now present, and a small C-ABI fixture links one Mojo
object with the SDK-compiled allocator slice (plus an optional proposed full
archive) using Xcode clang.
The first gate should inspect all of the following:

1. `ar -t` contains the intended runtime objects and no desktop-only object.
2. `nm -u` on the final executable contains no unresolved `KGEN_CompilerRT_*`
   symbols and no unexpected dynamic runtime dependency.
3. `vtool -show-build` reports `IOS` or `IOSSIMULATOR` with the requested
   minimum OS, and `otool -L` contains only SDK/framework dependencies allowed
   by the fixture.
4. The current gate proves allocation-symbol resolution, final Mach-O metadata,
   and—when `RUN_SIMULATOR=1`—the allocator/owned-String lifetime marker on
   Simulator. It still does not exercise `initialize_runtime()`, an error path,
   repeated initialization, or AsyncRT. Those remain later increments.
5. `codesign --verify` and `simctl install/launch` validate the app bundle;
   physical-device signing and launch remain a later D5/D6 gate.

The runtime must be linkable with dead stripping. A library that links only
when all desktop objects and shared dependencies are retained is not an iOS
static runtime.

## Non-goals for this increment

- No on-device compiler, JIT, Python, REPL, or downloaded executable code.
- No private Apple frameworks or oMLX-style ANE bridge.
- No assumption that macOS environment, filesystem, signal, fault-handler, or
  desktop device-context behavior is available in the iOS sandbox.
- No physical iPhone is required to complete the source/dependency map or the
  first Simulator link gates, but a physical device is required before calling
  the runtime production-ready.

## Exit criteria for D6 implementation

The first D6 code change now has an explicit Bazel target/source list, an iOS
SDK allocator compile/link action, and a versioned undefined-symbol manifest.
It is ready for the next review increment, but the D6 phase is not complete:
Simulator execution, repeated initialization, broader globals/system support,
and AsyncRT/threading remain required. It must preserve the existing
macOS/Linux `CompilerRT` target and make unsupported runtime features fail
clearly rather than silently loading the desktop shared library.
