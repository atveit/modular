# Mojo on an iOS Simulator: an end-to-end tutorial

This tutorial walks from a Mojo source file to a running SwiftUI app on an
iPhone Simulator. Every command below is a reproducible command for the
checked-in discovery harness.

The result is a real ahead-of-time compiled Mojo object, placed in a native
static archive, linked by Swift, packaged as an iOS app, ad-hoc signed,
installed, and launched by CoreSimulator. The Mojo functions are called first
by a C consumer and then by SwiftUI through a handwritten C header.

## What this proves (and what it does not)

The first slice is intentionally runtime-free. The Mojo module uses scalar
values and a caller-owned byte buffer. It does not allocate, start the Mojo
runtime, use Python, or use the JIT. This proves the target-object and Apple
linker path before the iOS static CompilerRT and full stdlib runtime are ready.

The current proof covers:

- Mojo source compiled for arm64-apple-ios17.0-simulator.
- A valid arm64 Mach-O object with an IOSSIMULATOR load command.
- A real ar archive consumed by Apple clang and Swift.
- C ABI calls returning 42 and Hello from Mojo on iOS.
- A SwiftUI App/View calling the same Mojo functions.
- A signed .app installed and launched on an iPhone Simulator.

It does not yet prove the full Mojo stdlib, static CompilerRT, physical-device
packaging, XCTest integration, XCFramework distribution, or Metal kernels.
Those are the next phases in MojoOniOSPlan.md.

## Prerequisites

Use an Apple Silicon Mac with:

- Xcode with both iphoneos and iphonesimulator SDKs;
- an iOS 17-or-newer Simulator runtime and an available iPhone Simulator;
- clang, ar, swiftc, codesign, nm, file, vtool, and xcrun;
- this repository checked out locally.

Check the toolchain before compiling:

~~~sh
cd /path/to/modular
uname -m
xcodebuild -version
xcrun --sdk iphonesimulator --show-sdk-path
xcrun simctl list runtimes
xcrun simctl list devices available | sed -n '1,40p'
mojo --version
swiftc --version
~~~

The tested machine had an arm64 Mac Studio, Xcode 26.2, an iOS 26.0 runtime,
and an iPhone 17 Pro Simulator. The source contract uses iOS 17 as its minimum
deployment target, so a newer installed runtime is fine.

## 1. Choose and record the Mojo compiler

The repository pins a newer development compiler than an independently
installed mojo on PATH. Always record which compiler is being used:

~~~sh
export MOJO_BIN=mojo
"$MOJO_BIN" --version
~~~

For a repository-pinned or locally built compiler, set both its path and the
checkout's stdlib import root when required:

~~~sh
export MOJO_BIN=/absolute/path/to/pinned/or/locally-built/mojo
export MOJO_STDLIB_PATH="$PWD/mojo/stdlib"
"$MOJO_BIN" --version
~~~

The repository build wrapper requires an explicit configuration. Use
build-mojo when changing compiler sources, or prebuilt-mojo when consuming
the pinned toolchain:

~~~sh
./bazelw build --config=build-mojo //KGEN:mojo
# or:
./bazelw build --config=prebuilt-mojo //KGEN:mojo
~~~

These full compiler builds can consume substantial disk space. They are not
needed for the first discovery run; use an explicit MOJO_BIN path once a
local compiler is available. The smoke script never substitutes another
compiler for a path supplied in MOJO_BIN.

## 2. Inspect the Mojo source and C boundary

The source is mojo/examples/ios/mojo_ios_smoke.mojo:

~~~mojo
@export("mojo_add")
def mojo_add(lhs: Int64, rhs: Int64) abi("C") -> Int64:
    return lhs + rhs


@export("mojo_hello_utf8")
def mojo_hello_utf8(
    output: UnsafePointer[UInt8, MutAnyOrigin], capacity: Int64
) abi("C") -> Int64:
    comptime message_length = 23
    if capacity <= 0:
        return message_length

    # The checked-in fixture writes the 23 ASCII bytes into output.
~~~

