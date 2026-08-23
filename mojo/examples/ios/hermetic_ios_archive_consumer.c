#include "mojo_ios_archive.h"

#include <stddef.h>
#include <stdint.h>

extern void KGEN_CompilerRT_Initialize(void);

int main(void) {
  // Pull one bounded serial-core symbol through the same configured CcInfo
  // graph as the Mojo archive. This initializer is intentionally not AsyncRT's
  // std.runtime.initialize_runtime().
  KGEN_CompilerRT_Initialize();
  uint8_t message[64] = {0};
  const int64_t required = mojo_hello_utf8(message, sizeof(message));
  return mojo_add(20, 22) == 42 && required > 0 ? 0 : 1;
}
