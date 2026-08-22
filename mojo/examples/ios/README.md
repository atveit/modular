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

The Mojo module imports no stdlib module, allocates no memory, and does not
initialize the Mojo runtime. It is therefore suitable for validating the
compiler's target-object and native Xcode linker path before the iOS static
CompilerRT exists.

## Run the discovery smoke test

From the repository root:

```sh
mojo/examples/ios/run_simulator_smoke.sh
```

The harness uses the repository's available `MOJO_BIN` (or `mojo` on `PATH`),
emits an `arm64-apple-ios17.0-simulator` object with `apple-m1`, archives it,
compiles a C consumer using the Xcode `iphonesimulator` SDK, links an arm64
Simulator executable, ad-hoc signs it, and verifies the Mach-O symbols and
load-command metadata. Set `MOJO_BIN=/path/to/mojo` to repeat the probe with a
repository-pinned or locally built compiler. A compiler that requires the
checkout's stdlib can additionally set
`MOJO_STDLIB_PATH="$PWD/mojo/stdlib"`. Set `MOJO_IOS_SMOKE_OUT` to retain
outputs elsewhere.

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

It is compile/link evidence for a caller-owned-buffer C adapter, not yet a
runtime, device, or performance claim.

The Core ML fixture uses the corresponding Objective-C/Swift/C-ABI adapter
shape and verifies `CoreML.framework` link artifacts for both `iphoneos` and
`iphonesimulator`:

```sh
mojo/examples/ios/coreml_adapter/run_coreml_link_smoke.sh
```

It does not bundle a model or call Core ML, and therefore makes no prediction,
compute-unit, ANE, runtime, device, or performance claim. See
[`coreml_adapter/README.md`](coreml_adapter/README.md) for the artifact checks.

`runtime_string_probe/` is the intentionally separate Simulator-only runtime
gate. It allocates a Mojo `String` and requires an explicitly supplied static
iOS Simulator runtime archive; without one, its harness reports `SKIP` rather
than claiming the runtime-free smoke result as runtime coverage. See
[`runtime_string_probe/README.md`](runtime_string_probe/README.md).

## Static runtime link probe

`run_static_runtime_link_probe.sh` is the D6 pre-link diagnostic. It compiles
a String-allocating Mojo C ABI export with the selected iOS SDK target and
records its undefined-symbol manifest. With no runtime archive, it exits after
that evidence; this is the expected current state. When a proposed
target-compatible static runtime exists, supply it explicitly:

```sh
MOJO_IOS_COMPILERRT_ARCHIVE=/absolute/path/libKGENCompilerRTIOS.a \
  mojo/examples/ios/run_static_runtime_link_probe.sh
```

The script uses Xcode's `clang++` and fails if the linked executable retains a
`KGEN_CompilerRT_` undefined symbol. A clean link remains link-only evidence:
Simulator launch must separately prove allocation, String lifetime, repeated
initialization, and clean teardown.

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

For now, `//mojo/examples/ios:ios_simulator_smoke_fixture` is intentionally a
source `filegroup`; it is not yet an `ios_application` or a runnable Bazel
test. That limitation is recorded by the scrutiny reports and is the D3
automation task. The direct scripts remain the low-level evidence path until a
`mojo_ios_static_library` action can reproduce the same `file`/`vtool`/`nm`
checks inside Bazel.
