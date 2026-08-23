# Mojo on iOS Roadmap

**Status:** In progress — runtime-free C ABI, narrow allocator/String execution,
and the direct SwiftUI Simulator launch are demonstrated; the canonical Bazel
`rules_apple`/`rules_swift` + XCTest gate and physical signing/launch remain
staged work
**Evidence last verified:** August 23, 2026
**Initial deployment baseline:** iOS and iPadOS 17

## Summary

This document describes an upstream-oriented path from Mojo's current partial
cross-compilation capabilities to production-quality Mojo libraries for iPhone
and iPad.

The initial application model is deliberately narrow: SwiftUI owns the app
lifecycle, while Mojo is ahead-of-time compiled on macOS into a static native
library and exposed to Swift through a stable C ABI. Device and Simulator
variants are packaged as an XCFramework and consumed through a local Swift
Package wrapper. SwiftUI is the first host and validation app, not the
boundary of iOS support.

The full-package goal is broader than one SwiftUI sample: a released package
must provide a documented, testable surface for the public iOS/iPadOS SDK. C
frameworks are imported directly where safe; Swift and Objective-C frameworks
are exposed through maintained adapter modules and callbacks. “Full” means
that every public framework in the supported SDK inventory has an explicit
status—direct, adapter-backed, compile-only, or unavailable—with availability,
ownership, sandbox, and test evidence. It does not promise that Mojo declares
SwiftUI protocols or reproduces the Swift ABI directly.

The roadmap locks in these decisions:

- The minimum deployment target is iOS/iPadOS 17.
- The first target is the arm64 iOS Simulator on Apple Silicon, followed by
  arm64 physical devices.
- SwiftUI owns application lifecycle, UI, scene management, and Apple framework
  object lifetimes.
- Mojo supplies reusable computation and systems code through an AOT-compiled
  static library and C ABI.
- Distribution uses separate device and Simulator variants in an XCFramework,
  wrapped by a local Swift Package. The package also owns the public Apple SDK
  adapter modules and framework-coverage manifest; SwiftUI is only its first
  end-to-end consumer.
- Initial scope is the Mojo language, core standard library, CPU/SIMD,
  threading, and native-library integration.
- Later scope includes Apple SDK bindings and Mojo-generated Metal compute
  kernels.
- Full package support is measured against the public iOS/iPadOS SDK inventory,
  not against SwiftUI alone.
- On-device Mojo JIT, REPL, or compiler support, Python interoperability,
  direct Swift ABI support, direct SwiftUI declarations from Mojo, and the full
  MAX runtime are initially out of scope.

