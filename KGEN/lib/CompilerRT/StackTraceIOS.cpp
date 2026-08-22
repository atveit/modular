//===----------------------------------------------------------------------===//
// iOS candidate for the minimal Error stack-trace ABI.
//
// The standard library interprets a zero return from GetStackTrace as "not
// collected". This narrow candidate makes that behavior explicit for iOS
// static-runtime experiments without importing desktop configuration, signal,
// or LLVM stack-trace support. It does not provide stack-trace collection.
//===----------------------------------------------------------------------===//

#include "Support/SymbolExport.h"

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT int
KGEN_CompilerRT_GetStackTrace(char **strings, unsigned depth) {
  (void)depth;
  if (strings)
    *strings = nullptr;
  return 0;
}
