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

The first direct-C framework probe is the Accelerate/vDSP adapter:

```sh
mojo/examples/ios/accelerate_adapter/run_accelerate_smoke.sh
```

It is compile/link evidence for a caller-owned-buffer C adapter, not yet a
runtime, device, or performance claim.

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
