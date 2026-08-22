# Isolated `rules_apple`/`rules_swift` load trial

This nested Bazel module is a diagnostic, not an iOS application fixture. It
declares the `rules_apple` 4.1.0 and `rules_swift` 3.1.2 versions selected
transitively in the root lockfile, then loads their public `ios_application`
and `swift_library` symbols while querying a simple filegroup. The app probe
lives in a separate `app` package so that this load-only query evaluates no
`ios_application` declaration.

Run it without changing the root `MODULE.bazel` graph:

```sh
mojo/examples/ios/rules_apple_trial/run_isolated_rules_load_trial.sh
```

The successful query shows that those pinned rule repositories can be resolved
and loaded in a direct-dependency scope. It does not instantiate, analyze, or
build `ios_application`; therefore it says nothing about iOS platform and
toolchain setup, application linking, signing, packaging, installation, or
execution.

`run_isolated_ios_application_trial.sh` is the intentionally separate next
probe. Its `app` package declares a minimal UIKit Swift entry point and an `ios_application`
with iOS 17 plus iPhone/iPad families, then queries, analyzes, and attempts to
build it in another isolated output root. It has no Mojo archive dependency.
If SDK/toolchain setup stops analysis or build, the script reports `BLOCKED`
with the command log and exits successfully so the load-only trial remains a
separate, reproducible passing check.

`run_isolated_archive_consumer_control.sh` copies the generated runtime-free
archive/header into a temporary newer-rule workspace, verifies its Simulator
member, and imports it with `cc_import` behind a small C caller in the minimal
iOS app. It is intentionally a copied-artifact compatibility control, not a
root Bazel dependency or a Mojo runtime integration. `rules_apple` may process
and locally sign the resulting IPA as part of bundling; this control uses no
external signing identity and never installs or launches it.

`run_same_graph_provider_control.sh` is a separate disposable top-level module
that depends on the local `modular` module and places
`@modular//mojo/examples/ios:mojo_ios_static_library_smoke` behind a
`cc_library` dependency. It is the bounded CcInfo-provider test: it does not
copy a `bazel-bin` archive. The control stops at analysis, so a passing result
does not claim app build, signing, installation, or execution.

Without overrides this control reports `BLOCKED` before query analysis: the
root module's versionless `bazel_dep(name = "rules_mojo")` is valid only at the
root but cannot be resolved when `modular` is a local module dependency. The
disposable `rules_mojo` and Jammy sysroot overrides make the query pass, while
the additional `rules_mypy` override still leaves `--nobuild` blocked because
the consumed module's development-dependency repository mapping is not visible
to its registered Mojo toolchain. A dependency-owner change to make the root
module consumable is required before this provider seam can be analyzed
together with Apple rules.

The runner additionally attempts a disposable direct `rules_mojo` 0
local-path override using the checkout's resolved source. If that does not
advance Bzlmod resolution, the root's versionless dependency remains the
actionable boundary; the override never modifies the root module or lockfile.

It also derives local paths for the cached Jammy aarch64/x86_64 sysroot modules
and gives them disposable `0.0.0` direct pins. These overrides test module
resolution only and never replace root archive overrides or alter the root
lockfile.

For the same isolated purpose, the runner can expose the cached patched
`rules_mypy` 0.41.0 source as a direct local dependency: the root registers a
Mojo toolchain that loads it while marking the dependency as development-only.
This is not a proposal to change the root dependency visibility or lockfile.

With the Bazel 9.2.0 selected for this checkout, the app target is queryable
but analysis currently stops in `rules_apple` before any SDK action because its
transition declares `//command_line_option:apple_crosstool_top`, which Bazel
reports is not a valid setting. That is a rules/Bazel compatibility blocker,
not evidence of a working application, link, signing, packaging, installation,
or execution path.

An isolated compatibility control changing only the nested module versions to
`rules_apple` 4.5.3 and `rules_swift` 3.5.0 analyzed and built this minimal
Simulator `.ipa` with Bazel 9.2.0, without the legacy transition failure. It
is not checked in as the default because the root graph currently selects the
4.1.0/3.1.2 pair transitively and the newer Swift dependency raises the minimum
protobuf version. A dependency-owner review is required before changing the
root graph; this fixture remains the reproducible legacy blocker.

Run the opt-in compatibility control without changing the root graph:

```sh
mojo/examples/ios/rules_apple_trial/run_isolated_compatibility_control.sh
```

It copies this nested module to a caller-selected temporary output directory,
removes only the copied lockfile, substitutes the two versions in only the
copy, and queries, analyzes, and builds the UIKit Simulator `.ipa`. It reports
`PASS` only after the copied workspace contains that IPA. The script explicitly
records that `rules_swift` 3.5.0 requires `protobuf` 34.0.bcr.1 while the root
currently selects 33.5; it does not establish that a direct-root upgrade is
safe, and it does not link Mojo, sign/install, or execute an app.