Official Mojo guidance already permits cross-compiling objects, but expects an
external target toolchain and target-compatible runtime libraries to perform
the final link. The first supported iOS workflow should embrace that contract
instead of trying to make the host-oriented executable driver own Xcode's
linking and signing responsibilities. See
[Mojo compilation targets](https://docs.modular.com/mojo/tools/compilation/).

## Verified Starting Point

The following observations were made on August 22, 2026. They are discovery
evidence, not permanent guarantees, and must be reproduced before implementation
decisions rely on them.

- The host is an arm64 Mac Studio running macOS 26.5.2 and Xcode 26.2. Both the
  `iphoneos` and `iphonesimulator` SDKs are installed.
- The repository pins Mojo `1.1.0.dev2026082105`. The independently installed
  compiler used for the smoke tests was Mojo `1.0.0b1`; therefore every probe
  below must be repeated with the repository-pinned or locally built compiler.
- A repository-built driver can now be produced with
  `./bazelw build --config=build-mojo //KGEN:mojo`. Using
  `bazel-bin/KGEN/tools/mojo/mojo-full` with `-I mojo/stdlib` reproduces the
  arm64 Simulator object, archive, link, ad-hoc signing, install, and launch
  chain. Its provenance was recorded as `Mojo 1.1.0.dev0 (deadbeef)` by the
  locally built binary; the source checkout's pinned version remains the
  authoritative version to report in CI.
- Mojo already emits a valid arm64 Mach-O object for the iOS Simulator with an
  `LC_BUILD_VERSION` platform of `IOSSIMULATOR`:

  ```sh
  mojo build \
    --target-triple arm64-apple-ios17.0-simulator \
    --target-cpu apple-m1 \
    --emit object \
    source.mojo \
    -o source.o
  ```

- A runtime-free Mojo function exported with `@export` and a C ABI can already
  be linked into an iOS Simulator dynamic library with Xcode's `clang` and
  ad-hoc signed. This validates the basic code generation and C-linkage path;
  the planned deliverable remains a static library.
- A normal `mojo build` executable fails because the driver invokes a macOS
  linker configuration and selects the macOS-only
  `libKGENCompilerRTShared.dylib`.
- Cross-compiling filesystem standard-library tests fails because
  `CompilationTarget.is_macos()` is false for iOS. This leaves shared Darwin
  facilities, including `__error` and Darwin errno values, unselected.
- SDK inspection confirms that important errno and open-flag constants match
  between macOS and iOS. The implementation must nevertheless validate C
  structures, layouts, symbol availability, and API availability rather than
  treating all iOS APIs as macOS APIs.
- The current compiler/build seams also warrant explicit attention: same-arch
  cross-OS compilation can inherit host CPU features; host-derived linker and
  file-extension choices leak into target builds; standard-library target
  queries distinguish Linux and macOS but not iOS; and current Apple GPU target
  paths contain macOS-specific AIR assumptions.
- CoreSimulator access was blocked by the discovery tool sandbox. The first
  implementation session must verify an installed iOS 17-or-newer Simulator
  runtime:

  ```sh
  xcrun simctl list runtimes
  ```

Temporary smoke tests are encouraged during discovery. They need not be checked
in unless they become stable regression tests, samples, or build-system fixtures.

### Post-upstream rebaseline — August 23, 2026

The fork was merged with 71 upstream commits through `10d978e3c7` and pushed
to `Atveit/modular:main`. The merge preserved both histories; 169 fork-only
paths were compared as Git tree entries with zero mismatches. The merged
`//KGEN:mojo` source build, focused KGEN/iOS tests, upstream compiler-timing
tests, static-library tests, Simulator launch, SwiftUI screenshot, core-seed
probe, XCFramework, Swift Package, and dual-SDK sysroot diagnostics pass.

The upstream language update removed `fn`; the fork's static-library lit test
was updated to `def`. The new pass-timing plumbing overlapped
`mojo-build.cpp` and was combined with, rather than substituted for, the
fork's `--emit static-lib` and iOS diagnostics. No other fork-only path needed
an integration edit.

The runtime plan changes only in sequencing, not architecture:

- D6 now has separate Bazel-produced Simulator and device core-seed archives
  built from `MemoryIOS.cpp`, `Initialize.cpp`, `GlobalsIOS.cpp`, and
  `StackTraceIOS.cpp`. The Simulator archive runs real emitted-Mojo global and
  Error probes; the device archive passes artifact/link metadata gates.
- The post-merge public `std.runtime.initialize_runtime()` object still calls
  `GetCurrentCPUDevice`, `GetOrCreateCPUDevice`, `ReleaseCPUDevice`, and
  `GetOrCreateGlobal`. Upstream did not remove the AsyncRT/thread-pool/allocator
  dependency boundary.
- The root `rules_apple`/`rules_swift` and Apple C++ toolchain migration remains
  unresolved. Until that dependency-owner work is approved, the target-correct
  CompilerRT archive actions remain explicit local Xcode diagnostics and D6 is
  prioritized over additional framework breadth.

## Support Contract

The initial supported configurations are:

| Dimension | Initial contract |
| --- | --- |
| Host | Apple Silicon Mac with Apple's developer tools and matching iPhoneOS/iPhoneSimulator SDKs (normally installed with Xcode) |
| Simulator | `arm64-apple-ios17.0-simulator`, baseline CPU `apple-m1` |
| Device | `arm64-apple-ios17.0`, portable baseline CPU `apple-a7` |
| App lifecycle | SwiftUI/Swift (or a later UIKit/Swift host) |
| Mojo artifact | AOT static library with a C ABI |
| Packaging | XCFramework plus local Swift Package wrapper |
| Package API surface | Public iOS/iPadOS SDK inventory with direct C, adapter, callback, compile-only, and unavailable statuses |
| Apple framework ownership | C ABI and adapter-owned handles; no Mojo-owned Swift/Objective-C object layouts |
| Initial execution | CPU, SIMD, and threading |
| Later execution | Precompiled Mojo-generated Metal kernels |
| Deployment baseline | iOS/iPadOS 17, configurable upward |

iOS is cross-compilation even when both host and target are arm64. Toolchain
logic must compare architecture, operating system, and target environment.
Device-specific CPUs such as `apple-a17` may be used for controlled benchmark
builds, but never as the baseline for generally distributed binaries.

### iOS and iPadOS support model

For the initial AOT native-library scope, iPhone and iPad are one Apple device
target family: use the same `arm64-apple-ios<version>` device triple, Apple
device SDK family, Darwin ABI, static runtime, and CPU/SIMD implementation. An
iPad does not require a separate Mojo backend or a fictional `ipados` target
triple. The app target communicates the supported families through packaging
metadata (`UIDeviceFamily`, represented by Xcode’s `TARGETED_DEVICE_FAMILY`;
Apple documents values for iPhone and iPad in its
[build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)).

The meaningful differences belong above the Mojo library boundary. iPadOS
apps may need scene-based lifecycle handling, multiple windows, resizable
Stage Manager layouts, external-display behavior, pointer/keyboard workflows,
and document-oriented UI. Apple’s [desktop-class iPad guidance](https://developer.apple.com/documentation/UIKit/building-a-desktop-class-ipad-app)
and [multiple-window guidance](https://developer.apple.com/documentation/uikit/supporting-multiple-windows-on-ipad)
describe those host responsibilities. SwiftUI/UIKit owns them; Mojo receives
stable C callbacks, handles, and buffers.

Do not infer “iPad” from the compiler target: the native library can be reused
by an iPhone-only, iPad-only, or universal app. If behavior genuinely differs,
the host should pass an explicit configuration or query the device idiom at
runtime. The support matrix must nevertheless test both iPhone and iPad
Simulator families, then at least one physical device in each family before
calling the app package universal.

## Staged Delivery Ladder

The thematic phases below are implemented through independently reviewable
deliveries. Each delivery has a concrete artifact, a reproducible validation
command, and a stop/go gate. A later delivery may improve an earlier one, but
it must not silently weaken its evidence. The ladder deliberately treats
SwiftUI as the first vertical slice and the public Apple SDK package as the
larger destination.

| Delivery | Artifact users can inspect or consume | Minimum evidence before moving on |
| --- | --- | --- |
| D0 — Evidence baseline | Pinned compiler/toolchain report, SDK/runtime inventory, support matrix | Compiler version, Xcode SDK paths, both canonical triples, and reproducible `file`/`vtool`/`nm` probes |
| D1 — Mojo object | Runtime-free Mojo source and arm64 Simulator object | `IOSSIMULATOR`, iOS 17.0, expected exported symbols, and no host-link step |
| D2 — Native C archive | Simulator `.a`, C header, C assertion consumer | `ar -t`, symbol preservation, Apple clang link, signed app bundle, and C assertions |
| D3 — SwiftUI Simulator slice | SwiftUI source, Clang module map, linked Simulator `.app` | Swift compile, final `nm`/`vtool`, codesign verification, `simctl install/launch`, and screenshot |
| D4 — First-class target plumbing | Compiler target classification, CPU defaults, `--emit static-lib`, focused unit tests | iOS device and Simulator metadata, same-arch cross-compilation tests, and unchanged macOS/Linux tests |
| D5 — Device object/archive | `arm64-apple-ios17.0` object and static archive | `IOS` load command, conservative `apple-a7` baseline, device clang link, and no accidental Simulator slice |
| D5a — Physical device artifact | Development-signed runtime-free device `.app` plus install/launch transcript | Paired iPhone/iPad, Developer Mode, provisioning/signing, `devicectl` install, and process launch with captured output |
| D5b — Physical visible “Hello from Mojo” | Development-signed SwiftUI `.app` showing Mojo-returned text and `20 + 22 = 42` | Device SwiftUI link, signing/install/launch, and a captured on-device screen or UI-test assertion; exercise iPhone and iPad hosts |
| D5c — Optional internal TestFlight tracer | Distribution-signed IPA containing the SwiftUI tracer app | App Store Connect record, application identifier in the profile, successful upload/processing, and installation through an internal TestFlight group |
| D6 — Serial static runtime and core stdlib | App-safe non-AsyncRT CompilerRT plus supported serial stdlib subset | Globals, allocation, errors, strings, output, restricted environment/files, repeated C-ABI calls, dead stripping, and no unresolved runtime symbols |
| D7 — AsyncRT/CPU/SIMD/threading package | Reusable core library with runtime initialization, parallel correctness tests, and device benchmark app | Two `initialize_runtime()` calls, NEON/vector inspection, multicore correctness/scaling, C-boundary overhead, and no unexplained Swift regression |
| D8 — Direct C SDK products | Darwin/CoreFoundation/CoreGraphics/Accelerate/`os` headers and package products | iOS 17 compile/link tests, ABI layout checks, availability metadata, and at least one runtime test per product |
| D9 — Object-framework adapters | Foundation/UIKit/SwiftUI/AVFoundation/Core ML adapter products | Stable C handles/callbacks, ownership and teardown tests, entitlement notes, and Simulator/device behavior where required |
| D9a — Public ML acceleration | Core ML model adapter plus Accelerate/vDSP/BLAS/BNNS products | Bundled model conversion record, compute-unit diagnostics, device correctness, and evidence that ANE claims come from profiling rather than configuration |
| D10 — Full SDK coverage manifest | Versioned public-framework inventory and machine-readable package manifest | Every public SDK framework has direct, adapter, callback, compile-only, or unavailable status with a reason and test reference |
| D11 — XCFramework/Swift Package | Device + Simulator XCFramework, headers/module maps, local Swift Package wrapper | Clean consumer app imports core and adapter products without Mojo/Modular installation; no `lipo` mixing |
| D12 — Metal package | Precompiled Mojo-generated metallibs plus Swift/ObjC host bridge | iPhone and iPad correctness, no on-device shader compilation, GPU trace comparison to MSL/MPS |
| D13 — Release and upstream stack | CI/manual gates, ABI fuzzing, docs, signed release artifacts, reviewable upstream commits | Support matrix is continuously tested; App Store constraints and all unavailable features are documented |

The first three deliveries are intentionally runtime-free and can land while
the static runtime is being designed. D8–D10 are the explicit answer to “all
iOS libraries”: completeness is measured by the SDK manifest and package
products, not by pretending that Mojo directly implements every Swift ABI.

Every delivery should include a short evidence record in the repository or CI
artifact containing: compiler version and path, target triple, SDK, command
line, artifact hashes, symbol/load-command checks, test result, and known
limitations. This makes each checkpoint independently auditable by a skeptical
consumer.

**Current checkpoint:** D0–D2 and the narrow D6 allocator/String Simulator
launch are demonstrated by checked-in shell probes. The direct SwiftUI
source/link harness has also been installed and launched in an arm64 iPhone 17
Pro Simulator; the captured screen shows the Mojo-returned greeting and
`20 + 22 = 42`. D3's stricter canonical exit gate—`rules_apple`/`rules_swift`
integration plus XCTest/UI-test assertions—remains open. D4 is implemented in
the compiler and stdlib;
focused KGEN and iOS-target Bazel tests pass, while broader cross-target
coverage remains. The repository-built driver also emits a genuine static
archive directly with `--emit static-lib` for both the Simulator and device
triples, while the independently installed 1.0.0b1 compiler still rejects
that option at option parsing, before it selects any target runtime or linker.
D5 has a device object/archive/link probe (signing and
installation remain intentionally skipped). D8 has a compile-only LLVM
inventory covering builtins, explicit SIMD, math, Darwin errno, clocks,
formatting, and libc output for both iOS triples, plus a direct-C
Accelerate/vDSP adapter whose opt-in Simulator run now checks a deterministic
vDSP result marker. This is Apple-framework runtime evidence, not Mojo
execution, device coverage, or a benchmark gate. A CoreFoundation CFString
adapter now has matching device/Simulator compile-link checks and an opt-in
Simulator ownership marker. CoreGraphics and Foundation now have matching
device/Simulator adapter checks plus opt-in Simulator result markers; these are
framework-boundary evidence, not Mojo-runtime or device support.
The public `os/signpost.h` surface now has a dual-SDK direct-C fixture that
links a fixed-name event adapter and verifies the `libSystem` signpost symbol;
collection/profiling and Mojo-runtime claims remain open. D9 has a
matching artifact-only Core ML framework adapter fixture for both device and
Simulator SDKs; it does not load a model
or claim ANE use. D12
has an Xcode-only handwritten-MSL AIR/metallib probe for both candidate iOS
triples; it does not prove Mojo lowering, app loading, or device dispatch.
D6 now has an explicit `//KGEN:CompilerRTIOSCoreSources` serial source contract plus a
libc-only `MemoryIOS.cpp` allocator slice. The Simulator link diagnostic
compiles that allocator with the iPhoneSimulator SDK and links the
runtime-dependent String object with no unresolved `KGEN_CompilerRT_*`
symbols. With `RUN_SIMULATOR=1`, it also installs and launches the probe and
observes `MOJO_RUNTIME_STRING_PROBE_PASS`, proving allocator/String lifetime
only; it is not full runtime execution or `initialize_runtime()` support.
An SDK-native bootstrap archive now compiles `MemoryIOS.cpp`, `Initialize.cpp`,
`Globals.cpp`, and `Support.cpp` directly for both iOS SDKs, using Bazel's LLVM
tree only for headers; every archive member has the expected `IOS` or
`IOSSIMULATOR` metadata and iOS 17 minimum version. This is
target-compatible allocation/initializer/global/bfloat-helper evidence only,
not a complete CompilerRT or AsyncRT runtime or a license to repackage the
host-built Bazel archive. Supplying that SDK-native archive to the String link
probe now also produces a clean Simulator link and the same launch marker; the
claim remains limited to allocator/String lifetime because no initializer or
AsyncRT entry point is exercised.
An expected-failure C link boundary now shows that adding `Globals.cpp` still
requires `M::GlobalTable::{getOrCreate,clear}` plus LLVM container/runtime
support; no executable is produced. This is the next concrete D6 dependency
map, not a runtime pass.
Additional D6 manifests now record the allocation, stack-trace, and global
table symbols required by narrow `Error` and `_Global` stdlib operations on
both iOS triples; they are dependency evidence only. The member-level runtime
metadata checker also proves that the host-only Bazel `CompilerRTIOSBootstrapHost`
archive is host `MACOS` and rejects it, while the SDK-compiled allocator slice
passes as `IOSSIMULATOR`. The remaining D7 and runtime portions of D9–D13
remain planned and must not be described as shipped support. D7 has a
Simulator-only external-symbol manifest for the three CPU-device names reached
by the checked-in `initialize_runtime()` implementation. Because the pinned
compiler cannot import this checkout's public `std.runtime` package, the
fixture uses pointer-width `Int` carriers solely to emit those arm64 symbol
names; it does not validate public `OptionalPointer` ABI signatures, call
semantics, link, or execute AsyncRT. A separate D7 assembly probe now emits
the runtime-free four-lane SIMD fixture for both iOS triples and observes
`fmla.4s` NEON instructions; this is instruction evidence only, not a
correctness, runtime, or performance result.
The follow-up direct Simulator compile of `AsyncRT.cpp`, even with the
repository LLVM source/generated headers, reaches incompatible target-configured
LLVM/MLIR dependencies (`file_status::getSize`, `EnvPathSeparator`, and
`mlir/Support/LLVM.h`). Source inspection also confirms that preserving
`initialize_runtime()` semantics retains the default thread pool and
TCMalloc/RuntimeGlobals graph. No AsyncRT subset is therefore wired into the
iOS runtime until a target-configured LLVM/MLIR toolchain and an intentionally
extracted shim API exist.
The first restricted environment/sandbox-file increment is now separately
proven. `PrintIOS.cpp` supplies only the formatted-print ABI required by the
current file lowering, without importing desktop `System.cpp`. A real Mojo
export roundtrips a private value through `setenv`/`getenv`/`unsetenv`, uses
`open` to write and read a fixed payload at a caller-owned app `TMPDIR` path,
and lets the C host independently verify and remove the file. The Simulator
marker passes and the device artifact links with `IOS`/iOS 17 metadata. This is
not evidence for arbitrary filesystem access, directory traversal, concurrent
I/O, `initialize_runtime`, AsyncRT, or physical-device execution.
D11 now has an artifact-only XCFramework, a
generated local Swift Package metadata and iOS Simulator build, and a separate
Swift consumer compile/link check for the runtime-free C ABI, covering `ios-arm64` and
`ios-arm64-simulator`; it does not load or execute a consumer app. The D3
artifact chain is proven, but its original exit gate—one
rules_apple/rules_swift Bazel command plus XCTest/UI-test assertions—is not yet
met because this checkout still uses source fixtures and shell probes.
UIKit now has a scalar `UIScreen` adapter with matching device/Simulator
metadata and a passing opt-in Simulator marker. A read-only Bazel
reconnaissance note records the bounded candidate pair `rules_apple` 4.1.0
plus `rules_swift` 3.1.2. Restoring the historical `link_hack.bzl` contract
fixed module traversal (`bazel mod all_paths` now completes), but the aliases
remain absent from the root module. The isolated trial resolves and loads both
rules and its minimal `ios_application` query passes; Bazel 9.2.0 then blocks
analysis at `rules_apple`'s `apple_crosstool_top` transition setting. A
temporary control using `rules_apple` 4.5.3 plus `rules_swift` 3.5.0 analyzes
and builds a minimal Simulator `.ipa`, but that pair raises the root protobuf
floor and has not been adopted. No root Apple-rule dependency or toolchain
change has been made, and no canonical app build is claimed.
In a separate disposable root dependency-owner trial, protobuf 34.0.bcr.1
resolved with either a narrowly ported development-dependency patch or no
protobuf patch; the no-patch variant passed the focused `CompilerRTIOSStatic`
build and 70 KGEN unit tests. Its minimal UIKit app still stops under the
repository's Bazel 10 pre-release because the 4.5.3 Apple rules request
`//command_line_option:apple_platforms` as an invalid transition output. This
narrows the root blocker to dependency/toolchain compatibility; it is not a
reason to change the shared root graph without owner review.
A newer disposable Bazel-10 control with `rules_apple` 5.0.0-rc3 and
`rules_swift` 4.0.0-rc3 clears the earlier `apple_platforms` transition and
reaches the repository-owned `macos_clang_toolchain`. Analysis then stops
because its configurable compiler args have Linux/macOS cases but no
iOS/default branch. The RC pair also changes apple_support and Swift argument
parser dependencies, so the disposable follow-up added Xcode-discovered
iPhoneOS/iPhoneSimulator sysroots and device/Simulator constraints only. That
clears the first sysroot select but then stops at `args:cpp_compile_args`,
whose `-stdlib` select is Linux/macOS-only; more macOS-only compile/link/rpath
and sanitizer selects remain. The next step is an owner-reviewed complete
target-aware iOS C++ toolchain branch, not a root dependency upgrade or a
macOS fallback.
The first reusable toolchain building block is now available without changing
the root module graph: `bazel/internal/cc-toolchain/apple_sysroot_repository.bzl`
resolves an explicit Xcode SDK name and an explicit framework allowlist. Its
diagnostic passes `iphonesimulator` and `iphoneos` with UIKit, while the legacy
macOS sysroot rule remains unchanged. This removes the hard-coded
`ApplicationServices.framework` assumption from future iOS sysroots, but does
not yet register an iOS C++ toolchain or build an Apple-rule app.
That isolated control now also imports the generated runtime-free Mojo archive
through `cc_import`, compiles a C caller of `mojo_add`, and builds a minimal
Swift/iOS Simulator IPA. This proves that the archive is consumable by the
Apple-rule linker in a compatible disposable workspace; it does not turn a
`bazel-bin` artifact into a root dependency or establish Mojo runtime/app
support.
The runtime-free Bazel action seam now analyzes and executes under the prebuilt
Mojo configuration through the registered `@rules_mojo` toolchain, without a
direct compiler-binary visibility exception. It carries the pinned stdlib
sources into the action, emits an `arm64-apple-ios17.0-simulator` object, makes
an archive with the Simulator SDK `libtool`, and checks the extracted member's
`IOSSIMULATOR`/minOS 17 metadata plus `_mojo_add` and `_mojo_hello_utf8`. A
parallel example target uses the same action for
`arm64-apple-ios17.0`/`apple-a7` with the iPhoneOS SDK and checks the `IOS`
load command, so both canonical slices now have a Bazel archive seam. A
separate KGEN source filegroup exposes only the four SDK-bootstrap CompilerRT
sources. The action is deliberately local/non-sandboxed and discovers Xcode
SDK tools through `xcrun`; therefore this is a real Bazel archive artifact but
not yet a hermetic Bazel iOS toolchain or app build.
The rule now also returns a `CcInfo` compilation context for its generated
header and linking context for its generated archive, so a future same-graph
Apple target can consume the artifact without a `bazel-bin` path. This provider
seam is not itself Apple-rule registration, SDK declaration, or runtime support.
The disposable same-graph control attempts that next step without copying an
archive. Its ladder of dynamic, local-only overrides advances past the root's
versionless `rules_mojo` and Jammy sysroot dependencies, but `--nobuild` then
stops at the registered Mojo toolchain because the consumed `modular` module
cannot see its `@rules_mypy` load. A top-level override cannot repair a
dependency's development-dependency repository mapping. No Apple SDK action
runs until this Bzlmod contract is repaired in a dependency-owner change.
The expected-failure `Globals.cpp` link boundary is complemented by a separate
`GlobalsIOS.cpp` candidate: its named/indexed lookup, insertion, destruction,
and idempotent teardown pass a C++ Simulator consumer and an opt-in Simulator
launch marker. It remains an experimental implementation, is not wired into
the canonical serial core archives, and makes no lock-free, concurrent-destruction, or
AsyncRT claim.
The follow-on probe emits a real Mojo `std.ffi._Global` object, links it against
that separate SDK-built candidate, and observes
`MOJO_COMPILERRT_GLOBALS_MOJO_PROBE_PASS` on the Simulator. This validates the
current named-global symbol path and basic teardown only; it is not general
stdlib, `initialize_runtime`, or AsyncRT support.
An additional Error-construction probe now links a separate SDK-built
`StackTraceIOS.cpp` candidate with `MemoryIOS.cpp`, returns the documented
zero/null “stack trace not collected” result, and observes
`MOJO_COMPILERRT_ERROR_PROBE_PASS` on the Simulator. It does not claim throwing,
stack capture, `initialize_runtime`, or AsyncRT support.
A composite core-seed probe now compiles `MemoryIOS.cpp`, `Initialize.cpp`,
`GlobalsIOS.cpp`, `StackTraceIOS.cpp`, and `PrintIOS.cpp` into one fresh
Simulator archive,
links both emitted Mojo global and Error probes, and observes
`MOJO_COMPILERRT_CORE_SEED_PROBE_PASS`. This demonstrates only coexistence of
the narrow allocation, named-global teardown, and Error-construction paths;
the canonical serial core archive remains explicitly scoped, and no
`initialize_runtime`, AsyncRT, TCMalloc, throwing, stack capture, concurrent
global semantics, or device claim is made. The same source/probe set now has an
artifact-only device mode: it compiles and links for
`arm64-apple-ios17.0`/`apple-a7`, verifies `IOS`/iOS 17 metadata, and performs
no signing, installation, or physical-device launch.
The repository-built driver is now available at
`bazel-bin/KGEN/tools/mojo/mojo-full`; with `-I mojo/stdlib` it reproduces the
runtime-free object/archive/link/launch Simulator chain. It still rejects both
candidate `air64-apple-ios17.0` triples as unknown targets, so that is a
confirmed compiler gap rather than an installed-compiler provenance issue. An
iOS CPU source using `--target-accelerator metal:4` now stops earlier with an
actionable `Mojo iOS Metal AIR is not implemented` diagnostic, rather than
silently selecting the hard-coded macOS AIR sidecar. The earlier sidecar
failure remains useful historical evidence for the compiler seam, but neither
path is an iOS AIR/metallib implementation. For the current runtime-free
export fixture, `--emit exe` stops before linking because there is no `main`,
while `--emit shared-lib` now stops with an actionable iOS diagnostic before the
legacy macOS linker path; the supported workaround remains object/static-lib
emission followed by the matching Apple SDK linker.

### Scrutiny-adjusted next steps

The two companion scrutiny reports are checked in at
[`docs/ios/Mojo4iOSScrutinyCla.md`](docs/ios/Mojo4iOSScrutinyCla.md) and
[`docs/ios/Mojo4iOSScrutinyGem.md`](docs/ios/Mojo4iOSScrutinyGem.md). They do
not change the architecture or the staged destination, but they do tighten the
claims and the immediate order of work:

1. **Keep the evidence taxonomy explicit.** Report object emission, archive and
   link, Simulator launch, and physical-device execution as separate gates. A
   successful earlier gate must not be summarized as proof of a later one.
2. **Make compiler provenance part of every result.** The installed Mojo
   `1.0.0b1` used in the original independent probe does not recognize
   `--emit static-lib`; the repository-pinned fork has the archive path. Every
   report must record the compiler path/version and whether `ar` or the compiler
   produced the archive.
3. **Finish the missing D3 automation before calling the first delivery done.**
   Replace the current shell/source fixtures with a small `rules_apple`/
   `rules_swift` sample, an XCTest target for both C exports, and a UI test for
   the rendered values. Keep the shell harness as a low-level regression probe.
4. **Make D5a/D5b the physical-device gates.** Pair and unlock
   `iPhoneATT`, enable Developer Mode, create a development-signed app with
   user-supplied signing material, install it with `devicectl`/Apple's device
   services, and capture the launch result. The checked-in
   [`run_device_smoke.sh`](mojo/examples/ios/run_device_smoke.sh) covers D5a;
   [`run_device_swiftui.sh`](mojo/examples/ios/run_device_swiftui.sh) covers
   D5b. Both have artifact-only modes and explicit opt-in signing paths. The
   gates do not require an Xcode project or the Xcode GUI: they use the SDK
   command-line tools (`xcrun`, `clang`, `swiftc`, `codesign`, and `devicectl`).
   Device connectivity must retain a cable fallback: Apple’s current Device
   Hub documentation requires iOS/iPadOS 27 or later for first-time wireless
   pairing, while a device paired by cable can subsequently run over Wi-Fi on
   the same network. See [Apple’s pairing guidance](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac).
   TestFlight is an optional D5c distribution proof after D5b: it uploads a
   complete, distribution-signed app containing Mojo code, not an XCFramework
   or Mojo library by itself. Keep external TestFlight review and public-beta
   claims separate from this internal tracer milestone.
5. **Treat D8 as a product-by-product ladder.** The Accelerate/vDSP adapter now
   has compile/link coverage and an opt-in Simulator result-marker run. Add
   device execution and a benchmark before marking that product
   runtime-supported.
6. **Treat D9a as a public-API accelerator milestone.** Core ML is the supported
   iOS path for model graphs that may use the Neural Engine;
   `MLComputeUnits` is an allow-list for Core ML scheduling, not a Mojo ANE
   kernel API or a guarantee that every operation ran on ANE. Convert and
   package models on the Mac with `coremltools`, expose prediction through a
   Swift/Objective-C C ABI adapter, and require physical-device profiling
   before making an ANE claim. Accelerate/vDSP/BLAS/BNNS remains a direct
   C/CPU-vector path and must not be described as raw ANE access. See the
   detailed [Core ML and Accelerate appendix](docs/ios/ACCELERATORS_COREML_ACCELERATE.md).
7. **Prioritize D6 over framework breadth.** The serial static iOS CompilerRT
   and a small allocation/String/Error/environment/file test matrix unlock
   substantially more Mojo code than adding additional Apple framework names
   to the manifest. AsyncRT and parallel execution are the following D7 gate.

These adjustments are deliberately conservative: they preserve the genuine
Simulator result while preventing a two-function, runtime-free sample from
being mistaken for a complete iOS port.

## Post-Upstream Replan: Next Execution Sequence

The August 23 upstream rebase changes one important assumption in the original
ordering. The current `std.runtime.initialize_runtime()` implementation is not
a general allocator or String initializer. It calls only the three AsyncRT
CPU-device functions used to create, query, and release the process worker
runtime. The public documentation likewise requires it for APIs that depend on
that runtime, such as `parallelize()`. The already-running allocation, String,
Error, environment, and sandbox-file probes do not reference those three
symbols.

Consequently, D6 is now the **serial core-runtime milestone** and is not blocked
on AsyncRT. D7 owns AsyncRT initialization, parallel execution, threading, and
performance. This is a scope split, not a shortcut:

- Do not add a no-op implementation of the AsyncRT symbols merely to make
  `initialize_runtime()` link.
- Serial exports may allocate and use the supported core stdlib without calling
  `initialize_runtime()`.
- Exports using parallel, coroutine, or async facilities must call
  `initialize_runtime()` and remain unsupported on iOS until the D7 runtime
  passes its gates.
- Until then, an iOS use of an unsupported runtime-dependent API should produce
  a clear compile/link diagnostic rather than silently running with different
  semantics.

The Bazel blocker is independent. This repository currently runs a Bazel 10
rolling build, while its resolved graph contains transitive `rules_apple 4.1.0`
and `rules_swift 3.1.2`. Current rules_swift guidance requires at least 3.5.0
for Bazel 10, and the rules_apple 5.0 release candidates are the line declaring
rolling-Bazel compatibility. Adopting that line also changes protobuf and
Apple-support dependencies, so it must be a dependency-owner migration with
full graph tests, not an incidental iOS example edit. See the
[rules_swift compatibility table](https://github.com/bazelbuild/rules_swift#supported-bazel-versions)
and [rules_apple releases](https://github.com/bazelbuild/rules_apple/releases).

Execute the next work as these small, reviewable deliveries. A later delivery
must preserve every earlier exit gate.

| Order | Delivery | Work | Exit gate / stop condition |
| --- | --- | --- | --- |
| N1 | Runtime contract regression | Add emitted-object manifests for representative serial exports and assert that they do not acquire `KGEN_CompilerRT_AsyncRT_*` dependencies. Move repeated runtime initialization out of D6 acceptance text. | Simulator and device objects for allocation/String/Error/environment/files have an audited symbol allow-list and no AsyncRT names. |
| N2 | Core archive contract | Rename the bounded source group around a serial `CompilerRTIOSCore` contract; keep desktop `CompilerRT` and the host-built bootstrap distinct. Include only allocator, globals, initializer ABI, no-stack-trace Error support, and admitted libc shims. | Source membership and exported symbols are explicit; Python, JIT, Crashpad, profiling loaders, signals, TCMalloc, and AsyncRT are absent. |
| N3 | Global lifetime hardening | Replace the current experimental global-table concurrency caveat with an iOS-safe synchronization/lifetime design and stress it from multiple native host threads. | Named/indexed lookup, insertion, destroy callbacks, repeated teardown, and concurrent access pass under Thread Sanitizer where available. |
| N4 | Serial stdlib matrix | Add runtime probes for formatting/output, clocks, errno/error paths, collections, paths, restricted environment access, nested sandbox directories, and ordinary files. Keep compile-only inventory for every stdlib module. | Each supported serial module has Simulator execution and a device link artifact; unsupported APIs have an explicit diagnostic and no accidental desktop dependency. |
| N5 | Core ABI hardening | Test repeated exported calls, caller buffers, opaque handles, Error-to-status conversion, dead stripping, duplicate-runtime rejection, and clean process exit. | A stress consumer executes thousands of calls with no leak, race, double free, unresolved symbol, or duplicate runtime archive. |
| N6 | Apple-rule dependency trial | In a disposable branch, directly register a Bazel-10-compatible rules_apple/rules_swift pair, reconcile protobuf/apple_support/rules_cc changes, and run the full module graph plus KGEN/stdlib regressions. Prefer a stable release when it supports this Bazel build; otherwise pin a reviewed release candidate explicitly. | Module graph, `//KGEN:mojo`, CompilerRT, focused stdlib tests, and a minimal no-Mojo iOS app all analyze/build. Stop if dependency upgrades require unrelated product migrations that cannot be isolated. |
| N7 | Root iOS C++ toolchain | Register separate `iphoneos` and `iphonesimulator` SDK repositories and add iOS branches for sysroot, triple, libc++, compile, link, rpath, sanitizer, and platform suffix selections. | A one-file C++ target analyzes and builds for both Apple mobile platforms without ambient `xcrun` discovery inside its compile action. |
| N8 | Hermetic Mojo archives | Move the target-correct Mojo/core-runtime archive actions from example-local diagnostics onto the registered Apple toolchain and return correct `CcInfo`. | Sandboxed/reproducible Simulator and device archives have correct member metadata and are consumable in the same Bazel graph. |
| N9 | Canonical Bazel app | Instantiate `swift_library`, `ios_application`, XCTest, and UI-test targets around the runtime-free tracer, then the serial core runtime. | One Bazel command builds, installs, launches, checks both C exports, and asserts the visible greeting/calculation in an arm64 Simulator. |
| N10 | Clean package consumer | Package serial core device/Simulator slices as an XCFramework plus local Swift Package and validate from a clean app checkout. | The app runs in Simulator with no Mojo compiler or Modular install and with exactly one compatible core runtime per final binary. |
| N11 | AsyncRT target graph | Define the smallest behavior-preserving iOS AsyncRT source/dependency graph. Remove or parameterize desktop-only configuration, profiling, signal, and target-LLVM assumptions; select a malloc-backed allocator explicitly. | Every source compiles for both iOS SDKs and the graph contains no TCMalloc, compiler/JIT, private API, or desktop fault-handler dependency. Do not add ABI stubs if this gate fails. |
| N12 | Runtime initialization correctness | Link the real three AsyncRT CPU-device symbols, call public `initialize_runtime()` twice, query parallelism, and exercise a minimal task/chain lifecycle. A documented single-thread profile may be used only as a clearly temporary correctness stage. | Simulator launch passes initialization, idempotence, task completion, and teardown-by-process with no ABI carrier approximation. |
| N13 | Real worker pool | Enable the reviewed iOS worker queue, bound thread counts for mobile hardware, validate foreground/background and memory-pressure behavior, and add parallel map/reduce correctness. | Useful multicore scaling appears above documented thresholds without hangs, oversubscription, lifecycle violations, or unexplained energy cost. |
| N14 | Physical-device tracer/package | Run D5a/D5b and the serial core package on a signed iPhone and iPad; keep signing data outside the repository. | Captured device launch and visible Mojo result, followed by the same XCFramework consumer on device. TestFlight remains optional after this gate. |
| N15 | Device benchmarks and accelerator continuation | Run Swift/Mojo scalar, SIMD, allocation, C-boundary, and threading benchmarks; then resume Core ML, Metal, and SDK-coverage deliveries. | Reproducible device reports meet the D7 thresholds or contain a root-caused issue; no Simulator or unprofiled ANE performance claim. |

**Execution progress:** N1–N4 are complete. The allocating String, Error, `_Global`,
and combined environment/file objects now have exact undefined-symbol
allow-lists for both iOS triples, and the gate rejects every
`KGEN_CompilerRT_AsyncRT_*` dependency. The serial core now has an explicit
`CompilerRTIOSCoreSources` contract, canonical device/Simulator archive labels,
and archive-level forbidden symbol-family checks. `GlobalsIOS.cpp` now uses one
recursive mutex for creation, lookup, insertion, and teardown and passes 64
Simulator teardown/recreation rounds with eight concurrent native threads.
The implementation is deliberately not lock-free; the current host Thread
Sanitizer runtime exited before the test body, so no TSan claim is made. N4
adds a real Simulator serial-stdlib matrix and device link artifact covering
formatting/output, collections, clocks, errno/Error behavior, paths, restricted
environment access, nested sandbox directories, and ordinary files. All 38
top-level stdlib packages have compile-only coverage for both iOS triples, and
process spawning now has an explicit iOS compile-time diagnostic. N5 is next.

The immediate coding order is N1–N5, while N6–N9 should proceed as a separate
dependency/toolchain stack. N11 must begin with dependency isolation and may
run in parallel with those tracks, but N12 cannot be declared complete until
the real public `OptionalPointer` ABI and CPU-device semantics execute. Physical
device work is still valuable but is not a prerequisite for N1–N13.

## Phased Implementation Roadmap

### Phase 0 — Freeze the Support Contract

1. Repeat object-emission, linker, exported-symbol, and standard-library probes
   with the repository-pinned or locally built compiler.
2. Confirm the installed Simulator runtimes with `xcrun simctl list runtimes`
   and select an iOS 17-or-newer arm64 runtime.
3. Add a living support matrix covering Simulator and device targets, CPU
   architecture and defaults, runtime availability, standard-library modules,
   Swift integration, packaging, and Metal.
4. Establish the canonical triples and baseline CPUs:

   - Simulator: `arm64-apple-ios17.0-simulator`, CPU `apple-m1`.
   - Device: `arm64-apple-ios17.0`, CPU `apple-a7`, matching Apple clang's
     conservative device default.

5. Define cross-compilation using architecture, OS, and environment rather than
   architecture alone.
6. Reserve device-specific CPU selection for benchmark or application-local
   builds with an explicitly documented deployment set.
7. Open an upstream design discussion before broad compiler changes because the
   work crosses compiler, runtime, standard-library, and build-system
   boundaries.

For each probe, use a source file containing the two C ABI exports from Phase 1
and record the tool output alongside the compiler version:

```sh
mojo build \
  --target-triple arm64-apple-ios17.0-simulator \
  --target-cpu apple-m1 \
  --emit object source.mojo -o source-simulator.o
file source-simulator.o
xcrun vtool -show-build source-simulator.o
nm -gU source-simulator.o

mojo build \
  --target-triple arm64-apple-ios17.0 \
  --target-cpu apple-a7 \
  --emit object source.mojo -o source-device.o
file source-device.o
xcrun vtool -show-build source-device.o
nm -gU source-device.o
```

The expected invariants are `Mach-O 64-bit object arm64` from `file`, an
`LC_BUILD_VERSION` platform of `IOSSIMULATOR` with minimum OS 17.0 for the first
object and `IOS` with minimum OS 17.0 for the second from `vtool`, and the two
unmangled C symbols (shown with the platform underscore by `nm`) corresponding
to `mojo_add` and `mojo_hello_utf8`. The exact SDK/build-tool version strings
may vary and should be recorded, not hard-coded into compatibility tests.

**Exit gate:** The pinned compiler produces valid `IOS` and `IOSSIMULATOR`
objects. Checked-in discovery documentation or tests record exact commands and
expected `file`, `vtool`, and `nm` properties: arm64 Mach-O object format, the
correct platform load command and minimum OS, and the expected C symbols.

### Phase 1 — First Simulator Win Without the Mojo Runtime

1. Add a tiny Mojo module with two runtime-free C ABI exports:

   - `mojo_add(Int64, Int64) -> Int64`.
   - `mojo_hello_utf8(output, capacity) -> required_length`, using a
     caller-owned byte buffer and no heap allocation.

2. Add a handwritten C header for these first exports. Do not depend on the
   currently internal and unstable header generator.
3. Add a minimal SwiftUI host whose `Text` view displays the Mojo UTF-8 message
   and a calculation performed in Mojo.
4. Use `rules_apple` and `rules_swift` for the canonical repository sample. The
   app target should use an equivalent of:

   ```starlark
   ios_application(
       families = ["iphone", "ipad"],
       minimum_os_version = "17.0",
       # ...
   )
   ```

   These rules support building, signing, installing, and running Simulator
   applications from Bazel. See the
   [rules_apple iOS tutorial](https://github.com/bazelbuild/rules_apple/blob/main/doc/tutorials/ios-app.md).
5. Introduce a focused `mojo_ios_static_library` rule or macro. It should invoke
   the host Mojo compiler, emit the requested target object, archive it, and
   return C-linkable metadata to the Swift target. It must not create a second
   compiler pipeline.
6. Keep SwiftUI as the application entry point, consistent with Apple's
   [SwiftUI app organization](https://developer.apple.com/documentation/swiftui/app-organization).
7. Keep exploratory shell scripts and generated Xcode fixtures untracked unless
   they become reproducible parts of the sample or test suite.

**Exit gate:** One documented repository command builds, installs, and launches
the SwiftUI app in an arm64 iPhone Simulator. XCTest verifies both C exports,
and a UI test verifies that the app displays “Hello from Mojo on iOS.”

### Phase 2 — First-Class Apple Target and Build Plumbing

1. Add explicit Apple platform classification in the Mojo driver. macOS, iOS
   device, and iOS Simulator must not collapse into a generic Darwin or host
   check.
2. Correct same-architecture cross-compilation detection and introduce
   target-aware CPU defaults so an iOS build never inherits the Mac Studio's
   M-series features accidentally.
3. Generalize the existing macOS sysroot repository into Apple SDK repositories
   resolved through `xcrun` for `macosx`, `iphoneos`, and `iphonesimulator`.
4. Extend the Mojo Bazel toolchain so the Apple target configuration supplies
   the target triple, SDK, and minimum deployment version.
5. Make output extensions, linker selection, diagnostics, debug tooling, and
   post-link behavior derive from the target rather than the compiler host.
6. Keep `--emit object` as the first stable iOS compiler contract. For
   unsupported iOS `--emit exe` or `--emit shared-lib` combinations, produce an
   actionable diagnostic directing users to static-library and Xcode/Bazel
   integration.
7. Add `--emit static-lib` only after object emission is stable. Implement it as
   a thin archive-producing layer over the same object pipeline.

**Exit gate:** Cross-target tests verify triple classification, CPU defaults,
cross-compilation state, Mach-O platform load commands, relocations, exported
symbols, and target-aware diagnostics. Existing macOS and Linux behavior remains
unchanged.

### Phase 3 — Static iOS CompilerRT and Core Standard Library

The source/dependency inventory for this phase is maintained in
[`docs/ios/COMPILERRT_IOS_STATIC_RUNTIME.md`](docs/ios/COMPILERRT_IOS_STATIC_RUNTIME.md).
It is intentionally a separate implementation map: the existing desktop
`CompilerRT` target must not be reused through its source glob or shared-library
output name.

1. Split or parameterize `KGENCompilerRT` so iOS receives a statically linkable,
   application-safe runtime instead of `libKGENCompilerRTShared.dylib`.
2. Limit the initial serial runtime to what library code needs: globals,
   allocation, error support, admitted libc shims, and core system queries.
   AsyncRT and its worker pool belong to Phase 5/D7.
3. Exclude Python loading, compiler and JIT facilities, Crashpad, Tracy or plugin
   loading, dynamic profiling loaders, and globally installed fault handlers.
4. Require exported Mojo entry points that launch parallel work or use async or
   coroutine facilities to call `std.runtime.initialize_runtime()`. Serial
   allocation, String, Error, environment, and file operations do not require
   that CPU-device initializer. Preserve its idempotent, process-lifetime
   behavior when Phase 5 enables it.
5. Extend the standard-library target API with:

   - `CompilationTarget.is_ios()`.
   - `CompilationTarget.is_ios_simulator()`.
   - `CompilationTarget.is_darwin()` for shared macOS/iOS ABI behavior.
   - `platform_map(..., ios=..., darwin=...)`, with exact-platform values taking
     precedence over Darwin defaults.

6. Refactor genuinely shared layouts and constants from `_macos` into Darwin
   implementations. Validate C structure sizes, alignments, offsets, exported
   symbols, and availability against both macOS and iOS SDKs.
7. Classify standard-library modules and encode unsupported behavior as clear
   compile-time diagnostics:

   - **Supported:** builtins, math, SIMD, collections, memory, formatting,
     clocks, libc output, sandbox-compatible files, and errno.
   - **Supported with restrictions:** environment access, filesystem paths,
     dynamic loading of bundled code, and system queries.
   - **Unavailable initially:** subprocess and process spawning, Python,
     REPL/JIT features, and APIs incompatible with the iOS sandbox.

**Exit gate:** Simulator tests cover output, allocation and deallocation,
strings, errors, restricted environment access, sandboxed files, repeated
C-ABI calls, global teardown, dead stripping, and clean process exit without
unresolved runtime symbols. The emitted serial objects contain no
`KGEN_CompilerRT_AsyncRT_*` dependency. Runtime initialization and parallel
execution are Phase 5 gates.

### Phase 4 — Physical Device and Reusable Packaging

1. Build the same SwiftUI sample for `arm64-apple-ios17.0` and run it on a
   development-signed iPhone or iPad. The runtime-free C-ABI fixture has D5a
   as a lower-level tracer bullet; D5b is the user-visible gate and must show
   Mojo-returned text and arithmetic on the physical screen.
2. Keep signing identities, team IDs, device identifiers, and provisioning
   profiles outside tracked defaults.
3. Produce separate static archives for device and Simulator. Never combine
   device and Simulator variants with `lipo`.
4. Combine each Mojo library variant with exactly one compatible static
   CompilerRT to avoid runtime deployment, duplicate-runtime, and install-name
   issues.
5. Package both variants, public headers, and a Clang module map:

   ```sh
   xcodebuild -create-xcframework \
     -library <device-library> -headers <headers> \
     -library <simulator-library> -headers <headers> \
     -output MojoLibrary.xcframework
   ```

6. Add a local Swift Package binary target and a small Swift wrapper that maps
   safe Swift values to the C ABI. Ship the framework-coverage manifest and
   adapter modules as package products, so a consumer can import the same
   public surface whether its UI is SwiftUI, UIKit, or another public Apple
   framework.
7. Keep the ABI deliberately C-shaped: scalar/POD arguments, caller-owned
   buffers, opaque handles with explicit destroy functions, C callbacks, and
   integer error codes. Never expose Mojo-owned strings, collections,
   exceptions, or native Mojo layouts directly to Swift.
8. Validate the package from a clean consumer app. Apple requires distinct
   platform variants and recommends XCFrameworks for libraries produced by
   alternate build systems. See
   [Apple XCFramework guidance](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle).

9. Optionally upload the visible tracer app as a distribution-signed TestFlight
   build after the physical-device gate. Start with an internal tester group;
   external testing may require beta review and the app must be suitable for
   public distribution. TestFlight validates signing, App Store Connect
   processing, and over-the-air installation, but does not expand Mojo runtime
   or standard-library coverage.

The low-level Mojo library, C consumer, archive, app bundle, and physical
device launch should remain reproducible with command-line tools. `xcodebuild`
and an Xcode project are optional conveniences for the SwiftUI host, XCTest,
code-signing configuration, and consumer-app validation; they are not a
prerequisite for the first physical-device Mojo proof.

**Exit gate:** The same package works unmodified in an iPhone Simulator and on
a physical iPhone or iPad. A clean consumer can import the core Mojo product
and at least one Apple-framework adapter product without installing the Mojo
compiler or Modular tooling. The package includes a versioned framework
coverage manifest; every listed public framework has a direct, adapter,
compile-only, or unavailable status and a linked test/diagnostic.

### Phase 5 — CPU, SIMD, Threading, and Swift Benchmarks

1. Build a target-correct, statically linkable iOS AsyncRT graph with explicitly
   reviewed CPU-device, allocator, worker-queue, profiling, and shutdown policy.
   Do not satisfy its ABI with no-op stubs.
2. Validate the public `std.runtime.initialize_runtime()` ABI directly: call it
   twice, query `parallelism_level()`, run minimal task/chain and parallel
   correctness probes, and keep the runtime alive for process lifetime.
3. Run correctness tests in Simulator, but prohibit Simulator measurements from
   being used in performance claims.
4. Add an on-device release benchmark app comparing:

   - Mojo scalar code with equivalent optimized Swift.
   - Mojo explicit SIMD and auto-vectorized loops with Swift loops.
   - Mojo parallel CPU work with Swift structured concurrency.
   - Both languages with Accelerate/vDSP or Metal Performance Shaders as an
     optimized platform ceiling.

5. Begin with vector transform, reduction, dot product, image convolution,
   small and large matrix multiplication, allocation-heavy processing, and
   parallel map/reduce.
6. Allocate and initialize data outside timed regions. Use identical buffers
   and algorithms, warmups, many iterations, result validation, and separate
   measurements of C-boundary overhead.
7. Record compiler version, optimization flags, target CPU and features,
   device/chip, OS, workload size, thermal state, median and p95 latency,
   throughput, peak memory, binary size, and energy observations.
8. Inspect emitted assembly to confirm NEON/vector instructions. Use Instruments
   and signposted regions to profile CPU occupancy and call trees; Apple's
   [OSSignposter](https://developer.apple.com/documentation/os/ossignposter)
   supports isolating timed work.
9. Require Mojo to achieve at least 90% of optimized Swift throughput for
   equivalent compute-bound implementations, or record a root-caused
   compiler/runtime issue before calling the workload supported. Accelerate and
   MPS results are informative ceilings, not pass/fail gates.

**Exit gate:** Public runtime initialization is idempotent and the real AsyncRT
task path executes correctly in Simulator. Reproducible physical-device reports
then demonstrate correct SIMD generation, useful multicore scaling above
documented workload thresholds, controlled runtime overhead, and no unexplained
large regression against equivalent Swift.

### Phase 6 — Apple Framework Interoperability

1. Preserve the architecture boundary: SwiftUI and lifecycle code remain Swift;
   Mojo implements reusable computation and systems code.
2. Support Swift calling Mojo through maintained or generated C headers and
   Clang module maps.
3. Treat “Apple libraries available in Mojo” as an API-coverage objective for
   the public iOS/iPadOS SDK, not as a promise to reproduce every Swift ABI
   detail. Maintain an inventory per Xcode SDK of framework, minimum OS,
   availability annotations, ownership model, and binding status. A framework
   is supported when its documented public APIs are callable from Mojo through
   one of the following stable tiers:

   1. Direct bindings for public C APIs such as Darwin, CoreFoundation,
      Accelerate/BLAS, and `os` facilities.
   2. Objective-C or Swift adapter modules exposing stable C functions for
      Foundation and UIKit object APIs, SwiftUI view/model adapters, Metal,
      AVFoundation, Core ML, and other non-C frameworks.
   3. Registered C callbacks for lifecycle events, asynchronous completion, and
      data delivery from Swift to Mojo.

   Keep the checked-in
   [Apple framework coverage inventory](mojo/examples/ios/APPLE_FRAMEWORK_COVERAGE.md)
   as the source of truth for package support. Promote it into a
   machine-readable manifest during packaging, with one package product for the
   core Mojo ABI and separate adapter products for framework families. A
   package release cannot silently claim “all iOS libraries”: an SDK framework
   absent from the manifest is a release-blocking coverage gap.

4. Prioritize the first public framework coverage wave as Foundation,
   CoreFoundation, CoreGraphics, UIKit, SwiftUI, Metal, Accelerate/vDSP/BNNS,
   `os`/signposts, AVFoundation, and Core ML. Add later frameworks through the
   same inventory and adapter conventions rather than creating framework-specific
   ABI exceptions.
5. Add a Clang-based binding generator only after handwritten bindings establish
   conventions for naming, availability, nullability, ownership, callbacks, and
   error handling.
6. Treat direct Swift ABI support—including declaring SwiftUI `View` or `App`,
   Swift generics and protocols, and opaque result types in Mojo—as a separate
   language/compiler research project, not a prerequisite for iOS support.
7. Follow Swift's normal Clang-module import model for packaged native
   libraries. See
   [Swift C/C++ interoperability](https://www.swift.org/documentation/cxx-interop/).

**Exit gate:** A sample app uses Mojo computation together with at least one C
Apple framework and one Objective-C or Swift adapter, without unsafe ownership
crossing the boundary. A clean Swift Package consumer imports the core product
and an adapter product. The framework inventory identifies which public APIs are
covered directly, covered through adapters, compile-only, or still unavailable;
“all Swift libraries” is measured by that inventory rather than by an unsafe
direct Swift ABI claim.

### Phase 6A — Full Public SDK Package Coverage

This is the package-wide extension of Phase 6. SwiftUI remains the first
vertical slice, but the deliverable is an auditable family of package products
covering the public iOS/iPadOS SDK.

1. **Crawl:** enumerate public frameworks and module headers from the selected
   Xcode SDK; record minimum OS, availability, nullability, ownership, required
   entitlements, and whether the framework is C, Objective-C, Swift, or mixed.
2. **Walk:** for each framework, land the smallest safe surface in one of the
   direct-C, adapter, callback, compile-only, or unavailable tiers. Keep each
   adapter in its own Swift/Objective-C target and expose only stable C entry
   points to Mojo.
3. **Run:** compile every manifest entry for both `iphoneos` and
   `iphonesimulator`, run Simulator correctness tests for the supported subset,
   and run device tests for APIs whose behavior depends on hardware,
   entitlements, sensors, cameras, or GPU families.
4. **Package:** publish the core Mojo product, framework adapter products, C
   headers, Clang module maps, availability metadata, and the XCFramework in a
   local Swift Package. A consumer must be able to import only the products it
   uses; linking an unrelated framework must not be required.
5. **Audit:** fail packaging when a public SDK framework is missing from the
   manifest, when an adapter lacks ownership/teardown tests, or when a
   compile-only entry is accidentally labeled runtime-supported.
6. **Expand:** add Foundation, CoreFoundation, CoreGraphics, Accelerate,
   UIKit, SwiftUI, Metal, `os`, AVFoundation, and Core ML first, then add later
   public frameworks through the same manifest and adapter rules.

**Exit gate:** A clean Swift Package consumer imports the core product and at
least two framework products from different tiers, runs on Simulator, and has
an inventory report showing every public SDK framework as direct, adapter,
callback, compile-only, or unavailable with a reason and test reference.

### Accelerator strategy: Metal, Core ML/ANE, Accelerate, and private research

The roadmap deliberately separates four mechanisms that are often conflated:

1. **Mojo-generated Metal (direct programmable path).** Mojo can eventually
   lower kernels to Apple AIR, link them to an iOS-compatible `.metallib` on
   the Mac, and bundle that resource in an app. A small Swift or Objective-C++
   host bridge owns `MTLDevice`, buffers, pipeline state, dispatch, and
   synchronization; Mojo sees a stable C ABI. No shader compiler, JIT, network
   download, or executable-code generation runs on the device. The current
   macOS implementation is a useful lowering reference, but its exact
   `air64-apple-macosx` predicates, M-series presets, and host-side launch
   machinery are not proof of iOS support. The detailed staged work is in
   [ACCELERATORS_METAL_IOS.md](docs/ios/ACCELERATORS_METAL_IOS.md).
2. **Core ML (supported public ANE route).** Convert a model or ML Program on
   the Mac with `coremltools`, bundle the resulting `.mlpackage` or compiled
   model, and call it from a Swift/Objective-C adapter. Configure
   `MLModelConfiguration.computeUnits` with `.all` by default, or restrictive
   values such as `.cpuAndNeuralEngine` for a diagnostic/fallback experiment.
   These values allow or exclude compute units; they do not submit arbitrary
   Mojo kernels to ANE, reserve an ANE, or prove placement. Core ML may
   partition a graph across CPU, GPU, and ANE, so ANE usage must be demonstrated
   with physical-device tooling and raw evidence. See Apple's
   [MLComputeUnits documentation](https://developer.apple.com/documentation/coreml/mlcomputeunits)
   and the repository's [Core ML and Accelerate appendix](docs/ios/ACCELERATORS_COREML_ACCELERATE.md).
3. **Accelerate (supported public CPU/DSP route).** Bind vDSP/vForce,
   BLAS/LAPACK, and BNNS through direct C headers or a narrow adapter. This is a
   valuable CPU/SIMD and linear-algebra path, and BNNS can execute supported
   CPU-side neural-network graphs, but Accelerate is not a public raw ANE
   programming API. Benchmark it against Mojo SIMD and Metal rather than
   labeling it Neural Engine execution. See Apple's
   [Accelerate overview](https://developer.apple.com/accelerate/).
4. **oMLX-style private ANE (quarantined research only).** The adjacent
   `dflash2qwen` experiment is a macOS-specific, fixed-shape hybrid design: it
   selects approximate INT8 prefill rows, uses private `_ANE*` interfaces and
   IOSurface plumbing, overlaps selected ANE work with Metal, and leaves decode
   and other stateful work on Metal. Its local Mojo facade explicitly identifies
   itself as a scaffold: class discovery, IOSurface allocation, conceptual
   procedure states, or CPU reference loops do not prove ANE compile/load/eval.
   Private selectors, device-specific split ratios, eager procedure banks, and
   dual-ANE assumptions must not enter an iOS package, TestFlight artifact, or
   App Store build. Keep any future private-ANE experiment in a separately
   opted-in macOS target with real compile/load/warm/evaluate counters and
   fail-closed errors. The evidence and quarantine rules are in
   [ACCELERATORS_ANE_Omlx.md](docs/ios/ACCELERATORS_ANE_Omlx.md).

This yields a crawl-walk-run order: first prove public Core ML and Accelerate
adapters with explicit device measurements, then prove one Mojo Metal kernel
end to end, then experiment with hybrid partitioning only behind public-API or
clearly quarantined research boundaries. Do not promise “ANE support” because a
model loaded with `.all` succeeds, because private classes are discoverable, or
because a benchmark reports a configured ANE flag.

### Phase 7 — iOS Metal Compute

1. Reuse the existing Mojo AIR lowering, Apple GPU standard-library primitives,
   kernel implementations, and optimization work wherever they are
   target-independent.
2. Replace hard-coded `air64-apple-macosx` assumptions with platform-aware AIR
   targets and iOS deployment-compatible Metal/AIR versions.
3. Model iPhone and iPad GPU capabilities through Metal GPU families queried
   from `MTLDevice`. Do not map A-series devices blindly onto the current M1–M5
   names.
4. Compile Mojo kernels into metallibs on the Mac during the application build
   and bundle them as resources. Do not compile or download executable kernels
   on the device.
5. Add a small Objective-C++ or Swift Metal host bridge for device discovery,
   buffer management, pipeline creation, dispatch, synchronization, and error
   conversion.
6. Start with vector addition and reduction, then move to progressively larger
   kernels only after correctness and profiling infrastructure is stable.
7. Compare Mojo-generated metallibs with equivalent handwritten Metal Shading
   Language and MPS implementations using GPU traces, occupancy, bandwidth,
   limiter counters, and thermal data. Apple documents
   [GPU counter statistics](https://developer.apple.com/documentation/xcode/analyzing-apple-gpu-performance-using-counter-statistics)
   for profiling Apple GPUs.

**Exit gate:** Precompiled Mojo Metal kernels run correctly on at least one
iPhone class and one iPad class, require no runtime shader compilation, and have
explained performance relative to handwritten MSL and MPS.

### Phase 7A — Public Core ML and Neural Engine integration

1. Convert representative models on the Mac with a pinned `coremltools`
   toolchain. Record source-model hashes, input/output contracts, precision,
   shapes, minimum deployment target, and the emitted `.mlpackage` or compiled
   model hash. Keep conversion and model artifacts out of the on-device Mojo
   compiler path.
2. Add a Swift/Objective-C adapter linked against `CoreML.framework`. Expose a
   narrow C ABI to Mojo using caller-owned typed buffers or opaque model
   handles, explicit create/destroy functions, integer status codes, and
   bounded diagnostics. Keep `MLModel`, `MLMultiArray`, Swift concurrency, and
   Objective-C ownership on the adapter side.
3. Start with `MLModelConfiguration.computeUnits = .all`, then run diagnostic
   variants such as `.cpuOnly`, `.cpuAndGPU`, and `.cpuAndNeuralEngine` where
   the deployment target supports them. Treat these as scheduling constraints,
   not as direct engine-selection or kernel-programming APIs.
4. Validate conversion parity on macOS, then validate cold/warm load,
   numerical tolerances, malformed inputs, memory, latency, energy, and
   thermal behavior on physical iPhone and iPad devices. Use Core ML and
   Neural Engine Instruments or equivalent Apple tooling to substantiate any
   statement that work actually ran on ANE; a successful prediction or a
   compute-unit flag alone is insufficient.
5. Add hybrid experiments only after a complete Core ML graph is correct:
   Mojo owns CPU/Metal preprocessing and postprocessing while Core ML owns a
   supported subgraph. Begin with explicit copies and synchronization; attempt
   IOSurface or Metal-buffer sharing only after lifetime, stride, dtype, and
   cache-coherency tests pass.

**Exit gate:** A clean signed device app runs a bundled public Core ML model
through the Mojo C ABI, passes the reference tolerance and failure matrix on
an iPhone and iPad class, and publishes raw device evidence for the selected
compute-unit configurations. The result may say “Core ML used an eligible
compute unit”; it must not claim arbitrary Mojo code ran on ANE.

### Phase 7B — Optional macOS private-ANE research (never an iOS deliverable)

1. Keep oMLX-style work in a separately opted-in macOS target and build
   configuration. Exclude private frameworks, selectors, private dylibs, and
   ANE bridge objects from iOS, XCFramework, TestFlight, and App Store
   artifacts.
2. Port one claim at a time: capability probe; real fixed-shape compile;
   load/warm/evaluate; checked output; IOSurface/Metal ownership; then dual-
   instance overlap. Class discovery, procedure counts, registry flags, and
   CPU reference loops are not success evidence.
3. Require explicit per-procedure execution counters, native error propagation,
   timeout/cancellation handling, transactional state rollback, and a fail-
   closed result when any requested procedure is missing or falls back.
4. Pin hardware, OS, model, INT8 conversion, tile shape, split ratios, and
   thermal/memory conditions. Compare against GPU-only Mojo and oMLX with raw
   tensor/token correctness records as well as throughput; do not generalize a
   dual-ANE M3 Ultra result to iPhone or iPad.

**Exit gate:** This phase can produce a reproducible macOS research report,
but it never changes the supported iOS package contract. A future public Apple
API may replace this phase; private API discovery is not an upstreaming gate.

### Phase 8 — Hardening and Upstreaming

1. Add macOS CI jobs for iOS object emission, static runtime linking,
   XCFramework creation, Simulator unit tests, and the SwiftUI smoke app.
2. Keep development-signed physical-device and performance runs as separately
   provisioned CI or manual gates.
3. Fuzz and ABI-test exported structures, callbacks, buffers, error paths, and
   ownership boundaries.
4. Document Xcode, Bazel, SwiftPM, device signing, symbolication, App Store
   constraints, and unsupported APIs.
5. Submit changes as reviewable stacks: target classification, build toolchain,
   Simulator sample, static runtime, standard library, device packaging,
   benchmarks, framework interoperability, and Metal.
6. Keep all shipped execution AOT. This avoids relying on downloaded or
   feature-changing executable code, which Apple restricts under App Review
   rule 2.5.2. See the
   [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

**Exit gate:** The documented support matrix is continuously tested, a clean
consumer can integrate the release artifact, unsupported features fail clearly,
and the upstream change series is split into independently reviewable units.

## Test and Acceptance Matrix

Every phase must preserve earlier gates. A feature is not considered supported
until its corresponding tests run in the intended target environment.

| Area | Required coverage and acceptance criteria | First required phase |
| --- | --- | --- |
| Compiler | Both triples; target-aware CPU defaults; correct cross-compilation state; Mach-O platform metadata; debug information; stable C ABI symbols; actionable unsupported-link diagnostics | 0–2 |
| Serial core runtime | Static link; globals; allocation; errors; restricted environment/files; repeated C-ABI calls; process-lifetime shutdown; dead stripping; no unresolved, duplicate, or AsyncRT runtime symbols | 3 |
| Async runtime | Two public initialization calls; real CPU-device ABI; task/chain correctness; threading; process-lifetime ownership; no TCMalloc or desktop-only dependency unless explicitly approved | 5 |
| Standard library | Compile-only coverage for every module; runtime coverage for the supported subset; explicit diagnostics for restricted or unavailable APIs | 3 |
| Swift integration | Swift unit tests for every exported ABI; caller-owned buffer and opaque-handle tests; callback and error-path coverage | 1–6 |
| Application integration | SwiftUI UI test; iPhone and iPad Simulator build/install/launch; runtime-free physical artifact launch; visible SwiftUI physical “Hello from Mojo”; clean XCFramework consumer | 1, D5a–D5b, and 4 |
| Compatibility | No macOS or Linux regression; configurable deployment target with iOS 17 as the tested baseline | Every phase |
| CPU performance | On-device scalar, SIMD, allocation, C-boundary, and threading baselines; recorded toolchain, device, thermal, latency, throughput, memory, and energy context | 5 |
| Public ML acceleration | Core ML conversion/package hashes; C adapter ownership/error tests; `.all` and diagnostic compute-unit runs; physical-device numerical, thermal, and ANE-tool evidence; Accelerate/vDSP/BLAS/BNNS parity | 6A–7A |
| Metal performance | Correctness and on-device measurements against MSL/MPS only after the GPU phase; no Simulator performance claims | 7 |
| Distribution | No JIT, Python, compiler binaries, loose dynamic libraries, private Apple APIs, user-specific signing material, or merged device/Simulator `lipo` binary; optional internal TestFlight build uses distribution signing and a complete app bundle | 4–8 and D5c |

## Assumptions and Follow-Up Platforms

- iPhone and iPad are the only initial Apple mobile families. watchOS, tvOS,
  visionOS, and Mac Catalyst are follow-up ports after the iOS abstractions are
  proven.
- arm64 Simulator support is sufficient for the current Mac Studio. Add an
  x86_64 Simulator slice only if a supported Xcode/Intel CI environment still
  requires it.
- A physical device and Apple development signing identity will be available by
  Phase 4.
- “Direct SwiftUI support” means a supported SwiftUI host calling Mojo; it does
  not mean implementing SwiftUI's Swift protocols inside Mojo.
- The initial deliverable is a reusable Mojo native library, not a standalone
  Mojo-owned iOS application process.
- macOS Metal support is a valuable implementation reference, but iOS GPU
  capability discovery, AIR target metadata, deployment rules, resource
  packaging, and performance validation remain explicit porting work.
