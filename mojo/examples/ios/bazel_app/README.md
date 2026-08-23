# Canonical Bazel iOS tracer

This is the N9 application gate. SwiftUI owns the app lifecycle and imports the
generated Mojo C header as a Clang module. The app calls `mojo_hello_utf8` and
`mojo_add` from the same configured Bazel graph.

Run the complete Simulator gate from the repository root:

```sh
mojo/examples/ios/bazel_app/run_bazel_ios_app.sh
```

The runner uses 16 Bazel jobs by default, builds the arm64 iOS 17 Simulator
IPA, runs XCTest against both Mojo exports, and runs XCUITest against the exact
visible greeting and calculation. It then verifies Mach-O/symbol/signing/link
provenance, installs and launches the app, and writes a screenshot under
`bazel-out/ios-bazel-app/`.

Override the local destination when needed:

```sh
MOJO_IOS_SIMULATOR_DEVICE='iPad Pro 13-inch (M5)' \
MOJO_IOS_SIMULATOR_VERSION=26.0 \
mojo/examples/ios/bazel_app/run_bazel_ios_app.sh
```

This is Mojo C-ABI evidence with the bounded serial iOS core linked exactly
once. The app explicitly calls `KGEN_CompilerRT_Initialize`, but that serial
initializer is not `std.runtime.initialize_runtime()` and does not initialize
AsyncRT. The gate does not claim physical-device execution, a full Mojo
runtime, or direct Swift ABI interoperability. The final app link uses Xcode's
Apple linker through the repository wrapper; unlike the N8 archive actions,
that link is local-Xcode reproducible rather than remote-hermetic.
