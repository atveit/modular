#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern int64_t mojo_ios_global_symbol_probe(void);
extern int64_t mojo_ios_error_symbol_probe(int64_t value);
extern void KGEN_CompilerRT_DestroyGlobals(void);
extern int KGEN_CompilerRT_Initialize(void);

int main(void) {
  assert(KGEN_CompilerRT_Initialize());
  assert(mojo_ios_global_symbol_probe() == 1);
  assert(mojo_ios_global_symbol_probe() == 2);
  assert(mojo_ios_error_symbol_probe(23) == 23);
  KGEN_CompilerRT_DestroyGlobals();
  puts("MOJO_COMPILERRT_CORE_SEED_PROBE_PASS");
  return 0;
}
