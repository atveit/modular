# ANE and oMLX: experimental reference, not an iOS backend

## Decision

Treat the oMLX ANE work as a **macOS research reference** for partitioning,
measurement, and failure handling. It is not a supported Mojo accelerator and
must not be used in an iOS product, TestFlight build, or App Store submission.
The reference calls undocumented `AppleNeuralEngine.framework` interfaces;
Apple's App Review Guideline 2.5.1 requires apps to use public APIs. The
supported iOS route to the Neural Engine is a public framework such as Core ML
(or a subsequently adopted public Apple ML framework), with Metal as the
explicit programmable accelerator.

This is a product and release boundary, not a claim that private ANE APIs are
available, stable, or supported on any Apple platform.

## What the oMLX experiment actually does

The vendored oMLX experimental note describes a source-build-only path for a
fixed-shape Qwen 3.5/3.6/3.8 *prefill* tile. It creates two INT8 programs,
pinned to physical ANE instances on the measured M3 Ultra, for disjoint output
rows; Metal computes the remaining rows and merges the results. Decode,
attention, recurrent state, normalization, embeddings, and logits remain on
the GPU. The feature is disabled by default.

Important limits from the reference:

- It relies on undocumented APIs and says it may stop working after a macOS
  update.
- It requantizes selected weights to per-output-channel INT8, so it is an
  approximate path rather than bit-exact inference.
- Its documented target is Apple-silicon macOS and, for the dual-engine path,
  an M3 Ultra-specific configuration; it is not evidence for iPhone or iPad.
- Fixed sequence shapes, eager compilation, resident procedure banks,
  device-specific split tuning, and carefully measured GPU/ANE overlap are
  central to the result. They are not incidental implementation details.

The useful design lesson is therefore *hybrid scheduling with explicit evidence*,
not a portable “use ANE directly” abstraction.

## Evidence and current implementation state

The adjacent `dflash2qwen` plan is unusually clear about status. Its desired
end state is 112 real Qwen procedures (64 MLP plus 48 Gated DeltaNet),
IOSurface-backed activation sharing, explicit two-ANE/Metal synchronization,
and a fail-closed backend. It explicitly labels the current Mojo implementation
as a scaffold.

| Area | Verified by source inspection | Not verified / not implemented |
|---|---|---|
| Capability probe | `ane.mojo` locates private Objective-C classes and the bridge checks class/selector presence. | Presence of a class or selector does not establish that a model compiles, loads, or evaluates. |
| Storage plumbing | The bridge creates and locks `IOSurface` objects, obtains base addresses/IDs, and can wrap an IOSurface in a private object. | Metal-buffer interoperability, ownership correctness across all paths, and end-to-end zero-copy activation transfer are unproven. |
| Native calls | The bridge declares Objective-C message sends for private compile/load/evaluate/map/unmap/unload selectors. | No model-descriptor/MIL builder, native error propagation, ticket/completion lifecycle, procedure-bank construction, or successful device execution is wired through Mojo. |
| Procedure registry | It describes logical MLP/GDN partitions and tracks conceptual procedure states. | The plan records simulated compiled/resident state and dispatch methods that can return success without an ANE evaluation; those semantics are not backend readiness. |
| Compute | CPU SIMD/reference loops exist for MLP/GDN-like calculations. | They do not demonstrate ANE work, dual-die concurrency, IOSurface/Metal interop, Qwen parity, or performance. |

Accordingly, no documentation, feature flag, benchmark, or health indicator in
this repository may report ANE execution merely from the probe, IOSurface
allocation, registry counts, or reference-loop output. Readiness requires a
real compile, load, warm-up, evaluation, completion, and numerical result on
the requested hardware.

## Risks

### Platform and App Store risk

The oMLX mechanism uses private classes such as `_ANEClient` and private
selectors. That is incompatible with App Store distribution: Guideline 2.5.1
permits only public APIs. Dynamically looking up the framework or selectors
does not turn them into public APIs, and runtime availability probing is not a
distribution exemption. Do not ship this code in an iOS app bundle and do not
attempt to hide, weak-link, or remotely gate it for review.

Private-interface use is also a reliability risk outside the App Store:
private ABI, selector behavior, compiler acceptance, memory limits, and device
topology may change with an OS update. The oMLX evidence is hardware- and
version-specific, so its throughput, split ratios, and two-instance assumptions
must never be generalized to other Macs, iPhones, or iPads.

### Correctness and operational risk