The handwritten header is mojo/examples/ios/mojo_ios_smoke.h:

~~~c
int64_t mojo_add(int64_t lhs, int64_t rhs);
int64_t mojo_hello_utf8(uint8_t *output, int64_t capacity);
~~~

This is the intended initial boundary: POD values, caller-owned buffers, and
integer length/error results. Do not expose Mojo-owned strings, collections,
exceptions, or raw native layouts here.

## 3. Build the Mojo object, archive, and C consumer

Use a writable output directory. The harness emits a target object, archives
it, compiles the C consumer with the iPhone Simulator SDK, links an arm64
executable, signs it, and checks its Mach-O metadata.

~~~sh
export IOS_OUT=/tmp/mojo-ios-tutorial
mkdir -p "$IOS_OUT/mojo-cache"

MOJO_CRASHPAD=0 \
MODULAR_CACHE_DIR="$IOS_OUT/mojo-cache" \
MOJO_BIN="$MOJO_BIN" \
MOJO_STDLIB_PATH="$MOJO_STDLIB_PATH" \
MOJO_IOS_SMOKE_OUT="$IOS_OUT/smoke" \
  mojo/examples/ios/run_simulator_smoke.sh
~~~

If the compiler says it cannot locate std, set the source stdlib explicitly
and rerun:

~~~sh
MOJO_STDLIB_PATH="$PWD/mojo/stdlib" \
MOJO_IOS_SMOKE_OUT="$IOS_OUT/smoke" \
  mojo/examples/ios/run_simulator_smoke.sh
~~~

The C consumer in mojo/examples/ios/smoke_main.c asserts the actual ABI results:

~~~c
assert(mojo_add(20, 22) == 42);
uint8_t message[23] = {0};
assert(mojo_hello_utf8(message, 23) == 23);
assert(mojo_hello_utf8(NULL, 0) == 23);
~~~

To request the C app's Simulator installation and launch:

~~~sh
RUN_SIMULATOR=1 \
MOJO_IOS_SMOKE_OUT="$IOS_OUT/smoke" \
  mojo/examples/ios/run_simulator_smoke.sh
~~~

## 4. Verify that the artifacts are Mojo-to-iOS artifacts

Do not rely only on a successful shell exit. Inspect the actual files:

~~~sh
file "$IOS_OUT/smoke/mojo_ios_smoke.o" \
     "$IOS_OUT/smoke/libmojo_ios_smoke.a" \
     "$IOS_OUT/smoke/mojo_ios_smoke_simulator"

ar -t "$IOS_OUT/smoke/libmojo_ios_smoke.a"

nm -gU "$IOS_OUT/smoke/mojo_ios_smoke.o" | \
  grep -E '(_?mojo_add|_?mojo_hello_utf8)$'

vtool -show-build "$IOS_OUT/smoke/mojo_ios_smoke.o"
vtool -show-build "$IOS_OUT/smoke/mojo_ios_smoke_simulator"

codesign --verify --deep --strict "$IOS_OUT/smoke/mojo_ios_smoke.app"
~~~

Expected evidence includes:

~~~text
Mach-O 64-bit object arm64
current ar archive random library
Mach-O 64-bit executable arm64
_mojo_add
_mojo_hello_utf8
platform IOSSIMULATOR
minos 17.0
~~~

The IOSSIMULATOR load command is essential. The host is also arm64, but this
is still cross-compilation because the target OS and environment differ from
macOS.

The same runtime-free source can be checked against the physical-device
triple without signing or installing a device app:

~~~sh
MOJO_CRASHPAD=0 \
MODULAR_CACHE_DIR="$IOS_OUT/device-cache" \
MOJO_BIN="$MOJO_BIN" \
MOJO_STDLIB_PATH="$MOJO_STDLIB_PATH" \
MOJO_IOS_TRIPLE=arm64-apple-ios17.0 \
MOJO_IOS_SMOKE_OUT="$IOS_OUT/device" \
  mojo/examples/ios/run_simulator_smoke.sh

