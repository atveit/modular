# Apple acceleration from Mojo on iOS: Core ML and Accelerate

**Status:** integration guidance, not a claim that Mojo currently imports Apple
framework modules directly.  Use a small Swift/Objective-C/C adapter at the
iOS app boundary and keep the Mojo-facing ABI C-compatible.

## Decision

There are two supported Apple acceleration routes for an iOS app containing
Mojo code:

| Workload | Apple API to own in the app adapter | Hardware contract |
| --- | --- | --- |
| A trained, supported ML graph | Core ML (`MLModel`) | The OS/Core ML scheduler chooses among CPU, GPU, and, where usable and available, the Neural Engine. |
| Numerics, DSP, or a small custom CPU-side network | Accelerate: vDSP/vForce, BLAS/LAPACK, or BNNS | CPU vector-processing path; this is not an ANE API. |

Core ML is the route for a model intended to benefit from the Apple Neural
Engine (ANE). Accelerate is the route for high-performance CPU vector,
linear-algebra, signal-processing, and BNNS work. Apple describes Core ML as
using CPU, GPU, and Neural Engine, while Accelerate provides CPU
vector-processing computation. [Core ML overview](https://developer.apple.com/documentation/CoreML)
and [Accelerate overview](https://developer.apple.com/documentation/accelerate)
are the authoritative API entry points.

## ANE availability is scheduling permission, not direct control

Do **not** describe `MLComputeUnits` as a way to command, reserve, profile, or
write kernels for the ANE. It is an *allow-list* for Core ML's scheduling:

- `.all` permits Core ML to use all eligible units, including the Neural
  Engine when it is available and supports the relevant work.
- `.cpuAndNeuralEngine` permits CPU and Neural Engine but excludes GPU.
- `.cpuAndGPU` explicitly excludes the Neural Engine; `.cpuOnly` excludes GPU
  and ANE.

The actual placement can vary with device, OS release, model representation,
operators, shapes, precision, thermal/power state, and concurrent work. The
appropriate production default is normally `.all`; use the restrictive values
to establish fallbacks or isolate/debug a performance question, not as a
device-selection guarantee. See Apple's [MLComputeUnits
documentation](https://developer.apple.com/documentation/coreml/mlcomputeunits)
and [MLModelConfiguration.computeUnits](https://developer.apple.com/documentation/coreml/mlmodelconfiguration/computeunits).

Core ML may execute a graph across devices. Consequently, an observation that
a prediction succeeded with `.all` does not prove every operation ran on ANE,
and failure under `.cpuAndNeuralEngine` is not evidence that an ANE is absent.
There is no supported public iOS API for submitting arbitrary Mojo kernels
directly to the ANE; use Core ML for supported model graphs. For bespoke GPU
kernels, evaluate Metal separately rather than relabeling it as the Core
ML/Accelerate route.

## Core ML model pipeline

1. Start with a reference model and fixed representative inputs. Convert it
   with Python `coremltools`' Unified Conversion API, pinning both the minimum
   iOS deployment target and input/output names, shapes, dtypes, and image
   preprocessing. For PyTorch sources, explicitly provide input shapes.
2. Prefer an ML Program (`.mlpackage`) when the app's minimum target permits
   it (iOS 15+); this is Core ML Tools' recommended current representation.
   An ML Program package keeps weights separate from program architecture. Use
   the older neural-network representation only when deployment compatibility
   requires it.
3. Add the `.mlpackage` or `.mlmodel` to the Xcode project. Xcode compiles a
   bundled model into the optimized resource used on device and can generate a
   typed Swift wrapper. For downloaded source models, compile off the main
   thread with the asynchronous `MLModel` compilation API, then load the
   resulting `.mlmodelc`.
4. Configure and load the model in Swift/Objective-C, pass correctly typed
   `MLMultiArray` or `CVPixelBuffer` features, perform prediction, and copy or
   otherwise marshal only the result the Mojo caller needs.

References: [conversion formats](https://apple.github.io/coremltools/docs-guides/source/target-conversion-formats.html),
[ML Program packaging](https://apple.github.io/coremltools/docs-guides/source/convert-to-ml-program.html),
[Core ML input/output types](https://apple.github.io/coremltools/docs-guides/source/model-input-and-output-types.html),
[Xcode model integration](https://developer.apple.com/documentation/CoreML/integrating-a-core-ml-model-into-your-app),
and [runtime compilation/loading](https://developer.apple.com/documentation/coreml/mlmodel).

### Conversion example (build-host Python)

```python
import coremltools as ct

converted = ct.convert(
    source_model,
    inputs=[ct.TensorType(name="input", shape=(1, 3, 224, 224))],
    minimum_deployment_target=ct.target.iOS15,
    convert_to="mlprogram",
    compute_precision=ct.precision.FLOAT16,
)
converted.save("MyModel.mlpackage")
```

This is illustrative: select precision, input layout, normalization, dynamic
shape policy, and deployment target according to the reference model and
devices actually supported. `compute_units` in Core ML Tools is useful for
macOS conversion-time/loading-time testing; the iOS app must set its own
`MLModelConfiguration.computeUnits` at runtime.

### Swift adapter shape

Keep framework ownership on the Swift/Objective-C side, not in Mojo. A
minimal C ABI gives Mojo a stable integration seam:

```c
// MojoCoreMLAdapter.h -- include from an Objective-C(.mm) implementation.
// Return 0 on success; write a diagnostic/status code otherwise.
int mojo_coreml_predict_f32(const float *input, size_t input_count,
                            float *output, size_t output_count);
```

The implementation should retain one model per serialized executor/queue (or
create separate model instances per concurrent executor), construct feature
objects matching the compiled model description, invoke prediction, validate
the output feature, and only then expose it through this buffer ABI. Apple's
`MLModel` documentation says to use an instance on one thread or dispatch
queue at a time; respect that at the adapter boundary. A Swift implementation
can expose this C symbol with `@_cdecl`, or an Objective-C/Objective-C++
implementation can export it directly. Compile/link that adapter in Xcode
with `CoreML.framework`; link the Mojo archive through the existing C ABI
bridge. Do not pass Swift classes, Objective-C objects, exceptions, ownership
semantics, or framework callbacks across the Mojo C ABI.

For zero-copy aspirations, verify ownership, alignment, dtype, stride, and
lifetime against the target model and framework APIs first. A deliberate copy
is safer than handing Core ML an invalid or short-lived Mojo buffer.

## Accelerate route

Call Accelerate from the same Swift/Objective-C/C adapter. Its public headers
are C interfaces, which makes a narrow adapter especially natural:

- **vDSP/vForce:** vector arithmetic, reductions, convolution/filtering, FFTs,
  and related DSP operations.
- **BLAS/LAPACK:** dense matrix/vector algebra and solvers. Be explicit about
  row-major/column-major layout and leading dimensions; Apple's BLAS
  documentation highlights the distinction.
- **BNNS:** CPU neural-network training/inference primitives. `BNNSGraph` can
  execute whole CPU-based networks from an Xcode-compiled ML package, but it
  is not a mechanism to make arbitrary Mojo code run on ANE.

Apple documents [vDSP](https://developer.apple.com/documentation/accelerate/vdsp),
[BLAS](https://developer.apple.com/documentation/accelerate/blas-library), and
[BNNS](https://developer.apple.com/documentation/accelerate/bnns-library/).
Use `Accelerate.framework` rather than assuming an undocumented ABI or
instruction set. Benchmark on actual iOS hardware; Simulator figures are not
evidence of Apple-silicon device throughput or ANE placement.

## Validation and release gate

Treat conversion and device execution as separate gates:

1. **Reference parity:** save representative inputs and source-model outputs;
   run `coremltools` prediction on macOS and compare numerical tolerances,
   labels, and preprocessing. Core ML Tools notes that macOS validation does
   not remove the need to validate on the target platform.
2. **Artifact inspection:** record converter/coremltools version, source model
   revision/hash, input/output contract, deployment target, model type,
   precision, package size, and a checksum for the emitted `.mlpackage` or
   `.mlmodel`.
3. **Xcode integration:** inspect the model in Xcode, build the signed app,
   and verify model-resource inclusion. Test malformed input, wrong shape or
   dtype, insufficient output capacity, and model-load/prediction errors
   through the C ABI without process termination.
4. **Physical-device matrix:** test every supported iPhone/iPad class and
   lowest supported iOS release. Exercise `.all`, and constrained configurations
   only as diagnostic/fallback cases. Measure end-to-end latency, warm/cold
   load, memory, energy/thermal behavior, and numerical parity—not just one
   prediction.
5. **Accelerate parity:** compare vDSP/BLAS/BNNS results with a scalar or
   trusted reference; test strides, tails, aliasing policy, matrix layout,
   and boundary values. Benchmark the adapter boundary and copies as part of
   the workload.

See [Core ML Tools model prediction](https://apple.github.io/coremltools/docs-guides/source/model-prediction.html)
and [Core ML Tools quickstart validation note](https://apple.github.io/coremltools/docs-guides/source/introductory-quickstart.html).

## Packaging checklist

- Version-control conversion code and an input/output contract, but place the
  generated model in the application target using the project's chosen binary
  artifact policy.
- Bundle `.mlmodel`/`.mlpackage` through Xcode for build-time compilation;
  preserve the generated wrapper only as build output. For runtime downloads,
  persist source/compiled assets in an app-managed cache and compile outside
  the main thread.
- Select the model representation and `minimum_deployment_target` together;
  ML Program requires iOS 15 or later. Fail installation or choose a tested
  compatible model variant for older deployment targets.
- Treat model updates as code: checksum, authenticate/download safely, validate
  schema and outputs before promotion, and retain a known-good rollback asset.
- Include the adapter's framework link settings and C header in the Xcode
  target; expose a small, versioned C surface to Mojo.

## Non-goals and evidence standard

This document does not establish that any particular Mojo compiler/runtime
configuration supports iOS device deployment, nor does it claim a measured
speedup. Pair an integration with the repository's target/link/device evidence
and record exact devices, OS/Xcode/Core ML Tools versions, model artifacts,
configurations, and measurements. Claims about ANE usage require evidence from
the applicable Apple tooling on physical hardware; Core ML configuration alone
is insufficient.
