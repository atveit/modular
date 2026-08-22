# Objective-C Foundation adapter fixture

This fixture demonstrates the object-framework boundary planned for Mojo iOS
hosts. `mojo_foundation_url_is_file_url` accepts only a caller-owned UTF-8
buffer and a scalar output pointer. The Objective-C adapter creates an
adapter-owned `NSString`, creates an adapter-owned `NSURL`, reads `isFileURL`,
and lets ARC/autorelease cleanup occur before returning. No Foundation object
or retain/release responsibility crosses the C ABI.

Run the default arm64 device and Simulator compile/link checks:

```sh
mojo/examples/ios/foundation_adapter/run_foundation_smoke.sh
```

It uses the corresponding Xcode SDK to compile the Objective-C adapter, links
the Swift C-ABI consumer with `Foundation.framework`, and verifies the adapter
symbol plus `IOS`/`IOSSIMULATOR` metadata. This does not use Mojo runtime,
sign a device app, install anything, or claim physical-device support.

For the opt-in, Simulator-only URL marker:

```sh
RUN_SIMULATOR=1 mojo/examples/ios/foundation_adapter/run_foundation_smoke.sh
```

That path ad-hoc signs and launches a minimal Simulator app and requires
`MOJO_FOUNDATION_URL_PASS`. It demonstrates only the `NSString`/`NSURL`
adapter operation, not general Foundation coverage, UI behavior, or a Mojo
runtime path.