The reference's INT8 conversion makes the hybrid prefill numerically
approximate. Small numerical differences can alter greedy choices, speculative
decode acceptance, recurrent/KV state, or later tokens. A production-quality
experimental macOS path would need model- and OS-pinned numerical contracts,
state-transaction rollback, forced failure/timeout tests, and raw performance
records. It must fail closed when explicitly selected; a silent switch to
Metal would make performance and correctness evidence misleading.

Fixed-size banks bring further risks: high startup cost, compilation/load
failure, memory-window limits, tail routing, thermal variance, and routing
behavior that varies across devices. A dual-ANE design also cannot presume two
independently addressable engines exist.

## Fit in the Mojo iOS roadmap

Use three separate tracks rather than one overloaded “ANE support” milestone.

1. **Public iOS acceleration (supported path).** Keep Mojo compute on public,
   documented mechanisms: Metal for custom kernels, and Core ML or another
   public Apple framework when a model can be represented and validated there.
   Core ML can use CPU, GPU, and Neural Engine, but device assignment is the
   framework's responsibility; do not promise a particular engine or a
   dual-engine topology. Validate artifacts, signing, launch, correctness,
   latency, memory, energy, and thermal behavior on real devices.

2. **macOS private-ANE research (quarantined path).** If pursued, place it in
   a clearly experimental macOS-only component behind an explicit build and
   runtime opt-in. Keep the private Objective-C++ ABI surface narrow; keep
   policy, scheduling, state, telemetry, and validation in Mojo. Exclude this
   component from iOS targets, app bundles, public SDKs, and App Store builds.
   Its deliverables are reproducible experiments, not platform support.

3. **Portable interfaces (only after evidence).** A future accelerator API may
   express capabilities such as fixed-shape compilation, asynchronous tickets,
   shared buffers, profiling, cancellation, and fail-closed errors. It must not
   expose private ANE names, selector contracts, die IDs, or imply a mapping to
   physical Neural Engine instances. Public iOS and private macOS experiments
   should be independently implemented behind that interface only when both
   have real tests.

The first iOS milestone should therefore be: *a signed device app runs a
public-API inference path and truthfully reports its observable performance*.
It is explicitly **not**: *compile oMLX-style private ANE programs on iOS*.

## Admission criteria for a macOS-only experiment

Before an `ane-metal` result is described as real, require all of the following:

- Capability probe reports the exact OS, hardware, selector set, and unknown
  capabilities without treating them as support.
- A tiny real fixed-shape procedure compiles, loads, warms, evaluates, and
  returns checked results; failures preserve a useful native error.
- The selected model runs every required procedure, with actual per-procedure
  execution counters; partial banks are a startup failure.
- IOSurface/Metal interop has a measured, ownership-checked test with no
  activation payload copy through host arrays.
- ANE, Metal, cancellation, timeout, and rollback behavior pass numerical and
  state-transaction tests. CPU reference code remains a test oracle only.
- Benchmarks record raw runs, configuration, machine/OS version, model hashes,
  compilation/warm time, memory, thermal state, and direct GPU-only comparison.
- The private implementation stays absent from iOS artifacts and every
  distributable App Store build.

## Sources

Repository-local evidence was inspected on 2026-08-22:

- `../dflash2qwen/newplan.md`, especially “Not yet real”, the native-bridge
  requirements, and the assumption register.
- `../dflash2qwen/src/mojo/hw/ane.mojo` and
  `../dflash2qwen/src/mojo/hw/ane_bridge.{h,m}`.
- `../dflash2qwen/thirdparty/benchmarks/omlx-latest/source/docs/experimental/qwen35_ane_prefill.md`.

Public platform and policy references:

- [Apple App Review Guidelines, 2.5.1](https://developer.apple.com/app-store/review/guidelines/)
- [Apple Core ML overview](https://developer.apple.com/documentation/coreml)
- [Apple on public Core ML compute units](https://developer.apple.com/documentation/coreml/mlcomputeunits/cpuandneuralengine)

The following upstream oMLX issue reports are useful corroborating evidence for
the experimental nature of the approach, not platform guarantees:

- [Qwen ANE prefill on M3 Max: fixed-shape and packed-bank caveats](https://github.com/jundot/omlx/issues/2781)
- [Configured ANE path with zero observed ANE operations](https://github.com/jundot/omlx/issues/2839)
- [ANE prefill memory-pressure failure for Qwen 3.8 27B](https://github.com/jundot/omlx/issues/2841)
- [Device-specific ANE regression and capability-gating discussion](https://github.com/jundot/omlx/issues/2779)
