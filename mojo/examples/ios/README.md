# Runtime-free Mojo iOS Simulator fixture

For a complete copy-and-run walkthrough, see
[MojoOnIOSimulatorTutorial.md](../../../MojoOnIOSimulatorTutorial.md).

This directory is the first executable slice of the Mojo-on-iOS plan. It
contains two `@export` functions with a handwritten C header:

- `mojo_add(Int64, Int64) -> Int64`
- `mojo_hello_utf8(uint8_t *, int64_t) -> int64_t`

The fixture also contains minimal app-bundle metadata so the static smoke
executable can be installed with `simctl` when an iOS Simulator service is
available. The runtime-free executable is not itself a SwiftUI app; the
adjacent `swiftui_host/` fixture is the source-level SwiftUI adoption seam.

## CoreFoundation direct-C adapter

`corefoundation_adapter/run_corefoundation_smoke.sh` compiles an ownership-safe
CFString C adapter and its Swift C-ABI consumer for both arm64 iOS device and
Simulator SDKs. It verifies the adapter symbol, framework linkage, and Mach-O
`IOS`/`IOSSIMULATOR` metadata without using Mojo runtime support, signing a
device app, installation, or physical-device execution.

```sh
mojo/examples/ios/corefoundation_adapter/run_corefoundation_smoke.sh
```

`RUN_SIMULATOR=1` opts into a separately scoped Simulator app launch that
requires the `MOJO_COREFOUNDATION_CFSTRING_PASS` marker after a CFString
create/inspect/release. See
[`corefoundation_adapter/README.md`](corefoundation_adapter/README.md) for the
ownership boundary and constraints.

## Foundation Objective-C adapter

`foundation_adapter/run_foundation_smoke.sh` demonstrates the object-framework
boundary: caller-owned UTF-8 enters an Objective-C adapter, which owns an
`NSString` and `NSURL` and returns only a status plus scalar `isFileURL` value.
The default harness checks device and Simulator `Foundation.framework` links
and their `IOS`/`IOSSIMULATOR` metadata without Mojo runtime, device signing,
installation, or physical-device claims.

```sh
mojo/examples/ios/foundation_adapter/run_foundation_smoke.sh
```

`RUN_SIMULATOR=1` additionally requests the scoped Simulator
`MOJO_FOUNDATION_URL_PASS` marker. See
[`foundation_adapter/README.md`](foundation_adapter/README.md) for the
ownership and runtime limits.

## UIKit Objective-C adapter

`uikit_adapter/run_uikit_smoke.sh` keeps `UIScreen` ownership inside an
Objective-C adapter and exposes only the scalar main-screen scale through C.
Its default harness checks `UIKit.framework` links and `IOS`/`IOSSIMULATOR`
metadata for device and Simulator slices without using Mojo runtime, signing a
device app, installing anything, or claiming physical-device support.

```sh
mojo/examples/ios/uikit_adapter/run_uikit_smoke.sh
```

`RUN_SIMULATOR=1` runs the scoped `MOJO_UIKIT_SCREEN_SCALE_PASS` marker; the
checked-in harness has passed that Simulator gate. See
[`uikit_adapter/README.md`](uikit_adapter/README.md) for the ownership and
runtime limits.

## Metal AIR toolchain probe

`run_metal_air_toolchain_probe.sh` compiles a checked-in handwritten MSL kernel
to each candidate iOS AIR triple, invokes `metallib`, and records exact commands
and `file` inspection under `/tmp/mojo-ios-metal-air-probe` by default. It is
artifact-only: generated artifacts do not claim Mojo lowering, app packaging,
Metal library loading, or device GPU execution. Unsupported triples report
`SKIP`.

```sh
mojo/examples/ios/run_metal_air_toolchain_probe.sh
```

Set `MOJO_IOS_METAL_AIR_TARGETS` to a space-separated candidate list and
`MOJO_IOS_METAL_AIR_PROBE_OUT` to select an output directory.

