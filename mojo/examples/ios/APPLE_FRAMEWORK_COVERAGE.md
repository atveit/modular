# Apple framework coverage inventory

This is the working inventory for the Phase 6 goal: make the public iOS and
iPadOS SDK useful from Mojo. “Available in Mojo” means that a documented public
API can be called through a stable boundary; it does not mean that Mojo
reimplements the Swift ABI or declares arbitrary Swift protocols and opaque
result types.

The inventory is intentionally versioned with the Xcode SDK used by a build.
Every promoted API needs its framework, minimum OS, availability annotations,
nullability, ownership convention, callback convention, and error conversion
recorded here or in the generated API report. Private Apple APIs are never a
supported tier.

## Coverage tiers

| Tier | Boundary | Appropriate APIs | First acceptance test |
| --- | --- | --- | --- |
| Direct C | Mojo C/Clang bindings | Darwin, CoreFoundation, CoreGraphics, Accelerate/BLAS/vDSP/BNNS, `os` C/signpost facilities | Compile and link a tiny function against the iOS SDK; validate sizes, symbols, and availability on Simulator and device |
| Adapter | Small Objective-C or Swift module exposing C functions | Foundation objects, UIKit, SwiftUI models/views, Metal, AVFoundation, Core ML, and other non-C frameworks | Swift adapter owns framework objects; Mojo sees POD values, opaque handles, callbacks, and integer error codes |
| Callback | Registered C ABI callbacks | Lifecycle, asynchronous completion, delegate-style events, data delivery | Exercise success, cancellation, error, and teardown paths with no callback after destroy |
| Compile-only | Headers/imports accepted, runtime path incomplete | Early binding work and APIs requiring a later runtime or entitlement | Cross-compile and inspect symbols without claiming device behavior |
| Unavailable | No safe public boundary yet | Private APIs, on-device JIT/compiler loading, unsupported sandbox operations | Emit a clear compile-time or build-time diagnostic |

## Crawl: first public framework wave

The initial crawl is deliberately small and testable. Status is “planned” until
there is a checked-in binding, an iOS 17 compile test, and a runtime test at the
appropriate tier.

| Framework | Primary tier | Status | Smallest useful first surface |
| --- | --- | --- | --- |
| Darwin / libc | Direct C | In progress | errno, file descriptors, clocks, memory and thread primitives that are available in the app sandbox |
| CoreFoundation | Direct C | Simulator runtime marker passes | `corefoundation_adapter/run_corefoundation_smoke.sh`: CFString create/inspect/release through a scalar C ABI; device execution remains a separate gate |
| CoreGraphics | Direct C | Planned | scalar geometry and image metadata; no ownership crossing without an explicit rule |
| Accelerate, vDSP, BLAS, BNNS | Direct C | Simulator runtime marker passes | `accelerate_adapter/run_accelerate_smoke.sh`: vDSP vector add through a stable C header; device correctness and benchmarks remain |
| `os`, signposts | Direct C / callback | Planned | signposted regions and structured diagnostic output |
| Foundation | Adapter | Planned | data, URL/path, date, and error adapters with explicit ownership |
| UIKit | Adapter | Planned | screen/device metadata and a host-owned view/controller seam |
| SwiftUI | Adapter | Compile-only host exists | SwiftUI owns `App`/`View`; Mojo supplies computation and model data through C |
| Metal | Adapter + precompiled kernels | Planned | device discovery, buffer/pipeline handles, dispatch and error conversion |
| AVFoundation | Adapter | Planned | one bounded capture or media-buffer path with explicit callback lifetime |
| Core ML | Adapter | Compile/link fixture for `iphoneos` + `iphonesimulator` | `coreml_adapter/run_coreml_link_smoke.sh`: Objective-C C-ABI adapter and Swift consumer; model loading/runtime remain untested |

“All iOS libraries” is therefore a coverage process: add each public framework
to this inventory, choose the safest tier, and attach tests. Frameworks with
Swift-only APIs start with a Swift adapter; they do not block the C ABI and
static-library roadmap.

## Walk: binding conventions

Before generating bindings, handwritten examples must establish these rules:

1. Use scalar/POD arguments, caller-owned buffers, opaque handles, and explicit
   `destroy` functions. Never expose Mojo-owned strings, collections,
   exceptions, or native layout directly to Swift.
2. Keep Swift/Objective-C object ownership on the adapter side. Every retained
   handle has one documented release operation, and callbacks are unregistered
   before the handle is destroyed.
3. Carry availability and nullability into the C header. A missing optional
   framework feature returns an integer error rather than invoking undefined
   behavior.
4. Keep SwiftUI and application lifecycle code in Swift. The Mojo-facing API is
   a computation/model boundary, not a declaration of `View`, `App`, generics,
   protocols, or opaque result types.
5. Build the same headers against `iphoneos` and `iphonesimulator` SDKs and
   run ABI checks for sizes, alignment, offsets, symbols, and deployment target.

## Run and promotion gates

The current source-only SwiftUI probe is:

```sh
mojo/examples/ios/swiftui_host/compile_swiftui_host.sh
```

Promotion of a framework from “planned” or “compile-only” requires:

- a pinned compiler build for `arm64-apple-ios17.0-simulator` and
  `arm64-apple-ios17.0`;
- a Simulator correctness test and, where the API is device-sensitive, a
  development-signed device test;
- a clean consumer test through the eventual XCFramework/Swift Package;
- documented entitlements, sandbox restrictions, and availability behavior;
- a benchmark or profiling note for performance-sensitive paths.

The inventory should be reviewed whenever the Xcode SDK or minimum deployment
target changes. It is an acceptance artifact, not a promise that every Apple
framework can be made safe or useful through direct Mojo declarations.
