# Mojo-generated Metal kernels on iOS

## Purpose and current boundary

This appendix turns the roadmap's iOS Metal item into an implementation order.
It is deliberately narrower than general Mojo-on-iOS support: the first deliverable
is an ahead-of-time (AOT) compute library bundled by an iOS host app, not the
MAX runtime running in an app process.

The existing iOS tracer bullet proves CPU object generation and a C/Swift host
path for `arm64-apple-ios17.0` and
`arm64-apple-ios17.0-simulator`; see
[`run_simulator_smoke.sh`](../../mojo/examples/ios/run_simulator_smoke.sh) and
[`link_swiftui_host.sh`](../../mojo/examples/ios/swiftui_host/link_swiftui_host.sh).
It does **not** load or dispatch a Metal pipeline. The iOS Accelerate fixture
already establishes the intended framework seam: a stable C ABI with
caller-owned buffers and integer status codes
([`accelerate_adapter/README.md`](../../mojo/examples/ios/accelerate_adapter/README.md)).

## Evidence: current Metal implementation is macOS-specific

The Metal backend itself is reusable in important ways: it selects the `metal`
stdlib plugin, emits AIR from the ARM64 compilation path, has a Metal-specific
argument encoder, and can expose the underlying `MTLDevice` from a
`DeviceContext`.

However, it is not platform-aware today:

| Location | Current behavior | iOS consequence |
| --- | --- | --- |
| [`std/gpu/host/info.mojo`](../../mojo/stdlib/std/gpu/host/info.mojo) | Every M1--M5 target, including Metal 4 targets, embeds `air64-apple-macosx`. | There is no iOS AIR target constructor or iOS deployment-version selection. |
| [`std/sys/info.mojo`](../../mojo/stdlib/std/sys/info.mojo) | `is_apple_gpu()` is an exact `air64-apple-macosx` match. | An iOS AIR triple would not select Apple-GPU conditionals. |
| [`CompilationOptions.cpp`](../../KGEN/lib/ToolCommon/CompilationOptions/CompilationOptions.cpp) | `isMetalTriple()` accepts any `air64-` prefix, but its comment says iOS/tvOS/watchOS lack suitable compute GPUs. | The predicate is broader than the stated product assumption; the comment and downstream validation must change. |
| [`MAttrs.td`](../../Support/include/Support/MDialect/MAttrs.td) | `isMetal()` accepts `air64`, while the documentation calls Metal “macOS … not embedded devices.” | Target classification cannot be used as evidence that iOS lowering/packaging works. |
| [`std/gpu/host/info.mojo`](../../mojo/stdlib/std/gpu/host/info.mojo) | `MetalM1`--`MetalM5` have fixed M-series names, core counts, and shared limits; Metal 4 entries say “requires macOS 26.” | These presets must not be assigned to A-series chips. |

The existing host-side code is a useful internal reference, not an iOS bridge:
[`_metal.mojo`](../../max/mojo/max/gpu/host/_metal.mojo) retrieves an opaque
`MTLDevice`, and [`_device_context_metal.mojo`](../../max/mojo/max/gpu/host/_device_context_metal.mojo)
serializes kernel arguments and buffer handles through AsyncRT. Neither provides
an app-bundle metallib loader or an iOS-safe ownership/error boundary.

## Pinned compiler evidence

The repository-built driver was produced with:

```sh
./bazelw build --config=build-mojo //KGEN:mojo
```

It successfully emits the runtime-free host object for
`arm64-apple-ios17.0-simulator` and the existing C/Simulator smoke app passes
when invoked with `-I mojo/stdlib`. It does **not** accept either direct
`air64-apple-ios17.0` or `air64-apple-ios17.0-simulator` triples; both fail
before parsing with `unknown target triple`.