## Repository-pinned Mojo diagnostic

`run_pinned_mojo_air_diagnostic.sh` is a non-building diagnostic for the
repository-built `//KGEN:mojo` driver. It records the compiler path, SHA-256,
version, exact iOS AIR target commands, diagnostics, and any assembly artifact.
It reports `SKIP` when `bazel-bin/KGEN/tools/mojo/mojo-full` is absent, rather
than silently falling back to `mojo` on `PATH`.

```sh
./bazelw build --config=build-mojo //KGEN:mojo
mojo/examples/ios/run_pinned_mojo_air_diagnostic.sh
```

An existing built driver can be supplied with `MOJO_IOS_PINNED_MOJO`. This
probe intentionally does not infer AIR/metallib or device support from a
successful assembly emit.

## XCFramework packaging smoke

`run_xcframework_smoke.sh` builds the runtime-free C ABI archive for both the
arm64 device and arm64 Simulator targets, packages the two archives with
`xcodebuild -create-xcframework`, and checks the XCFramework manifest plus the
constituent Mach-O `IOS`/`IOSSIMULATOR` metadata. It is artifact-only: it does
not require a physical device or signing identity, and it does not install or
execute an app.

```sh
MOJO_BIN=bazel-bin/KGEN/tools/mojo/mojo-full \
MOJO_STDLIB_PATH=mojo/stdlib \
  mojo/examples/ios/run_xcframework_smoke.sh
```

Set `MOJO_IOS_XCFRAMEWORK_OUT` to a new output directory when retaining
artifacts from multiple runs. The same harness generates a local Swift Package
inside that output directory, with a binary target for the XCFramework and a
tiny Swift wrapper over `mojo_add`, then runs `swift package describe --type
json` and `swift build` for `arm64-apple-ios17.0-simulator` with the
`iphonesimulator` SDK. Separately, it invokes `swiftc` against the generated
XCFramework Simulator header/module-map/archive slice and checks the resulting
Mach-O platform and `mojo_add` symbol. These are compile/link-only checks;
neither the package nor an app is loaded or executed.

The Mojo module imports no stdlib module, allocates no memory, and does not
initialize the Mojo runtime. It is therefore suitable for validating the
compiler's target-object and native Xcode linker path independently of the
allocator-only D6 probe; the full iOS static CompilerRT still does not exist.

## Compile-only stdlib coverage

`run_stdlib_compile_coverage.sh` emits LLVM only for the arm64 iOS Simulator
and device triples from a small source that constructs explicit SIMD values and
uses math, Darwin errno, `perf_counter_ns`, and formatted `print` output.

```sh
MOJO_BIN=bazel-bin/KGEN/tools/mojo/mojo-full \
MOJO_STDLIB_PATH=mojo/stdlib \
  mojo/examples/ios/run_stdlib_compile_coverage.sh
```

It checks the emitted C ABI export plus Darwin `__error` and
`clock_gettime_nsec_np` declarations, `write` output lowering, and the
formatting/output fixture's CompilerRT dependency. This is compile evidence
only: it does not establish SIMD code quality, successful static-runtime
linking, libc-output correctness, or execution on Simulator/device.

## Narrow stdlib runtime symbol manifests

`run_stdlib_runtime_symbol_manifests.sh` emits—not links—two small probes for
both arm64 iOS triples: `Error` construction/formatting and lazy `std.ffi._Global`
storage. It records the undefined symbols and checks the expected dependency
surface (`KGEN_CompilerRT_GetStackTrace` for the error probe and
`KGEN_CompilerRT_GetOrCreateGlobal` for the global probe, plus allocation/free).

```sh
mojo/examples/ios/run_stdlib_runtime_symbol_manifests.sh
```

These are dependency manifests only. They do not validate ABI signatures,
thread safety, global lifetime, error behavior, static-runtime contents,
linking, or runtime execution.

