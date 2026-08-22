# Objective-C UIKit adapter fixture

This fixture demonstrates a minimal UIKit object-framework boundary for an iOS
host. `mojo_uikit_main_screen_scale` takes no object inputs and returns only a
scalar `double`. The Objective-C adapter reads `UIScreen.mainScreen.scale`
inside an autorelease pool; no UIKit object, ownership rule, or Swift/Objective-C
reference crosses the C ABI.

Run the default arm64 device and Simulator compile/link checks:

```sh
mojo/examples/ios/uikit_adapter/run_uikit_smoke.sh
```

The harness compiles the Objective-C adapter against each Xcode SDK, links the
Swift C-ABI consumer with `UIKit.framework`, and verifies the adapter symbol,
the `UIScreen` class reference, and `IOS`/`IOSSIMULATOR` Mach-O metadata. It
does not use the Mojo runtime, sign a device app, install anything, or claim
physical-device support.

For the opt-in, Simulator-only scalar marker:

```sh
RUN_SIMULATOR=1 mojo/examples/ios/uikit_adapter/run_uikit_smoke.sh
```

That path ad-hoc signs and launches a minimal Simulator app and requires
`MOJO_UIKIT_SCREEN_SCALE_PASS`. It establishes only that this UIKit scalar
adapter and Swift caller run on the selected Simulator. It does not test the
application lifecycle, views/controllers, rendering, general UIKit coverage,
Mojo runtime support, or physical-device behavior.
