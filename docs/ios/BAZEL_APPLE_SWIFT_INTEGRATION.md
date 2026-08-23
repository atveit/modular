# Bazel Apple/Swift integration

This note records the completed N6 dependency-owner migration, N7 root iOS C++
toolchain, N8 sandboxed same-graph archives, and N9 canonical SwiftUI app.

## Current checkout evidence

The checkout uses Bazel `10.0.0-pre-46c5e789f84c7bf4ba1edb105eefa7bc4ebc841b`.
Its root common module file directly pins `apple_support` to `2.8.1`,
`bazel_skylib` to `1.9.0`, `platforms` to `1.0.0`, and `rules_cc` to `0.2.18`.
It now directly registers `rules_apple` 5.0.0-rc3 as
`@build_bazel_rules_apple` and `rules_swift` 4.0.0-rc5 as
`@build_bazel_rules_swift`. These are explicit release-candidate pins because
the current stable Apple-rule line does not support this Bazel 10 pre-release.
The selected Swift rules require protobuf 34.0.bcr.1, so the root moved from
protobuf 33.5 and removed the old 33-specific development-dependency patch.

The promoted graph resolves this reviewed pair:

| Module | Resolved version | Relevant compatibility evidence |
| --- | --- | --- |
| `rules_apple` | `5.0.0-rc3` | release notes declare compatibility with Bazel rolling releases |
| `rules_swift` | `4.0.0-rc5` | current Bazel-10-compatible release-candidate line |
| `apple_support` | `2.8.1` | selected by the direct root pin and the Swift/Apple graph |
| `protobuf` | `34.0.bcr.1` | minimum declared by the selected Swift rules |

In a detached disposable root at commit `3fb710146d`, this exact graph built
`//KGEN:mojo`, desktop CompilerRT, and both target-correct iOS core archives.
It also passed `//KGEN/unittests:unittests`, the static-library driver test,
the iOS target test, and the stdlib OS lit suite with 16-way execution. A
minimal UIKit `ios_application` loads and queries, then reaches the N7 blocker:
the repo-owned `macos_clang_toolchain` has no iOS branch. This proves the
dependency selection independently of the root toolchain implementation; it
does not yet claim an app build.

An isolated compatibility control upgraded only its nested module to
`rules_apple` 4.5.3 and `rules_swift` 3.5.0. With Bazel 9.2.0 it analyzed and
built the minimal arm64 Simulator UIKit `.ipa`; the legacy
`apple_crosstool_top` transition error did not occur. This proves that the
newer pair can establish an Apple/Swift toolchain in isolation, not that it can
be added to the root graph safely. The checked-in opt-in harness is
`mojo/examples/ios/rules_apple_trial/run_isolated_compatibility_control.sh`.

## Selected root dependency shape

The reviewed root shape is:

```starlark
bazel_dep(
    name = "rules_apple",
    version = "5.0.0-rc3",
    repo_name = "build_bazel_rules_apple",
)
bazel_dep(
    name = "rules_swift",
    version = "4.0.0-rc5",
    repo_name = "build_bazel_rules_swift",
)
```

The dependency trial is complete, and the repository's own C++ toolchain now
registers exact iPhoneOS and iPhoneSimulator arm64 target variants rather than
relying on an ambient Apple-rule fallback.
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
the root protobuf selection at 33.5. A disposable root dependency-owner trial
with protobuf 34.0.bcr.1 showed that the existing protobuf development-dep
patch is not required for module resolution: both a narrowly ported patch and
the no-patch control resolved, and the no-patch control passed the focused
`CompilerRTIOSStatic` build plus 70 KGEN unit tests. This does not approve a
root upgrade; the Apple transition still fails under the repository's Bazel 10
pre-release.

| Isolated control | Bazel 9.2 result | Root-graph implication |
| --- | --- | --- |
| `rules_apple` 2.5.0 / `rules_swift` 1.9.1 | Resolver upgraded to 4.1.0 / 3.1.2 and warned that direct versions were unmet; analysis hit `apple_crosstool_top` again | 2.x is not a viable way to hold the existing graph without stronger overrides |
| `rules_apple` 4.3.3 / `rules_swift` 3.1.2 | Analysis reached Apple rule implementation, then failed because Bazel's `apple` fragment lacks `multi_arch_platform` | Avoids the protobuf 34 requirement but is still Bazel-9 incompatible |
| `rules_apple` 4.5.3 / `rules_swift` 3.5.0 | Query, analysis, and isolated Simulator IPA build pass | Requires `protobuf` 34.0.bcr.1 through rules_swift 3.5.0, so root dependency selection changes |
| Disposable root with protobuf 34.0.bcr.1 and no protobuf patch | Graph, `CompilerRTIOSStatic`, and 70 KGEN tests pass; minimal UIKit app analysis fails because `//command_line_option:apple_platforms` is not a valid transition output under Bazel 10 | The protobuf patch can be reviewed separately; the Apple-rules/Bazel-10 transition remains the active root blocker |
| `rules_apple` 5.0.0-rc3 / `rules_swift` 4.0.0-rc5 | Graph, KGEN/CompilerRT/iOS archives, and focused tests pass; minimal UIKit query reaches the repo-owned `macos_clang_toolchain` and stops because its configurable args have no iOS/default branch | Selected N6 pair; clears the Apple transition blocker and selects apple_support 2.8.1 plus protobuf 34.0.bcr.1 |

