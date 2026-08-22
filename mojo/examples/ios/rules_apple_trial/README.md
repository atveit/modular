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

With the Bazel 9.2.0 selected for this checkout, the app target is queryable
but analysis currently stops in `rules_apple` before any SDK action because its
transition declares `//command_line_option:apple_crosstool_top`, which Bazel
reports is not a valid setting. That is a rules/Bazel compatibility blocker,
not evidence of a working application, link, signing, packaging, installation,
or execution path.
