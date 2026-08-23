//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "AsyncRT/Runtime/CPUDevice.h"

using namespace M::AsyncRT;

bool CPUDeviceOptions::operator==(const CPUDeviceOptions &other) const {
  return numThreads == other.numThreads && maxThreads == other.maxThreads &&
         profileFilename == other.profileFilename &&
         runtimeProfilingTypeMask == other.runtimeProfilingTypeMask &&
         mainWillDonate == other.mainWillDonate &&
         threadBusyWaitTime == other.threadBusyWaitTime &&
         withAffinity == other.withAffinity &&
         leakCheckedAllocator == other.leakCheckedAllocator &&
         tcmallocAllocator == other.tcmallocAllocator &&
         profilingAllocator == other.profilingAllocator &&
         useAfterFreeAllocator == other.useAfterFreeAllocator &&
         workQueueType == other.workQueueType &&
         numaPartitioned == other.numaPartitioned &&
         allocatorType == other.allocatorType &&
         profilerDebuginfo == other.profilerDebuginfo;
}

CPUDeviceOptions CPUDeviceOptions::copy() const {
  return *this;
}
