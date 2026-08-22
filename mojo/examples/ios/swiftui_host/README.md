# SwiftUI host adoption fixture

`MojoIOSSmokeApp.swift` is the smallest planned SwiftUI integration seam. The
SwiftUI `App` and `View` types own the lifecycle and call the runtime-free Mojo
C ABI through the handwritten header in the parent directory. The view should
display `Hello from Mojo on iOS.` and `20 + 22 = 42` once linked with the Mojo
archive.

This checkout does not currently register `rules_apple` or `rules_swift`, so
the fixture is source-only and is exported by
`//mojo/examples/ios/swiftui_host:swiftui_host_fixture`. It intentionally does
not declare an `ios_application` target or vendor replacement rule definitions.
When those rules are registered, use this source and module map with:

```starlark
ios_application(
    name = "mojo_ios_smoke_app",
    families = ["iphone", "ipad"],
    minimum_os_version = "17.0",
    ...
)
```

The first rule-backed version should depend on a `mojo_ios_static_library`
target that returns the archive, C header/module map, and target-link metadata.
The runtime-free archive produced by `../run_simulator_smoke.sh` is sufficient
for ABI/link discovery, but it does not yet provide the runtime-backed
SwiftUI/XCTest acceptance test promised by Phase 1.

## Bazel rule availability diagnostic

`run_bazel_swiftui_diagnostic.sh` queries the exported source fixture and the
two required external rule repositories without adding dependencies or declaring
an application target:

```sh
mojo/examples/ios/swiftui_host/run_bazel_swiftui_diagnostic.sh
```

It reports `SKIP` when `@rules_apple` or `@build_bazel_rules_swift` is not
visible, which is the current expected state. With `RUN_XCODE_LINK=1`, it also
invokes the existing runtime-free Simulator archive smoke and SwiftUI Xcode
link seam. That optional path verifies only an arm64 Simulator executable,
Mojo C-ABI symbols, and an ad-hoc app bundle; it does not use an
`ios_application` action, XCTest, UI test, installation, or launch.

## Compile-only SwiftUI probe

On a Mac with Xcode installed, compile the Swift source for the arm64 iOS
Simulator without linking an application:

```sh
mojo/examples/ios/swiftui_host/compile_swiftui_host.sh
```

The script uses an explicit Clang module-map flag and a writable module cache.
It emits an arm64 Simulator Swift object and module, but does not link or sign
an application. The Mojo archive and `rules_apple`/Xcode application link
action remain intentionally deferred until the repository has an Apple Swift
toolchain integration.

To test the real link seam after building the runtime-free archive:

```sh
MOJO_IOS_SMOKE_OUT=/tmp/mojo-ios-smoke \
  mojo/examples/ios/run_simulator_smoke.sh
MOJO_IOS_ARCHIVE=/tmp/mojo-ios-smoke/libmojo_ios_smoke.a \
  mojo/examples/ios/swiftui_host/link_swiftui_host.sh
```

Add `RUN_SIMULATOR=1` to the link command to boot an available iPhone
Simulator, install the signed app, and request its launch. Set
`SIMULATOR_UDID` when a specific device is required.

The link probe emits a SwiftUI arm64 iOS executable for the selected
`MOJO_IOS_SWIFT_TRIPLE` (Simulator by default, or `arm64-apple-ios17.0` for a
device), verifies the `IOSSIMULATOR`/`IOS` load command and Mojo symbols, and
packages a minimal ad-hoc signed `.app`. By default it stops at packaging; with
`RUN_SIMULATOR=1` it also installs and launches the app in an available iPhone
Simulator. The direct Simulator path has been verified to show the Mojo-returned
greeting and arithmetic; this is not a physical-device claim and it does not
provide XCTest coverage. In environments where Swift emits a benign
`using sysroot for 'MacOSX' but targeting 'iPhone'` warning, `vtool` remains the
source of truth for the final platform metadata. The controlled probe showed
that `swiftc -sdk <iphonesimulator SDK>` alone still emitted that warning; the
link script therefore sets `SDKROOT` to the same SDK explicitly. This removed
the warning while preserving the `IOSSIMULATOR` load command.