For this C-ABI fixture, `mojo build --emit exe` is not an iOS linker probe: it
intentionally has no `main`, so the driver stops with `module does not contain
a 'main' function`. The driver now rejects `--emit shared-lib` for iOS with an
actionable diagnostic before the host macOS linker is invoked. Until an
iOS-aware shared-library driver/runtime exists, emit an object or archive and
link it with the matching Xcode SDK as this fixture does.

## Run the discovery smoke test

From the repository root:

```sh
mojo/examples/ios/run_simulator_smoke.sh
```

The harness prefers the repository-built pinned driver at
`bazel-bin/KGEN/tools/mojo/mojo-full` when it exists; otherwise it uses
`mojo` on `PATH`. With the pinned driver it automatically supplies this
checkout's `mojo/stdlib`, avoiding accidental probes with an older independent
installation. Build the pinned driver first when needed:

```sh
./bazelw build --config=build-mojo //KGEN:mojo
```

It emits an `arm64-apple-ios17.0-simulator` object with `apple-m1`, archives it,
compiles a C consumer using the Xcode `iphonesimulator` SDK, links an arm64
Simulator executable, ad-hoc signs it, and verifies the Mach-O symbols and
load-command metadata. Set `MOJO_BIN=/path/to/mojo` to select another compiler;
set `MOJO_STDLIB_PATH="$PWD/mojo/stdlib"` when it requires the checkout's
stdlib. Set `MOJO_IOS_SMOKE_OUT` to retain outputs elsewhere.

Set `MOJO_IOS_SKIP_SIGNING=1` for archive/link-only consumers such as the
XCFramework packaging harness. It omits app packaging as well, and cannot be
combined with `RUN_SIMULATOR=1`.

To request a launch when CoreSimulator is available:

```sh
RUN_SIMULATOR=1 mojo/examples/ios/run_simulator_smoke.sh
```

If CoreSimulator is inaccessible or no iPhone runtime/device is installed, the
script reports a `SKIP` after completing the static checks. This is expected in
sandboxed discovery environments; it is not evidence that an iOS app launch
has passed.

To validate the physical-device target without signing or installing a device
app, use the same source with the device triple:

```sh
MOJO_IOS_TRIPLE=arm64-apple-ios17.0 \
  mojo/examples/ios/run_simulator_smoke.sh
```

This emits an `IOS` object and device archive/executable using the portable
`apple-a7` baseline, then stops before provisioning. The two Apple platforms
must remain separate; do not combine their arm64 archives with `lipo`.

## Physical-device Hello milestone

The next concrete gate is a real, development-signed “Hello from Mojo” launch
on an iPhone or iPad. `run_device_smoke.sh` packages the device executable as
an app and is safe to run without signing material:

```sh
mojo/examples/ios/run_device_smoke.sh
```

To install and launch on a paired device, first unlock the device, trust the
Mac, enable Developer Mode, and obtain a development provisioning profile for
the bundle identifier. Then pass the identity, profile, and device identifier
only through the environment:

```sh
IOS_DEVICE_RUN=1 \
IOS_DEVICE_ID='<UDID-or-device-name>' \
IOS_CODE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' \
IOS_MOBILEPROVISION='/private/path/to/profile.mobileprovision' \
mojo/examples/ios/run_device_smoke.sh
```

The harness invokes `xcrun devicectl device install app` and
`xcrun devicectl device process launch --console`. It does not commit signing
identities, team IDs, device identifiers, profiles, or entitlements. A USB
cable is the recommended first pairing path; after pairing, Xcode can use a
wireless device on the same network. Apple’s current Device Hub guidance says
first-time wireless pairing requires iOS/iPadOS 27 or later; otherwise use a
cable for pairing, then disconnect it and run over Wi-Fi with IPv6 enabled on
the same network. See [Apple’s Device Hub pairing guidance](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac).

