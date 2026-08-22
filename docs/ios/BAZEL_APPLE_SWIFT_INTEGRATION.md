# Bazel Apple/Swift integration reconnaissance

This note records a read-only D3 investigation. It is not a request to modify
`MODULE.bazel`, and no `ios_application` target is enabled by this document.

## Current checkout evidence

The checkout uses Bazel `10.0.0-pre-46c5e789f84c7bf4ba1edb105eefa7bc4ebc841b`.
Its root common module file directly pins `apple_support` to `2.3.0`,
`bazel_skylib` to `1.9.0`, `platforms` to `1.0.0`, and `rules_cc` to `0.2.18`.
Neither `rules_apple` nor `rules_swift` is a direct dependency, so
`@rules_apple` and `@build_bazel_rules_swift` are not visible from the main
repository. The existing SwiftUI fixture must therefore remain source-only.

`bazel mod graph` and the checked-in module lock resolve a mutually compatible
transitive pair already present through `grpc`/`protobuf`:

| Module | Resolved version | Relevant compatibility evidence |
| --- | --- | --- |
| `rules_apple` | `4.1.0` | declares Bazel `>=7.0.0`; selects `apple_support` 2.3.0 in this graph |
| `rules_swift` | `3.1.2` | declares Bazel `>=7.0.0`; is the version selected by the graph |
| `apple_support` | `2.3.0` | already direct and selected |

This makes `rules_apple` 4.1.0 plus `rules_swift` 3.1.2 the bounded
reproduction pair for the existing failure; it is not a compatible app-target
recommendation for the checkout's Bazel 9.2.0/10.0-pre toolchain.

An isolated compatibility control upgraded only its nested module to
`rules_apple` 4.5.3 and `rules_swift` 3.5.0. With Bazel 9.2.0 it analyzed and
built the minimal arm64 Simulator UIKit `.ipa`; the legacy
`apple_crosstool_top` transition error did not occur. This proves that the
newer pair can establish an Apple/Swift toolchain in isolation, not that it can
be added to the root graph safely.

## Minimal isolated-trial shape

An owner-approved branch should first add direct module visibility in a small,
reviewable change, regenerate `MODULE.bazel.lock`, and run the existing
SwiftUI source fixture through the resulting toolchains. The candidate shape
is:

```starlark
# Candidate only; do not paste without dependency-owner review.
bazel_dep(name = "rules_apple", version = "4.5.3")
bazel_dep(
    name = "rules_swift",
    version = "3.5.0",
    repo_name = "build_bazel_rules_swift",
)
```

The rule modules provide their own Apple C++ setup and Swift local-toolchain
extensions. Before adding an app target, verify that those extensions resolve
against the selected Xcode and that they do not replace or conflict with the
repository's registered Mojo/C++ toolchains. The newer Swift module also raises
the graph's minimum `protobuf` version (3.5.0 declares `34.0.bcr.1`, while the
root currently selects 33.5), so it requires a full dependency-owner review.
The first target should be
Simulator-only, use the existing `Info.plist`, and have this dependency shape:

```text
ios_application (minimum OS 17.0, Simulator arm64)
  -> swift_library (MojoIOSSmokeApp.swift)
       -> cc_library/provider for the runtime-free Mojo archive + header/module map
```

Use `--ios_multi_cpus=arm64` (or the equivalent registered Simulator platform)
only after checking the generated action's SDK, triple, and Mach-O metadata.
Do not bundle the current host-built `CompilerRTIOSStatic` archive: its members
are macOS Mach-O, not iOS slices.

## Present blockers and next action

The direct-repository queries fail because the aliases are absent, despite the
transitive modules being resolved. The repository-rule mismatch that previously
blocked `bazel mod all_paths` has been repaired by restoring
`bazel/internal/link_hack.bzl` from the historical contract expected by
`MODULE.bazel`; `bazel mod all_paths rules_apple` and `rules_swift` now
complete. This fixes module evaluation only; it does not make the Apple rule
repositories visible from the main repository.

The isolated trial is now checked in under
`mojo/examples/ios/rules_apple_trial/`. Its load-only query resolves and loads
the two public rule sets, and its minimal `ios_application` query succeeds.
However, `bazel build --nobuild //app:trial_ios_application` is currently
blocked before linking by Bazel 9.2.0/rules_apple 4.1.0:

```text
transition inputs [//command_line_option:apple_crosstool_top]
do not correspond to valid settings
```

The diagnostic exits successfully after saving the full log so it is a
reproducible blocker report, not a passing app build. A separate temporary
4.5.3/3.5.0 control succeeds, but is not evidence that the root can safely
adopt it. Next action: have the Bazel dependency/toolchain owner review module
version selection and toolchain registration in a dedicated branch before
making the newer pair direct root dependencies, then build a compile-only
Simulator Swift library before declaring an application or claiming
XCTest/UI/runtime support.