vtool -show-build "$IOS_OUT/device/mojo_ios_smoke.o"
vtool -show-build "$IOS_OUT/device/mojo_ios_smoke_device"
~~~

The device probe must report platform IOS, minimum OS 17.0, arm64, the same
two C symbols, and an ar archive. It intentionally does not sign or install:
physical-device signing belongs to the later development-provisioning gate.

## 5. Compile the SwiftUI host

The SwiftUI source is mojo/examples/ios/swiftui_host/MojoIOSSmokeApp.swift:

~~~swift
import SwiftUI
import MojoIOSSmoke

private func messageFromMojo() -> String {
    var bytes = [UInt8](repeating: 0, count: 23)
    let length = bytes.withUnsafeMutableBufferPointer { buffer in
        mojo_hello_utf8(buffer.baseAddress, Int64(buffer.count))
    }
    guard length == 23 else { return "Mojo returned an invalid message length" }
    return String(decoding: bytes, as: UTF8.self)
}

struct ContentView: View {
    private let sum = mojo_add(20, 22)
    private let message = messageFromMojo()

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
            Text("20 + 22 = \(sum)")
        }
        .padding()
    }
}

@main
struct MojoIOSSmokeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
~~~

First compile it without linking. This isolates SwiftUI/module-map errors from
linker and signing errors:

~~~sh
mojo/examples/ios/swiftui_host/compile_swiftui_host.sh
~~~

The command emits an arm64 Simulator Swift object and module. The module map
imports the handwritten header; the Mojo archive is linked next.

The first non-SwiftUI Apple framework seam is a direct-C Accelerate/vDSP
adapter. It is deliberately separate from the Mojo archive so framework
ownership and availability can be tested independently:

~~~sh
mojo/examples/ios/accelerate_adapter/run_accelerate_smoke.sh
~~~

That probe compiles a C adapter against Accelerate.framework, links a Swift
consumer, checks the arm64/IOSSIMULATOR load command and exported adapter
symbol, and confirms the framework load command with otool. It is compile/link
coverage—not yet a runtime or physical-device support claim.

## 6. Link, sign, install, and launch SwiftUI

Link the SwiftUI host with the archive from step 3:

~~~sh
MOJO_IOS_ARCHIVE="$IOS_OUT/smoke/libmojo_ios_smoke.a" \
MOJO_IOS_SWIFT_LINK_OUT="$IOS_OUT/swiftui" \
  mojo/examples/ios/swiftui_host/link_swiftui_host.sh
~~~

This command asks swiftc for arm64-apple-ios17.0-simulator, imports the Mojo C
declarations through the module map, links with the iPhone Simulator SDK,
sets SDKROOT, packages and ad-hoc signs a minimal .app, and checks the final
image with file, vtool, nm, and codesign.

To install and launch it:

~~~sh
RUN_SIMULATOR=1 \
MOJO_IOS_ARCHIVE="$IOS_OUT/smoke/libmojo_ios_smoke.a" \
MOJO_IOS_SWIFT_LINK_OUT="$IOS_OUT/swiftui" \
  mojo/examples/ios/swiftui_host/link_swiftui_host.sh
~~~

Set and export SIMULATOR_UDID for a specific device:

~~~sh
xcrun simctl list devices available
export SIMULATOR_UDID=CC1A4BA7-8BED-480B-BE99-FD93E7DD1495
RUN_SIMULATOR=1 \
MOJO_IOS_ARCHIVE="$IOS_OUT/smoke/libmojo_ios_smoke.a" \
  mojo/examples/ios/swiftui_host/link_swiftui_host.sh
~~~

## 7. Capture the visible proof

After the launch command, capture the booted device directly from CoreSimulator.
For a specific device, set SIMULATOR_UDID as in the previous step; otherwise
the command selects the first available iPhone.

~~~sh
DEVICE_UDID="${SIMULATOR_UDID:-$(xcrun simctl list devices available | \
  sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { \
    s/.*\(([0-9A-F-]{36})\).*/\1/p; q; \
  }')}"