This first physical-device gate does not require an Xcode project, the Xcode
GUI, or `xcodebuild`; it uses the iPhoneOS SDK command-line tools from the
Apple developer-tools installation (the iPhoneOS SDK is normally supplied by
the full Xcode installation, not by a minimal standalone shell tool).
`xcodebuild` becomes useful later for a
SwiftUI/XCTest application and repeatable provisioning settings, but it is not
part of the Mojo-to-device tracer bullet.

For the visible physical milestone, use the SwiftUI wrapper. It reuses the
same device archive, links `MojoIOSSmokeApp.swift` for `iphoneos`, and packages
the app without an Xcode project:

```sh
mojo/examples/ios/run_device_swiftui.sh
```

With the device online and signing material supplied:

```sh
IOS_DEVICE_RUN=1 \
IOS_DEVICE_ID='<UDID-or-device-name>' \
IOS_CODE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' \
IOS_MOBILEPROVISION='/private/path/to/profile.mobileprovision' \
mojo/examples/ios/run_device_swiftui.sh
```

The D5b acceptance result is the same visible text as the Simulator:
`Hello from Mojo on iOS.` and `20 + 22 = 42`. The script prints every build,
signing, install, and launch step; capture its output alongside a device
screenshot or UI-test assertion.

The first direct-C framework probe is the Accelerate/vDSP adapter:

```sh
mojo/examples/ios/accelerate_adapter/run_accelerate_smoke.sh
```

By default it is compile/link evidence for a caller-owned-buffer C adapter.
With `RUN_SIMULATOR=1` it additionally packages, launches, and checks a
deterministic vDSP result marker in the iPhone Simulator. This remains direct
Accelerate/vDSP evidence, not Mojo execution, device coverage, or a performance
claim.

The Core ML fixture uses the corresponding Objective-C/Swift/C-ABI adapter
shape and verifies `CoreML.framework` link artifacts for both `iphoneos` and
`iphonesimulator`:

```sh
mojo/examples/ios/coreml_adapter/run_coreml_link_smoke.sh
```

It does not bundle a model or call Core ML, and therefore makes no prediction,
compute-unit, ANE, runtime, device, or performance claim. See
[`coreml_adapter/README.md`](coreml_adapter/README.md) for the artifact checks.

The CoreGraphics direct-C fixture uses scalar rectangle dimensions while
retaining/releasing framework resources inside C. It compile/links both iOS
slices by default; `RUN_SIMULATOR=1` adds a deterministic Simulator marker:

```sh
mojo/examples/ios/coregraphics_adapter/run_coregraphics_smoke.sh
```

See [`coregraphics_adapter/README.md`](coregraphics_adapter/README.md). This
does not establish Mojo runtime or physical-device support.

`runtime_string_probe/` is the intentionally separate Simulator-only runtime
gate. It allocates a Mojo `String` and requires an explicitly supplied static
iOS Simulator runtime archive; without one, its harness reports `SKIP` rather
than claiming the runtime-free smoke result as runtime coverage. See
[`runtime_string_probe/README.md`](runtime_string_probe/README.md).

## Static runtime link probe

`run_static_runtime_link_probe.sh` is the D6 Simulator link diagnostic. It
compiles a String-allocating Mojo C ABI export, then compiles the libc-only
`MemoryIOS.cpp` allocator slice against the Simulator SDK and links both. A
proposed target-compatible static runtime can be supplied explicitly:

```sh
mojo/examples/ios/run_static_runtime_link_probe.sh
```

Set `MOJO_IOS_COMPILERRT_ARCHIVE` to add a proposed full runtime archive after
the allocator slice. The script uses Xcode's `clang++` and fails if the linked
executable retains a `KGEN_CompilerRT_` undefined symbol. A clean link remains
link-only evidence. It also invokes the member-level metadata checker on the
newly created allocator archive, requiring its sole member to report
`IOSSIMULATOR` before linking. Set `RUN_SIMULATOR=1` to package, sign, install, and launch
the probe; the required `MOJO_RUNTIME_STRING_PROBE_PASS` marker then proves the
allocator and String lifetime path on Simulator. It still does not prove
`initialize_runtime()`, AsyncRT, repeated runtime initialization, or clean
process teardown for the full runtime.

