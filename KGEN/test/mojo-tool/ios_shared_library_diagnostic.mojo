# RUN: not %mojo-build --target-triple arm64-apple-ios17.0-simulator --target-cpu apple-m1 --emit shared-lib %s -o %t.simulator 2>&1 | FileCheck %s --check-prefix=SIMULATOR
# RUN: not %mojo-build --target-triple arm64-apple-ios17.0 --target-cpu apple-a7 --emit shared-lib %s -o %t.device 2>&1 | FileCheck %s --check-prefix=DEVICE

# iOS shared-library output must not reach the host macOS linker. Consumers
# should receive a static archive and link it with the matching Apple SDK.
# SIMULATOR: error: iOS shared-library emission is not supported by this Mojo driver; use --emit static-lib and link with the matching Apple SDK
# DEVICE: error: iOS shared-library emission is not supported by this Mojo driver; use --emit static-lib and link with the matching Apple SDK

@export("ios_shared_library_probe")
def ios_shared_library_probe(value: Int64) abi("C") -> Int64:
    return value
