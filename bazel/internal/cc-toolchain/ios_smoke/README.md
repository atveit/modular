# iOS C++ toolchain smoke target

`ios_cc_toolchain_smoke` is a runtime-free C++ binary used to validate the
root Bazel C++ toolchain against Apple's arm64 device and Simulator platforms:

```sh
bazel/internal/cc-toolchain/ios_smoke/run_ios_cc_toolchain_smoke.sh
```

The runner builds both variants with 16 jobs by default. Set
`MOJO_IOS_BAZEL_JOBS` to change that local limit. It checks each final Mach-O
platform and minimum OS, then inspects the compile action for the exact triple
and SDK repository and rejects an action-time `xcrun` dependency.

The target proves that Bazel selects a target-correct SDK sysroot, target
triple, host execution tools, and Mach-O platform. It is not an app bundle,
does not sign or launch, and does not validate the Mojo runtime.
