# Direct-C CoreFoundation adapter fixture

This fixture exposes one ownership-safe C ABI operation:
`mojo_corefoundation_utf16_length`. It creates a `CFString` from a caller-owned
UTF-8 buffer, obtains its UTF-16 code-unit count, releases the `CFString`
before returning, and writes a scalar result. No CoreFoundation ownership or
opaque handle crosses into Swift or Mojo.

Run the default arm64 device and Simulator compile/link checks:

```sh
mojo/examples/ios/corefoundation_adapter/run_corefoundation_smoke.sh
```

The harness compiles the C adapter with each matching Xcode SDK, links the
Swift C-ABI consumer with `CoreFoundation.framework`, and checks the adapter
symbol plus `IOS`/`IOSSIMULATOR` Mach-O metadata. It does not use the Mojo
runtime, sign a device app, install anything, or claim physical-device support.

To opt into only the Simulator CFString runtime marker:

```sh
RUN_SIMULATOR=1 mojo/examples/ios/corefoundation_adapter/run_corefoundation_smoke.sh
```

That path packages and ad-hoc signs a minimal Simulator app, then requires
`MOJO_COREFOUNDATION_CFSTRING_PASS` after the Swift consumer verifies the C ABI
result. It is CoreFoundation-only runtime evidence, not a Mojo runtime or UI
test. The fixture remains source-only until Apple/Swift Bazel rules are
registered in this checkout.
