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
be added to the root graph safely. The checked-in opt-in harness is
`mojo/examples/ios/rules_apple_trial/run_isolated_compatibility_control.sh`.

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

## Root-adoption compatibility matrix

The current evidence does not support a no-churn root adoption path that keeps
the root protobuf selection at 33.5:

| Isolated control | Bazel 9.2 result | Root-graph implication |
| --- | --- | --- |
| `rules_apple` 2.5.0 / `rules_swift` 1.9.1 | Resolver upgraded to 4.1.0 / 3.1.2 and warned that direct versions were unmet; analysis hit `apple_crosstool_top` again | 2.x is not a viable way to hold the existing graph without stronger overrides |
| `rules_apple` 4.3.3 / `rules_swift` 3.1.2 | Analysis reached Apple rule implementation, then failed because Bazel's `apple` fragment lacks `multi_arch_platform` | Avoids the protobuf 34 requirement but is still Bazel-9 incompatible |
| `rules_apple` 4.5.3 / `rules_swift` 3.5.0 | Query, analysis, and isolated Simulator IPA build pass | Requires `protobuf` 34.0.bcr.1 through rules_swift 3.5.0, so root dependency selection changes |

The practical adoption sequence is therefore a dependency-owner branch that
accepts and reviews the protobuf 34 upgrade, pins the compatible Apple/Swift
pair, regenerates the root lockfile, and validates the full repository's
existing Bazel tests before wiring an iOS target. A transition patch or an
older Apple-rules pin is not a safe substitute for that graph review.

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

## Archive-consumer control

The local runtime-free action now emits
`bazel-bin/mojo/examples/ios/libmojo_ios_static_library_smoke.a` plus its C
header. Its extracted member is arm64 `IOSSIMULATOR` with minimum iOS 17 and
exports `mojo_add`/`mojo_hello_utf8`.

`rules_apple_trial/run_isolated_archive_consumer_control.sh` copies those two
artifacts into a disposable workspace using the 4.5.3/3.5.0 control pair. It
imports the archive through `cc_import`, compiles a C caller that references
`mojo_add`, and makes that C library an `ios_application` dependency. The
control built an `ios_sim_arm64-min17.0` IPA successfully, exercising
Apple-support wrapped Clang/libtool plus Swift and bundle actions.

This proves a narrow artifact-compatibility seam only. It does not make a
`bazel-bin` path a valid root dependency: a root target must consume the
archive/header through a declared provider from `mojo_ios_static_library` (for
example, a `CcInfo`/linking context), within the same configured build graph.
The root also needs dependency-owner approval for direct rules_apple/rules_swift
registration and their Apple SDK/platform toolchains; the 4.5.3/3.5.0 pair
raises protobuf selection beyond the root's current version. The app bundle is
locally processed/signed by the rule, but the control uses no external signing
identity and performs no installation or execution.

## Same-graph provider control

`rules_apple_trial/run_same_graph_provider_control.sh` creates a disposable
top-level module with local-path dependency `modular`, then gives an Apple app
a `cc_library` dependency on the local `mojo_ios_static_library_smoke` target.
Unlike the archive-consumer control, it never copies `bazel-bin` artifacts.

The current control stops at module resolution, before any Apple platform or
SDK analysis: the root `modular` module declares `bazel_dep(name =
"rules_mojo")` without a version. That is accepted for the main module but
cannot be consumed from a dependent module, which reports a bad versionless
`rules_mojo` dependency. The smallest remaining blocker for a true same-graph
Apple consumer is therefore making the root module dependency graph consumable
under Bzlmod (with dependency-owner review); no root module change was made by
the control.
