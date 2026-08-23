#include "MojoIOSCore.h"

extern void KGEN_CompilerRT_Initialize(void);
extern int64_t mojo_add(int64_t lhs, int64_t rhs);
extern int64_t mojo_hello_utf8(uint8_t *output, int64_t capacity);

int64_t mojo_ios_package_add(int64_t lhs, int64_t rhs) {
  KGEN_CompilerRT_Initialize();
  return mojo_add(lhs, rhs);
}

int64_t mojo_ios_package_hello_utf8(uint8_t *output, int64_t capacity) {
  KGEN_CompilerRT_Initialize();
  return mojo_hello_utf8(output, capacity);
}
