//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#ifndef ASYNCRT_RUNTIME_PROFILING_H
#define ASYNCRT_RUNTIME_PROFILING_H

#if defined(MODULAR_ASYNCRT_DISABLE_PROFILING)
#include "Support/Profiling/TimeProfilerDisabled.h"
#else
#include "Support/Profiling/TimeProfiler.h"
#endif

#endif // ASYNCRT_RUNTIME_PROFILING_H