The more important control is a GPU source compiled for an iOS host triple
with `--target-accelerator metal:4`. That invocation reaches the GPU sidecar
pipeline but then tries to create the hard-coded `air64-apple-macosx` target and
fails with `target 'air64-apple-macosx' is not supported by this build`. This
pinpoints the current porting seam: the host iOS target is recognized, while
the generated Metal sidecar target is still macOS-specific. It is evidence for
the Stage 1 target factory work below, not evidence of iOS GPU compilation.

## Staged implementation

### Stage 0 — establish the exact Apple toolchain contract

Add a macOS-hosted discovery test that records the accepted AIR triples,
minimum deployment version, AIR version, and resulting metallib metadata for
the installed Xcode. Treat the following as **candidates to validate with the
toolchain**, rather than hard-coded facts:

| Slice | Candidate AIR target | CPU host target |
| --- | --- | --- |
| iPhone/iPad device | `air64-apple-ios17.0` | `arm64-apple-ios17.0` |
| iOS Simulator (compile/link/package coverage only) | `air64-apple-ios17.0-simulator` | `arm64-apple-ios17.0-simulator` |

The test must invoke the same Xcode Metal utilities used in the final rule and
assert that the generated artifact is loadable by the matching SDK. Do not
claim Simulator GPU execution from this test; device execution is the initial
GPU gate. Record the selected AIR/Metal language feature set in a manifest
beside each metallib so an app cannot load a library built for a later OS.

Exit gate: the device candidate produces an inspectable `.air` and `.metallib`
with an explicit iOS deployment floor; an unsupported triple or AIR version
fails before packaging.

### Stage 1 — make AIR targets platform-aware

Introduce an Apple-Metal target factory parameterized by platform and feature
level, then migrate current macOS constructors to call it. The factory should
produce one of `air64-apple-macosx`, `air64-apple-ios<version>`, or the
validated Simulator form, while retaining the existing data layout and
`stdlib_plugin = "metal"` where they are proven target-independent.

Update `is_apple_gpu()` to recognize the Apple AIR family (for example, an
`air64-apple-` predicate plus explicit allowed OSes), and add a separate
`CompilationTarget.is_apple_ios_gpu()` predicate. Keep `is_macos()` checks
where a feature is genuinely macOS-only; do not silently widen those features
to iOS. Amend the two macOS-only comments in KGEN and Support so that they
describe the actual supported target matrix.

Add compile-only coverage for:

- the device and Simulator candidate AIR triples;
- Metal plugin selection and `is_apple_gpu()` for all Apple AIR platforms;
- rejection of an Apple AIR version/platform combination not accepted by the
  toolchain;
- preservation of existing `air64-apple-macosx` output and features.

Exit gate: an iOS AIR module lowers through the same plugin selection path as
macOS, and existing macOS Metal tests remain unchanged.

### Stage 2 — capability model based on `MTLDevice`, not marketing names

Add an iOS bridge query that returns a versioned POD capability record. Its
fields should include the OS/deployment version, `MTLDevice` registry ID/name
for diagnostics, supported Apple GPU family values, thread execution width,
maximum threads per threadgroup, buffer limits, and every optional feature that
can alter code generation. The bridge owns the Objective-C Metal objects; Mojo
and Swift receive only C-compatible data and opaque handles.

Maintain a table from *queried Metal GPU-family capabilities* to conservative
Mojo feature bundles (baseline, enhanced, and future). It must be possible for
an A-series and M-series device to select the same bundle, and for an unknown
device to use baseline rather than being guessed as `apple-mN`. Core counts,
register limits, and shared-memory figures in today's `MetalM1`--`MetalM5`
presets are desktop assumptions and must not become iOS defaults. Metal 4 / AIR
2.8 functionality remains opt-in only after the runtime capability and
deployment floor agree.

Exit gate: unit tests feed mocked capability records for an A-series class, an
M-series iPad class, and an unknown future device; each selection is
deterministic and never relies on the device-name string.

### Stage 3 — AOT metallib build and package rule

Create a `mojo_ios_metallib` build action (initially a script-backed fixture if
Apple Bazel rules are still unavailable) that:

1. compiles a named Mojo kernel module to the validated iOS AIR target;
2. links AIR into a `.metallib` with the iPhoneOS SDK toolchain;
3. emits a JSON manifest containing target triple, deployment floor, AIR/Metal
   feature level, entry-point names, ABI layout version, and SHA-256;
4. copies the metallib and manifest into the app bundle resources; and
5. fails if an app slice and library manifest differ in platform or minimum OS.

The application must load only this bundled, signed resource. There must be no
`newLibraryWithSource`, network download, JIT, or first-launch compilation
path. Package independent variants only when their manifest requirements
differ; select them through Stage 2 capabilities.

Exit gate: a clean app build contains an iOS-targeted metallib and manifest;
tampering with either manifest metadata or the resource hash makes packaging or
loading fail predictably.

### Stage 4 — small host bridge and first kernels

Implement the bridge in Objective-C++ or Swift, with a C header consumable by
Mojo. Keep its first API deliberately boring:

```c
typedef struct MojoMetalContext MojoMetalContext;
int mojo_metal_open(const char *resource_name, MojoMetalContext **out);
int mojo_metal_vector_add(MojoMetalContext *,
                          const float *lhs, const float *rhs, float *out,
                          size_t count);
int mojo_metal_synchronize(MojoMetalContext *);
void mojo_metal_close(MojoMetalContext *);
const char *mojo_metal_last_error(MojoMetalContext *);
```

Internally, `open` obtains `MTLDevice`, validates the manifest against its
capability record, loads the bundled library, resolves a fixed entry point,
and creates an `MTLComputePipelineState`. Dispatch uses command buffers and
caller-owned shared/managed buffers under platform-appropriate synchronization.
The bridge translates Objective-C/Swift failures to stable error codes and
never leaks Foundation or Metal objects across the C/Mojo boundary.

Start with vector addition, then a reduction with explicit numerical tolerances.
Only then reuse higher-level MAX launch machinery, because the current
`MetalEnqueueFunctionArgs` path assumes AsyncRT-managed buffers and function
handles.

Exit gate: an XCTest target on physical iPhone and iPad loads precompiled Mojo
metallibs, runs vector addition and reduction, checks results, and verifies no
runtime source compilation API is called.

### Stage 5 — correctness, performance, and CI

Build a three-level test matrix:

| Level | Where | Required assertions |
| --- | --- | --- |
| compiler/package | macOS CI | AIR triple, metallib manifest, entry points, incompatible slice rejection |
| host integration | iOS Simulator | Swift/C ABI, resource lookup, manifest/error paths; no claim of equivalent GPU hardware |
| device execution | at least one iPhone and one iPad | Metal dispatch, numerical correctness, capability variant selection, teardown, and no source compilation |

For each kernel, compare output against CPU reference first, then equivalent
handwritten MSL and MPS where applicable. Capture GPU traces/counters, wall
time, allocation count, and thermal state; report unsupported counter access
as a skipped metric rather than inventing a performance result. Add regression
tests for deployment-floor rejection and a new unknown GPU family.

Exit gate: CI retains compiler/package coverage on every relevant change and
periodic signed-device runs prove the baseline metallib on both device classes.

## Recommended first change list

1. Add Stage 0 toolchain probe and artifact inspection tests.
2. Refactor the target constructors and predicates in `std/gpu/host/info.mojo`
   and `std/sys/info.mojo`; update the KGEN/Support comments and tests.
3. Land a standalone vector-add metallib fixture plus manifest, without MAX or
   full Mojo runtime dependencies.
4. Add the narrow C host bridge and physical-device XCTest.
5. Generalize only after the fixture has profiling and lifecycle evidence.

This sequence preserves the iOS plan's AOT/no-on-device-compilation requirement
while isolating the currently unproven parts: Apple toolchain triple acceptance,
iOS AIR feature compatibility, and real-device capability behavior.
