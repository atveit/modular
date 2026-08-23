//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "AsyncRT/Runtime/HostSystem.h"
#include "AsyncRT/Runtime/Globals/RuntimeGlobal.h"

#include <cstdio>
#include <cstdlib>
#include <mutex>

namespace M::AsyncRT {

CPUDeviceRef getOrCreateCPUDevice(CPUDeviceSource source,
                                  const CPUDeviceOptions &options,
                                  bool allowUsingExistingOptions) {
  std::lock_guard<std::mutex> lock(getGlobalCPUDeviceMutex());
  CPUDevice *existingCPUDevice = getGlobalCPUDevicePointer();
  if (existingCPUDevice) {
    if (getStoredGlobalCPUDeviceCreationOptions() != options &&
        !allowUsingExistingOptions) {
      std::fputs("AsyncRT CPUDevice options changed\n", stderr);
      std::abort();
    }
    return CPUDeviceRef::copy(existingCPUDevice);
  }

  if (options.workQueueType != CPUDeviceOptions::WorkQueueType::kSingleThread ||
      options.tcmallocAllocator || options.leakCheckedAllocator ||
      options.profilingAllocator || options.useAfterFreeAllocator ||
      options.numaPartitioned || !options.profileFilename.empty() ||
      options.profilerDebuginfo !=
          CPUDeviceOptions::ProfilerDebuginfo::kNoProfiler) {
    std::fputs("iOS AsyncRT requires malloc, one thread, and no profiler\n",
               stderr);
    std::abort();
  }

  CompactCPUDevicePtr cpuDevicePtr = CompactCPUDevicePtr::reserve();
  std::unique_ptr<Allocator> allocator = createMallocAllocator();
  std::unique_ptr<WorkQueue> workQueue =
      createSingleThreadWorkQueue(cpuDevicePtr);
  CPUDeviceRef newCPUDevice = CPUDeviceRef::take(new CPUDevice(
      cpuDevicePtr, std::move(allocator), std::move(workQueue), source,
      CPUDeviceType::kGlobal, kAnyNumaNode));

  getStoredGlobalCPUDeviceCreationOptions() = options;
  setGlobalCPUDevicePointer(newCPUDevice.getPointer());
  return newCPUDevice.copy();
}

} // namespace M::AsyncRT
