# Direct-C os/signpost adapter fixture

This fixture anchors the public `os/signpost.h` C API behind one scalar C ABI:
`mojo_os_signpost_emit() -> int32_t`. It emits a fixed-name event to
`OS_LOG_DEFAULT`; no object, handle, string, callback, variadic format, or
ownership crosses the boundary.

Run the artifact check from the repository root:

```sh
mojo/examples/ios/os_signpost_adapter/run_os_signpost_smoke.sh
```

The harness compiles the C adapter and links a Swift C-ABI consumer with the
iOS SDK system library for arm64 iPhone OS and Simulator iOS 17. (`os` is a
public header/API surface here, not a separately linkable iOS framework.) It
requires the adapter export, an os/signpost implementation reference,
`libSystem` linkage, and matching Mach-O platform metadata.

This is compile/link-only evidence. It does not launch an app, capture or
visualize signposts, establish a profiling workflow, use the Mojo runtime, or
make physical-device claims. The next useful milestone is a Simulator/device
profiling integration that collects the fixed signpost from a real workload.
