# Runtime-backed Mojo String Simulator probe

This fixture is intentionally unlike the runtime-free iOS smoke test: its
export constructs a `String` through concatenation and integer formatting, so
it requires a static Mojo runtime that is compatible with the arm64 iOS
Simulator. The C consumer asserts the resulting byte count and emits a marker
only after the call returns.

Run it with an explicitly supplied runtime archive:

```sh
MOJO_IOS_RUNTIME_ARCHIVE=/absolute/path/to/libmojo_runtime_ios_simulator.a \
mojo/examples/ios/runtime_string_probe/run_runtime_string_simulator.sh
```

The harness accepts a successful result only after it links the archive,
installs the signed app, launches it with `simctl`, and observes
`MOJO_RUNTIME_STRING_PROBE_PASS`. It is Simulator-only and makes no device,
Apple-framework, Core ML, or ANE claim.

Without `MOJO_IOS_RUNTIME_ARCHIVE`, it intentionally exits zero with an
explicit `SKIP`. The pinned Mojo 1.0.0b1 distribution currently has no
discovered static iOS runtime archive, so it cannot validate the runtime path.
Object emission, a runtime-free link, or a missing archive must never be
reported as a runtime pass.