`//KGEN:CompilerRTIOSStatic` is currently built by the host Bazel
configuration, so its archive must be inspected before it is supplied here:

```sh
./bazelw build --config=build-mojo //KGEN:CompilerRTIOSStatic
mojo/examples/ios/check_compilerrt_ios_static_metadata.sh
```

The default check expects an `IOSSIMULATOR` archive for
`arm64-apple-ios17.0-simulator`; use `MOJO_IOS_RUNTIME_TRIPLE=arm64-apple-ios17.0`
for a device archive. It extracts every archive member and rejects `MACOS`
metadata. The current host-built archive is therefore expected to fail this
check. The minimal full-runtime recipe is to make the Bazel C++ compile actions
target the matching `iphoneos` or `iphonesimulator` SDK (`-target`, `-isysroot`,
and the iOS minimum-version flag), archive those SDK-targeted objects with that
SDK's `libtool -static`, then rerun this member-level check before the existing
link probe. `run_static_runtime_link_probe.sh` already demonstrates the same
recipe for its intentionally allocator-only `MemoryIOS.cpp` slice; it is not a
recipe for repackaging host-built `CompilerRTIOSStatic` objects.

Set `RUN_SIMULATOR=1` to opt into the narrow allocator/String lifetime gate:

```sh
RUN_SIMULATOR=1 mojo/examples/ios/run_static_runtime_link_probe.sh
```

It packages the linked executable with the existing `Info.plist`, ad-hoc signs
it, installs and launches it with `simctl --console`, and requires the exact
`MOJO_RUNTIME_STRING_PROBE_PASS` marker. If CoreSimulator or an available
iPhone Simulator is absent, it reports `SKIP`. This gate does not prove
`initialize_runtime`, AsyncRT, or general runtime support.

