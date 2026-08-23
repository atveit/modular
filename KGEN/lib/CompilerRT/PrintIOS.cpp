//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

// iOS candidate for the standard-library formatted-print ABI.
//
// Keep this separate from System.cpp: that desktop source also owns CPU
// topology, argv, configuration, LLVM stack traces, and signal handlers. The
// iOS core seed currently needs only this public libc forwarding function.
//===----------------------------------------------------------------------===//

#include "Support/SymbolExport.h"

#include <cstdarg>
#include <cstdio>

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT int
KGEN_CompilerRT_fprintf(FILE *stream, const char *format, ...) {
  va_list args;
  va_start(args, format);
  int result = vfprintf(stream, format, args);
  va_end(args);
  return result;
}