That N6 dependency-owner step is now promoted with protobuf 34 and the old
protobuf patch removed. N7 target-aware C++ toolchain support, N8 same-graph
Mojo and serial-core archives, and the N9 canonical app are complete. A local
transition patch or an older Apple-rules pin remains an unsafe substitute.

The 5.0.0-rc3/4.0.0-rc5 pair now reaches a root toolchain with declared,
separate iPhoneOS/iPhoneSimulator SDK inputs; standard device/Simulator
constraints; exact iOS 17 triples; libc++; and iOS compile, link, rpath,
artifact, module-map, and host-tool selections. The permanent smoke runner at
`bazel/internal/cc-toolchain/ios_smoke/run_ios_cc_toolchain_smoke.sh` builds
both raw Mach-O targets and checks action provenance. It does not build an app,
sign, launch, or claim target sanitizer support.

One reusable prerequisite is now checked in independently of that dependency
decision: `bazel/internal/cc-toolchain/apple_sysroot_repository.bzl` resolves
an explicit `macosx`, `iphoneos`, or `iphonesimulator` SDK and accepts an
explicit framework allowlist. The diagnostic
`bazel/internal/cc-toolchain/run_apple_sysroot_repository_diagnostic.sh`
queries both iOS SDK repositories with UIKit and passes. The existing
`macos_sysroot_repository` remains unchanged; the generic rule is now
registered twice and selected by the exact root iOS toolchains.

## Canonical app result and next action

`mojo/examples/ios/bazel_app/run_bazel_ios_app.sh` is the N9 gate. It builds a
root `swift_library`/`ios_application`, runs XCTest against both Mojo C exports,
runs XCUITest against the exact visible greeting and calculation, verifies the
final Mach-O/symbol/signing/link evidence, and installs, launches, and captures
the app on an arm64 Simulator. The app pulls one bounded serial-core archive
through an explicit initializer anchor. That initializer is not
`std.runtime.initialize_runtime()` and does not establish AsyncRT support.

Two compatibility details remain deliberately explicit. The selected
rules_apple release candidate needs a small Bazel-10 linkstamp API patch until
upstream carries the same fallback. Swift application linking uses Xcode's
Apple linker via the repository wrapper so Swift autolink and SDK framework
re-exports resolve correctly. The SDK repository declares the full public
framework tree for that closure. N8 compile/archive actions remain sandboxed
and free of action-time `xcrun`; the final application link is local-Xcode
reproducible, not a remote-hermetic claim.

N10 is implemented by
`mojo/examples/ios/package_consumer/run_clean_package_consumer.sh`. It merges
each Mojo/serial-core platform pair into one static product with exactly one
serial initializer, creates an XCFramework, and copies it into a local Swift
Package. Its clean SwiftUI consumer builds under a sanitized Swift-only
environment with no repository path, installs and launches in Simulator, and
writes a marker only after checking Mojo's exact greeting and sum. Generated
XCFrameworks remain build artifacts rather than tracked binaries.

The next action is N11: isolate and target-compile the smallest
behavior-preserving AsyncRT graph without pulling TCMalloc, desktop profiling,
fault handlers, compiler/JIT facilities, or target-mismatched LLVM/MLIR.

## Historical blockers

The direct repositories are now visible as `@build_bazel_rules_apple` and
`@build_bazel_rules_swift`. The repository-rule mismatch that previously
blocked `bazel mod all_paths` remains repaired by the restored
`bazel/internal/link_hack.bzl` contract.

The isolated trial is now checked in under
`mojo/examples/ios/rules_apple_trial/`. Its load-only query resolves and loads
the two public rule sets, and its minimal `ios_application` query succeeds.
However, `bazel build --nobuild //app:trial_ios_application` is currently
blocked before linking by Bazel 9.2.0/rules_apple 4.1.0:

```text
transition inputs [//command_line_option:apple_crosstool_top]
do not correspond to valid settings
```

That nested diagnostic remains historical evidence. The root now uses the
selected 5.0.0-rc3/4.0.0-rc5 pair, the completed N7 iOS C++ toolchain, N8
sandboxed same-graph Mojo/core-runtime archives, and the passing N9 app.

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

The control is a ladder of disposable overrides. With no overrides, module
resolution stops because the root declares versionless `rules_mojo`; a direct
local override advances past that dependency. Dynamic local overrides for the
two versionless Jammy sysroot modules then make the query pass, but `--nobuild`
stops at the registered Mojo toolchain because the consumed `modular` module
cannot see its `@rules_mypy` load. A top-level `rules_mypy` override does not
repair a dependency's development-dependency repository mapping. These results
are all before Apple SDK/app analysis and require a dependency-owner Bzlmod
change; no root module or lockfile was edited by the control.
