# Core ML adapter link fixture

This is an **artifact-only** iOS framework-link fixture. An Objective-C
implementation imports the public `<CoreML/CoreML.h>` header and exposes the
plain C function `mojo_coreml_framework_anchor`; a Swift target imports that
C declaration through a Clang module map. The harness cross-compiles and links
both iOS target families and inspects the resulting Mach-O files.

It proves only that this Swift/Objective-C/C-ABI adapter shape can compile and
link `CoreML.framework` for the iPhone OS and iPhone Simulator SDKs. It does
**not** package or load an `.mlmodel`/`.mlpackage`, call the anchor, execute a
prediction, request a compute unit, demonstrate ANE use, or make a device
runtime/performance claim.

## Run

From the repository root, with Xcode selected:

```sh
mojo/examples/ios/coreml_adapter/run_coreml_link_smoke.sh
```

The script emits independent artifacts beneath
`/tmp/mojo-ios-coreml-link-probe/iphonesimulator` and
`/tmp/mojo-ios-coreml-link-probe/iphoneos`. Set `MOJO_IOS_COREML_OUT` to keep
them elsewhere, and set `MOJO_IOS_COREML_MIN_OS` (default `17.0`) to alter the
minimum iOS version consistently for both targets.

Success requires all of the following for each SDK:

1. Objective-C adapter object compilation with the matching SDK and target.
2. Swift/Clang C-ABI consumer linking with `-framework CoreML`.
3. An arm64 Mach-O executable with matching platform metadata.
4. The exported `mojo_coreml_framework_anchor` symbol and a
   `CoreML.framework/CoreML` load command.

The fixture is source-only because this checkout does not register
`rules_apple`/`rules_swift`. It is an adoption seam for a future app target,
not a substitute for model-conversion or physical-device validation. See
[`docs/ios/ACCELERATORS_COREML_ACCELERATE.md`](../../../../docs/ios/ACCELERATORS_COREML_ACCELERATE.md)
for supported Core ML scheduling, packaging, and runtime validation guidance.
