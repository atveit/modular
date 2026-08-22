# Direct-C CoreGraphics adapter fixture

The C adapter constructs a `CGRect`, creates/releases a CoreGraphics color
space internally, and exposes only `double width, double height -> double`
through its C ABI. No CoreGraphics or Core Foundation object crosses the
boundary.

Run the default artifact check:

```sh
mojo/examples/ios/coregraphics_adapter/run_coregraphics_smoke.sh
```

It compiles and links the adapter plus a Swift/Clang consumer for both arm64
`iphonesimulator` and `iphoneos`, requiring the adapter's public CoreGraphics
symbol reference, the `CoreGraphics.framework` load command, and matching
Mach-O platform metadata. It neither signs nor runs an app by default.

For opt-in Simulator-only runtime evidence:

```sh
RUN_SIMULATOR=1 mojo/examples/ios/coregraphics_adapter/run_coregraphics_smoke.sh
```

The app must emit `MOJO_COREGRAPHICS_RECT_PASS` after validating the area of a
3×4 rectangle. This proves only the C/Swift CoreGraphics fixture ran in a
Simulator; it is not a Mojo runtime, physical-device, graphics-rendering, or
performance claim.
