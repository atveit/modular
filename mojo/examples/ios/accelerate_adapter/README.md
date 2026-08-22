# Direct-C Accelerate adapter fixture

This is the first non-SwiftUI Apple framework seam. The C adapter calls
Apple's public `vDSP_vadd` API from `Accelerate.framework`, while Swift sees
only the stable `mojo_accelerate_vector_add` C declaration through a Clang
module map. The boundary uses caller-owned buffers, scalar counts, and an
integer status code; it transfers no framework or Mojo-owned objects.

## Run the compile/link probe

From the repository root:

```sh
mojo/examples/ios/accelerate_adapter/run_accelerate_smoke.sh
```

The harness uses `xcrun` to compile the C adapter against the
`iphonesimulator` SDK, links the Swift consumer with `Accelerate.framework`,
and verifies arm64 Mach-O platform metadata, the exported adapter symbol, and
the framework load command. Set `MOJO_IOS_ACCELERATE_OUT` to retain outputs
elsewhere. This is compile/link-only: CoreSimulator launch and physical-device
execution are not claimed here.

The fixture is intentionally source-only rather than an `ios_application`
target. `rules_apple` and `rules_swift` are not registered in this checkout;
the same header/module map and adapter object can become a `cc_library` plus a
Swift target when the Apple Bazel toolchain is added.

## Framework inventory status

| Framework/API | Boundary | Status in this fixture | Next gate |
| --- | --- | --- | --- |
| Accelerate/vDSP | Direct C adapter | Compile/link prototype passes on iOS Simulator | Runtime correctness on Simulator, then device; benchmark against Mojo and Swift |
| CoreFoundation | Direct C | Planned | Handwritten ownership-safe CFString/CFData probe |
| `os` signposts | Direct C/callback | Planned | Signpost-backed device benchmark integration |
| SwiftUI | Swift host + C ABI | Compile/link host exists | SwiftUI UI test once rules/app/runtime integration exists |
| Metal | Adapter + precompiled kernels | Planned | iOS AIR/metallib and device dispatch probe |

This does not imply direct Swift ABI support. Swift-only framework APIs remain
adapter-owned, and Mojo continues to cross the boundary through C-compatible
POD values, buffers, opaque handles, callbacks, and integer errors.