xcrun simctl io "$DEVICE_UDID" screenshot "$IOS_OUT/mojo-ios-simulator.png"
open "$IOS_OUT/mojo-ios-simulator.png"
~~~

The expected screen contains:

~~~text
Hello from Mojo on iOS.
20 + 22 = 42
~~~

This is not a hard-coded SwiftUI-only string: ContentView calls
mojo_hello_utf8 and mojo_add, and those symbols resolve from the Mojo archive.
The complete chain is:

~~~text
Mojo source -> target object -> ar archive -> Swift C ABI calls
-> signed iOS app -> simctl install/launch -> visible Simulator result
~~~

## Skeptic's validation checklist

If you suspect that a result could be documentation or AI slop, validate each
link independently:

1. Record "$MOJO_BIN" --version and keep the exact path in the terminal log.
2. Use a new output directory and rerun the smoke script; do not trust a
   previously generated object.
3. Check that the object is arm64 and that vtool says IOSSIMULATOR, not merely
   that file says Mach-O.
4. Run ar -t and confirm the archive contains the newly generated object.
5. Use nm to verify that _mojo_add and _mojo_hello_utf8 are defined in the
   object and final executable.
6. Read the C consumer source and verify its assertions independently. A
   changed export or wrong buffer contract must make the consumer fail.
7. Inspect the final app with codesign --verify --deep --strict and
   vtool -show-build.
8. Install and launch the exact app bundle with xcrun simctl, then capture the
   screen. The visible 42 and UTF-8 message come from the two exported Mojo
   functions, not from a separate test executable.
9. Repeat from a clean checkout or new output directory and compare the
   compiler version, target triple, symbols, load command, and screenshot.
10. Keep Bazel status separate: a failure to download or analyze a large Bazel
    graph due to disk space is not a passing compiler test and is not evidence
    against the small direct smoke harness.

For an additional independent check:

~~~sh
otool -L "$IOS_OUT/swiftui/MojoIOSSmokeApp"
vtool -show-build "$IOS_OUT/swiftui/MojoIOSSmokeApp"
nm -gU "$IOS_OUT/swiftui/MojoIOSSmokeApp" | \
  grep -E '(_?mojo_add|_?mojo_hello_utf8)$'
~~~

## Troubleshooting

### Bazel asks for a configuration

Use one of the required configurations:

~~~sh
./bazelw build --config=prebuilt-mojo //KGEN:mojo
# or
./bazelw build --config=build-mojo //KGEN:mojo
~~~

The first compiler build can analyze tens of thousands of targets and download
large toolchains. A failure before compilation due to a full Bazel cache is an
environment/storage failure, not evidence that the direct object smoke failed.

### The compiler cannot find std

Set the source stdlib explicitly:

~~~sh
export MOJO_STDLIB_PATH="$PWD/mojo/stdlib"
~~~

Then rerun the smoke script. The runtime-free fixture does not call a stdlib
function, but current drivers can still require an import root.

### CoreSimulator is unavailable

The scripts still complete object, archive, link, symbol, signing, and vtool
checks, then print SKIP for installation/launch. Install an iOS 17-or-newer
runtime in Xcode and retry:

~~~sh
xcrun simctl list runtimes
xcrun simctl list devices available
~~~

### A normal mojo build executable fails to link

That is expected at this stage. The normal executable path still selects the
macOS CompilerRT/linker configuration. Use --emit object plus the native Apple
linker, or --emit static-lib with a compiler containing that implementation.
Do not package a macOS libKGENCompilerRTShared in an iOS app.

## Appendix A — What was needed to support this tutorial

This tutorial depends on a small but real set of compiler, stdlib, and build
changes. They are intentionally separated from the later runtime and framework
work.

### A.1 Target identity and cross-compilation

The compiler now distinguishes:

~~~text
arm64-apple-ios17.0-simulator  -> iOS Simulator, default CPU apple-m1
arm64-apple-ios17.0            -> physical iOS, default CPU apple-a7
arm64-apple-macosx...           -> macOS
~~~

