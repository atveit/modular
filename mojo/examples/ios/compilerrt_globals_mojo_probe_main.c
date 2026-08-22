#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern int64_t mojo_ios_global_symbol_probe(void);
extern void KGEN_CompilerRT_DestroyGlobals(void);

int main(void) {
  assert(mojo_ios_global_symbol_probe() == 1);
  assert(mojo_ios_global_symbol_probe() == 2);
  KGEN_CompilerRT_DestroyGlobals();
  puts("MOJO_COMPILERRT_GLOBALS_MOJO_PROBE_PASS");
  return 0;
}
