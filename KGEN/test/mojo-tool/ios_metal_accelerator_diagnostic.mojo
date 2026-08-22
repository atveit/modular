# RUN: not %mojo-build --target-triple arm64-apple-ios17.0-simulator --target-cpu apple-m1 --target-accelerator metal:4 --emit asm %s -o %t.simulator 2>&1 | FileCheck %s --check-prefix=SIMULATOR
# RUN: not %mojo-build --target-triple arm64-apple-ios17.0 --target-cpu apple-a7 --target-accelerator metal:4 --emit asm %s -o %t.device 2>&1 | FileCheck %s --check-prefix=DEVICE

# An iOS CPU host plus the existing Metal accelerator path must stop before it
# tries to compile the macOS-only `air64-apple-macosx` sidecar.
# SIMULATOR: error: Mojo iOS Metal AIR is not implemented: target triple 'arm64-apple-ios17.0-simulator' with Metal accelerator 'metal:4' would select the macOS AIR sidecar.
# DEVICE: error: Mojo iOS Metal AIR is not implemented: target triple 'arm64-apple-ios17.0' with Metal accelerator 'metal:4' would select the macOS AIR sidecar.

def main():
    pass