Cross-compilation compares architecture, vendor, OS, and environment. An arm64
Mac compiling arm64 iOS is still cross-compilation. This prevents Mac CPU
features and macOS linker assumptions from leaking into mobile binaries.

### A.2 Object and static-library handoff

The stable first contract is target object emission. ObjectCompiler::emitArchive
historically returns one linked target object buffer, not an ar container. The
--emit static-lib path writes that object to a temporary .o and wraps it with
llvm-ar or ar, without linking host CompilerRT. The native Apple consumer owns
the final SDK, runtime, signing, and app link.

### A.3 Darwin-aware stdlib classification

The stdlib adds CompilationTarget.is_ios(),
CompilationTarget.is_ios_simulator(), and CompilationTarget.is_darwin().
platform_map accepts exact ios values and a shared darwin fallback, with exact
values taking precedence. Shared Darwin errno and ABI constants are reused only
where verified; process spawning, Python, JIT/REPL, and other sandbox-incompatible
APIs remain unavailable with diagnostics.

### A.4 Runtime-free C ABI fixture

The first exported functions avoid allocation, globals requiring runtime
initialization, async work, and dynamic loading. This makes failures
attributable to target code generation, native archiving, or Apple linking
instead of an unimplemented iOS CompilerRT. The later runtime phase must add a
static, app-safe CompilerRT and idempotent runtime initialization.

### A.5 SwiftUI and Apple-library boundary

SwiftUI owns the app lifecycle. Mojo supplies reusable computation through
maintained C headers and a Clang module map. This is compatible with public
Apple libraries through a crawl-walk-run coverage program:

- direct C bindings for Darwin, CoreFoundation, CoreGraphics, Accelerate, and
  signpost facilities;
- Objective-C/Swift adapters exposing stable C functions for Foundation, UIKit,
  SwiftUI models/views, Metal, AVFoundation, Core ML, and other Swift-only APIs;
- registered C callbacks for lifecycle and asynchronous data delivery.

Direct Swift ABI support is deliberately not required for this tutorial.

The current checked-in Accelerate fixture is the first D8 prototype. It still
needs Simulator execution, device execution, benchmark comparisons, and Mojo
runtime integration before Accelerate can be promoted to a supported package
product.

### A.6 What remains before production iOS support

The next implementation gates are a pinned-compiler regression suite, static iOS
CompilerRT, broader stdlib tests, a rules_apple/rules_swift build rule, device
arm64 builds, XCFramework plus Swift Package distribution, on-device Swift
benchmarks, Apple-framework adapters, and precompiled Mojo Metal metallibs.
This tutorial is a validated first rung, not a claim that all later phases are
complete.

## Appendix B — Tracer bullet: follow one value through every format

This appendix follows the value 42 and the 23-byte message through each
representation. It is designed to catch a false “it built” claim at the exact
boundary where it would occur.

### B.1 Mojo source and exported symbols

~~~sh
sed -n '1,120p' mojo/examples/ios/mojo_ios_smoke.mojo
grep -n '@export' mojo/examples/ios/mojo_ios_smoke.mojo
~~~

The source must visibly contain mojo_add and mojo_hello_utf8. Those names are
the symbols expected in every later artifact.

### B.2 Target object bytes

~~~sh
file "$IOS_OUT/smoke/mojo_ios_smoke.o"
vtool -show-build "$IOS_OUT/smoke/mojo_ios_smoke.o"
nm -gU "$IOS_OUT/smoke/mojo_ios_smoke.o"
~~~

The object must be arm64, have platform IOSSIMULATOR and minos 17.0, and define
both symbols. If any one check fails, stop: nothing later can repair the wrong
target object.

### B.3 Archive container

~~~sh
ar -t "$IOS_OUT/smoke/libmojo_ios_smoke.a"
ar -s "$IOS_OUT/smoke/libmojo_ios_smoke.a"
nm -gU "$IOS_OUT/smoke/libmojo_ios_smoke.a"
~~~

The archive must contain the newly generated object and the symbols must remain
visible. This catches the historical bug where a raw object was merely renamed
with an .a suffix.

