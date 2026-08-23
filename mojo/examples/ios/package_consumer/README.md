# Clean XCFramework and Swift Package consumer

This is the N10 packaging gate. It builds the N8 Mojo and bounded serial-core
archives for device and Simulator, combines exactly one copy of each product
per platform, creates `MojoIOSCore.xcframework`, and copies that artifact into
a local Swift Package. A clean SwiftUI executable target imports only the
package wrapper; its build has no repository path and no Mojo compiler input.

Run from the repository root with a new output directory:

```sh
MOJO_IOS_PACKAGE_OUT=/tmp/mojo-ios-package-$RANDOM \
  mojo/examples/ios/package_consumer/run_clean_package_consumer.sh
```

The runner uses 16 Bazel jobs by default. It validates both XCFramework
variants and symbols, builds the clean package for an arm64 iOS 17 Simulator,
packages and ad-hoc signs the executable, installs and launches it, and requires
the app's `MOJO_IOS_PACKAGE_PASS` file. That marker is written only after the
Swift wrapper receives Mojo's exact greeting and calculation.

This proves Simulator consumption without a Mojo/Modular installation in the
consumer build. Xcode command-line tools are still required to create the
XCFramework, link Swift, sign, and use CoreSimulator. It does not prove a
physical-device launch, AsyncRT, `std.runtime.initialize_runtime()`, remote
execution, or binary redistribution policy.