It records the resolved `MOJO_BIN` path, compiler SHA-256/version, and
`MOJO_STDLIB_PATH` (defaulting to this checkout's `mojo/stdlib`), and asserts
that the emitted allocation probe references both expected aligned-allocation
CompilerRT symbols before linking.

## Runtime initialization symbol manifest

`run_runtime_initialize_symbol_manifest.sh` is a Simulator-only D7 discovery
fixture that compiles the checked-in public
`std.runtime.initialize_runtime()` implementation and records its native
dependencies:

```sh
mojo/examples/ios/run_runtime_initialize_symbol_manifest.sh
```

The repository-built compiler type-checks the public import and emits an object
with the required CPU-device symbols (`GetCurrentCPUDevice`,
`GetOrCreateCPUDevice`, and `ReleaseCPUDevice`) plus the global-table symbol
used to retain the runtime. An independently installed Mojo 1.0.0b1 cannot
import this checkout's `std.runtime` package; use the repository-built binary
for this probe. The fixture still does not link or execute it. These symbols
are implemented today by the desktop AsyncRT CPU-device/thread-pool runtime;
the manifest is evidence for a future explicit iOS runtime slice, not evidence
that that runtime is iOS-safe.

## SIMD assembly probe

`run_simd_assembly_probe.sh` uses the repository-built compiler to emit
assembly for a dynamic four-lane `Float32` computation for both iOS triples:

```sh
mojo/examples/ios/run_simd_assembly_probe.sh
```

It checks the assembly for an iOS 17 `.build_version` directive, the exported
C symbol, and an explicit four-lane NEON floating-point arithmetic mnemonic.
It is compile-only instruction evidence, not a link, correctness, runtime, or
performance test.

## Repository-built static-library emission probe

`run_static_lib_emission_probe.sh` exercises `--emit static-lib` with the
repository-built `mojo-full` for both iOS triples:

```sh
mojo/examples/ios/run_static_lib_emission_probe.sh
```

It verifies archive members, the runtime-free C ABI exports, and member
`IOSSIMULATOR`/`IOS` metadata. It does not link, sign, install, or run the
result. The independently installed Mojo 1.0.0b1 rejects `--emit static-lib`
at option parsing and is intentionally not used by this probe.

## SDK-native CompilerRT bootstrap archive

`run_compilerrt_ios_bootstrap_archive_probe.sh` compiles `MemoryIOS.cpp`,
`Initialize.cpp`, `Support.cpp`, and `Globals.cpp` directly with the
iPhoneSimulator and iPhoneOS SDK toolchains, then verifies every archived
object is target-correct:

```sh
mojo/examples/ios/run_compilerrt_ios_bootstrap_archive_probe.sh
```

The helper discovers Bazel's LLVM source and generated-header roots, passing
them only as headers to Xcode clang++; it never repackages host objects or links
Bazel LLVM libraries. The resulting archive contains only SDK-targeted core
allocation/initializer/global/bfloat-helper object evidence. It is not AsyncRT,
a completed runtime, link, or execution support. The helper verifies every
member's `IOS`/`IOSSIMULATOR` load command and iOS 17 minimum version; it does
not repackage the host-built Bazel archive.

There is also a Simulator-only Bazel diagnostic archive action. Its analysis
target can be checked without rebuilding the compiler:

```sh
./bazelw build --config=prebuilt-mojo --nobuild \
  //mojo/examples/ios:compilerrt_ios_simulator_bootstrap_archive_diagnostic
```

When the pinned compiler target and generated LLVM headers are available, a
normal build invokes Xcode's Simulator SDK compiler and archiver from a local,
non-sandboxed action because this repository currently has a macOS-only Bazel
sysroot/C++ toolchain. `//KGEN:CompilerRTIOSStatic` is an input solely to
materialize Bazel-generated LLVM headers; the action never reads, links, or
repackages its host archive. The checked-in shell probe and the Bazel action
both now produce fresh Simulator archive evidence. The Bazel action remains a
host-Xcode diagnostic rather than a hermetic iOS build until the SDK tools and
Apple platform toolchain are declared as Bazel inputs.

`run_compilerrt_ios_globals_link_boundary.sh` is the next, deliberately
expected-failure Simulator diagnostic. It compiles a C consumer of
`Initialize`, allocator, and indexed-global entry points against a freshly
SDK-built four-source archive. It requires the linker to report the missing
`M::GlobalTable::{getOrCreate,clear}` support used by `Globals.cpp` and exits
successfully only when that boundary is observed:

```sh
MOJO_IOS_COMPILERRT_GLOBALS_BOUNDARY_OUT="$(mktemp -d)" \
  mojo/examples/ios/run_compilerrt_ios_globals_link_boundary.sh
```

This confirms a missing SDK-native support dependency; it does not produce or
run an app, provide global-runtime support, or change the separate AsyncRT
blocker.

`GlobalsIOS.cpp` is a separate candidate implementation of the exported
global-entry ABI. It uses `llvm::StringRef` headers for the exact named-call
signature, but only libc++ `unordered_map`/`mutex`/`vector` primitives at link
time. The opt-in Simulator fixture verifies named lookup, insertion, indexed
lookup, destruction callbacks, and idempotent teardown:

```sh
RUN_SIMULATOR=1 MOJO_IOS_GLOBALS_IOS_CANDIDATE_OUT="$(mktemp -d)" \
  mojo/examples/ios/run_compilerrt_ios_globals_ios_candidate.sh
```

This candidate is not a replacement for desktop `Globals.cpp`: it does not
claim the lock-free table's contention, allocation, or concurrent-destruction
semantics, and it does not include AsyncRT.

`run_compilerrt_ios_globals_mojo_probe.sh` closes the next narrow gate: it
emits the checked-in `std.ffi._Global` Mojo export, links it against the
separate SDK-built candidate archive and a C consumer, calls the export twice,
then tears down globals. The opt-in Simulator marker is:

```sh
RUN_SIMULATOR=1 MOJO_IOS_GLOBALS_MOJO_PROBE_OUT="$(mktemp -d)" \
  mojo/examples/ios/run_compilerrt_ios_globals_mojo_probe.sh
```

This validates only the emitted named-global symbol path and basic lifecycle.
It does not wire the candidate into `CompilerRTIOSStatic`, establish general
stdlib support, or cover `initialize_runtime`/AsyncRT.

`StackTraceIOS.cpp` is a separate error-path candidate for
`KGEN_CompilerRT_GetStackTrace`. It returns zero and clears the output pointer,
which the standard library treats as “stack trace not collected”; it deliberately
does not import desktop configuration, signal, or LLVM stack-trace support. The
checked-in Error-construction probe links only this candidate plus `MemoryIOS`:

```sh
RUN_SIMULATOR=1 MOJO_IOS_ERROR_PROBE_OUT="$(mktemp -d)" \
  mojo/examples/ios/run_compilerrt_ios_error_probe.sh
```

The marker establishes construction/formatting of this emitted `Error` probe
with stack traces unavailable. It does not validate throwing, error reporting,
stack capture, `initialize_runtime`, or AsyncRT.

`run_compilerrt_ios_core_seed_probe.sh` is the composite non-AsyncRT gate. It
builds one SDK-native archive containing `MemoryIOS`, `Initialize`, `GlobalsIOS`,
and `StackTraceIOS`, then links both emitted Mojo probes into one Simulator app:

```sh
RUN_SIMULATOR=1 MOJO_IOS_CORE_SEED_PROBE_OUT="$(mktemp -d)" \
  mojo/examples/ios/run_compilerrt_ios_core_seed_probe.sh
```

This proves the two narrow candidate paths coexist in one archive and can
complete their basic global teardown/Error-construction sequence. It is not a
production static runtime, does not enable throwing or stack capture, and does
not invoke `initialize_runtime` or AsyncRT.

## SwiftUI adoption seam

`swiftui_host/` contains the source-only SwiftUI `App`/`View`, Clang module map,
and compile-only probe for the arm64 Simulator. Run
`swiftui_host/compile_swiftui_host.sh` to verify that SwiftUI can import the
handwritten C declarations and emit an iOS object. It deliberately stops before
linking because this checkout does not register `rules_apple`/`rules_swift` and
does not yet expose a runtime-backed `mojo_ios_static_library` provider.

`APPLE_FRAMEWORK_COVERAGE.md` is the crawl-walk-run inventory for making public
iOS/iPadOS APIs available to Mojo. It records which APIs are direct C bindings,
adapter-backed, compile-only, or not yet available; it does not imply that Mojo
must implement the Swift ABI or declare SwiftUI protocols directly.

## Bazel adoption point

`//mojo/examples/ios:ios_simulator_smoke_fixture` exports the source, header,
C consumer, and harness as a single fixture. It is intentionally not an
`ios_application` target yet: this checkout does not currently register
`rules_apple`/`rules_swift`, and normal Mojo executable linking still selects
the macOS runtime/linker path for this target. The next integration step is a
`mojo_ios_static_library` rule that invokes this same object/archive sequence
and returns C-linkable metadata to a `rules_apple`/`rules_swift` SwiftUI host.

### Isolated Apple-rule trial

`rules_apple_trial/` is a nested, diagnostic-only Bazel module. It directly
declares the lockfile-selected `rules_apple` 4.1.0 and `rules_swift` 3.1.2
versions without changing the repository's root module graph. The load-only
probe passes and the minimal iPhone/iPad `ios_application` query passes:

```sh
mojo/examples/ios/rules_apple_trial/run_isolated_rules_load_trial.sh
mojo/examples/ios/rules_apple_trial/run_isolated_ios_application_trial.sh
```

The nested package is deliberately not included in the root iOS `filegroup`:
its direct rule repositories are private to the nested module, and exposing it
from the root would make ordinary `//mojo/examples/ios/...` queries fail before
the root dependency decision is made.

The second command currently reports `BLOCKED` during Bazel 9.2.0 analysis at
the `apple_crosstool_top` transition; it does not build, sign, install, or run
an app. This records the next real Bazel blocker rather than implying that
`rules_apple` integration is complete. See
[`docs/ios/BAZEL_APPLE_SWIFT_INTEGRATION.md`](../../../docs/ios/BAZEL_APPLE_SWIFT_INTEGRATION.md)
for the exact boundary and remediation target.

The C ABI is deliberately constrained to scalar/POD values and caller-owned
buffers. Do not add Mojo strings, collections, exceptions, or owned pointers to
this boundary; opaque handles and explicit destroy functions belong in a later
runtime-backed phase.

## Build boundary: Mojo compiler versus Bazel

The intended division of responsibility is:

```text
mojo build --target-triple ... --emit object
        │
        ├── ar / future --emit static-lib       (Mojo artifact)
        │
        └── Apple clang + SDK + Swift/C consumer (app artifact)
                         │
                         └── codesign / devicectl (device run)
```

`mojo build` owns Mojo parsing, lowering, target CPU selection, and object
emission. Bazel should own action inputs, target triples, SDK selection,
archiving, C/Swift dependencies, test execution, and packaging once the
Apple rules are registered. Bazel must not replace the Mojo compiler, and the
Mojo compiler should not embed provisioning profiles or signing identities.

### Runtime-free static-library action prototype

`//mojo/examples/ios:mojo_ios_static_library_smoke` is an example-local
prototype of that action. Its rule declares the runtime-free Mojo source,
stdlib sources, and C header as inputs, requests
`arm64-apple-ios17.0-simulator`/`apple-m1` object emission from the registered
Mojo toolchain, invokes the Simulator SDK `libtool`, and validates the
extracted archive member's `IOSSIMULATOR` metadata plus the two C ABI exports.
`//mojo/examples/ios:mojo_ios_static_library_device_smoke` uses the same rule
for `arm64-apple-ios17.0`/`apple-a7` and checks the `IOS` load command. Both
targets have no signing, app, or Mojo-runtime behavior. The current actions are
explicitly local and non-sandboxed because `xcrun` discovers the host Xcode SDK
tools at execution time. Build both archive slices with:

```sh
./bazelw build --config=prebuilt-mojo \
  //mojo/examples/ios:mojo_ios_static_library_smoke \
  //mojo/examples/ios:mojo_ios_static_library_device_smoke
```

The generated archives and headers are under `bazel-bin/mojo/examples/ios/`.

The toolchain supplies the compiler and its transitive runfiles as declared
action tools. Therefore `--config=prebuilt-mojo` can use a declared prebuilt
host compiler without rebuilding `mojo-full`; an already-complete
`--config=build-mojo` compiler output is likewise a declared input. This avoids
an undeclared `bazel-bin` compiler path and makes the compiler half of the
action hermetic.

The full action is not hermetic yet: it discovers `libtool`, `ar`, and `vtool`
through host `xcrun` and resolves the Simulator SDK at execution time. The root
configuration also disables Apple C++ toolchain detection and registers no iOS
platform/toolchain. Until those SDK tools and the SDK are declared through an
Apple toolchain, any successful action is host-Xcode evidence only, not a
hermetic Bazel iOS build.

The rule also returns `CcInfo`: its generated header is in the compilation
context and its generated static archive is in the linking context. A future
same-graph Apple target can depend on this provider instead of referring to a
`bazel-bin` path. That provider seam does not by itself register Apple rules or
make the host-Xcode action hermetic.

For now, `//mojo/examples/ios:ios_simulator_smoke_fixture` is intentionally a
source `filegroup`; it is not yet an `ios_application` or a runnable Bazel
test. That limitation is recorded by the scrutiny reports and remains the D3
automation task. The runtime-free archive action now reproduces the low-level
`ar`/`vtool`/`nm` checks inside Bazel, while the direct scripts remain useful
for device slices, runtime probes, and clean evidence capture.