### B.4 C ABI call site

~~~sh
sed -n '1,120p' mojo/examples/ios/smoke_main.c
sed -n '1,120p' mojo/examples/ios/mojo_ios_smoke.h
~~~

The header types must match the Mojo exports: two signed 64-bit integers and a
caller-owned byte pointer/capacity. The C assertions check both the arithmetic
return value and every byte of the UTF-8 message.

### B.5 Native Simulator executable

~~~sh
file "$IOS_OUT/smoke/mojo_ios_smoke_simulator"
vtool -show-build "$IOS_OUT/smoke/mojo_ios_smoke_simulator"
nm -gU "$IOS_OUT/smoke/mojo_ios_smoke_simulator" | \
  grep -E '(_?mojo_add|_?mojo_hello_utf8)$'
~~~

This proves Apple clang selected an iOS Simulator link, not a macOS binary.
The C app is then copied into the signed app bundle and launched with simctl.

### B.6 Swift module, object, and final app

~~~sh
sed -n '1,160p' mojo/examples/ios/swiftui_host/MojoIOSSmoke.modulemap
sed -n '1,160p' mojo/examples/ios/swiftui_host/MojoIOSSmokeApp.swift
mojo/examples/ios/swiftui_host/compile_swiftui_host.sh
~~~

The Swift object must import the C module. After linking:

~~~sh
file "$IOS_OUT/swiftui/MojoIOSSmokeApp"
vtool -show-build "$IOS_OUT/swiftui/MojoIOSSmokeApp"
nm -gU "$IOS_OUT/swiftui/MojoIOSSmokeApp" | \
  grep -E '(_?mojo_add|_?mojo_hello_utf8)$'
codesign --verify --deep --strict "$IOS_OUT/swiftui/MojoIOSSmoke.app"
~~~

The final executable must be arm64, IOSSIMULATOR, iOS 17.0, signed, and define
the same two Mojo symbols. Only then should it be installed.

### B.7 Device state and pixels

~~~sh
xcrun simctl list devices available
xcrun simctl install "$SIMULATOR_UDID" "$IOS_OUT/swiftui/MojoIOSSmoke.app"
xcrun simctl launch "$SIMULATOR_UDID" com.modular.mojo.ios.smoke
xcrun simctl io "$SIMULATOR_UDID" screenshot "$IOS_OUT/mojo-ios-simulator.png"
~~~

The final screenshot must visibly contain Hello from Mojo on iOS. and
20 + 22 = 42. This is the last tracer-bullet check: SwiftUI executed the C ABI
calls whose definitions can be traced back to the Mojo source, rather than
displaying an unrelated static sample.

### B.8 Direct-C Apple framework tracer bullet

The Accelerate prototype follows a second value through the framework boundary:

~~~text
Swift arrays -> C header -> C adapter -> vDSP_vadd
-> Accelerate.framework-linked arm64 iOS image -> checked output buffer
~~~

Validate each representation independently:

~~~sh
sed -n '1,160p' mojo/examples/ios/accelerate_adapter/mojo_ios_accelerate.h
sed -n '1,160p' mojo/examples/ios/accelerate_adapter/mojo_ios_accelerate.c
MOJO_IOS_ACCELERATE_OUT="$IOS_OUT/accelerate" \
  mojo/examples/ios/accelerate_adapter/run_accelerate_smoke.sh
otool -L "$IOS_OUT/accelerate/accelerate_consumer" | \
  grep -F 'Accelerate.framework/Accelerate'
~~~

The adapter's C contract is POD/buffer/status-code only. This proves a public
Apple framework can enter the package through a controlled adapter tier; it
does not claim that Mojo directly implements Swift or Objective-C ABI types.

## Keeping code and tutorial synchronized

Before sharing a result, run:

~~~sh
git status --short
git diff --check
git show --stat --oneline HEAD
~~~

The tutorial commands refer only to files in this repository. Commit the code
and this document together so a later checkout cannot silently describe a
different harness.
