//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "AsyncRT/Runtime/CompactCPUDevicePtr.h"
#include "AsyncRT/Runtime/Globals/Globals.h"

#include <atomic>

using namespace M::AsyncRT;

[[maybe_unused]] MODULAR_CXX_EXPORT std::atomic<ssize_t>
    M::AsyncRT::Globals::totalAllocatedAsyncValues{0};

MODULAR_CXX_EXPORT CompactCPUDevicePtr &
M::AsyncRT::Globals::getCurrentCPUDeviceInTLS() {
  static thread_local CompactCPUDevicePtr currentCPUDeviceInTLS;
  return currentCPUDeviceInTLS;
}

MODULAR_CXX_EXPORT Detail::CPUDeviceTable &
M::AsyncRT::Globals::getCPUDeviceTableSingleton(
    const std::function<Detail::CPUDeviceTable *()> &ctor) {
  static Detail::CPUDeviceTable *table = ctor();
  return *table;
}

static std::atomic<uint64_t> globalUniqueTaskIdCounter{0};

MODULAR_CXX_EXPORT uint64_t M::AsyncRT::getUniqueTaskIdForWorkItem() {
  return globalUniqueTaskIdCounter.fetch_add(1, std::memory_order_relaxed);
}
