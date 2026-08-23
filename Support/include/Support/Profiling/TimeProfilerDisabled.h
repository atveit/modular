//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#ifndef SUPPORT_PROFILING_TIMEPROFILER_DISABLED_H
#define SUPPORT_PROFILING_TIMEPROFILER_DISABLED_H

#include <cstdint>
#include <limits>
#include <utility>

namespace M {

static constexpr bool kIsProfilingEnabled = false;

struct Trace {
  enum Type : uint8_t {
    kOther = 0,
    kAsyncRT = 1,
    kMem = 2,
  };

  static constexpr uint64_t kProfilingTypeWidthBits = 3;
  static constexpr uint64_t kFullyEnabled =
      std::numeric_limits<uint64_t>::max();
  static constexpr uint64_t typeBitshift(Type type) {
    return type * kProfilingTypeWidthBits;
  }
  static constexpr bool EnableTrace(Type, uint64_t) { return false; }
};

template <bool Enabled, Trace::Type Type> class ProfilerEntry {
public:
  template <typename... Args> static ProfilerEntry create(Args &&...) {
    return {};
  }
};

class TimeTraceScope {
public:
  template <typename Entry> explicit TimeTraceScope(Entry &&) {}
};

class TimeTraceProfiler {
public:
  TimeTraceProfiler() = default;
};

} // namespace M

#endif // SUPPORT_PROFILING_TIMEPROFILER_DISABLED_H
