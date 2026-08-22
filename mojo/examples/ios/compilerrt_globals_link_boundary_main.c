#include <stddef.h>
#include <stdio.h>

extern int KGEN_CompilerRT_Initialize(void);
extern void *KGEN_CompilerRT_AlignedAlloc(ptrdiff_t alignment, ptrdiff_t size);
extern void KGEN_CompilerRT_AlignedFree(void *ptr);
extern void *KGEN_CompilerRT_GetOrCreateGlobalIndexed(
    size_t index, void *(*init_fn)(void), void (*destroy_fn)(void *));
extern void KGEN_CompilerRT_DestroyGlobals(void);

static void *create_value(void) {
  return KGEN_CompilerRT_AlignedAlloc(8, 32);
}

static void destroy_value(void *value) {
  KGEN_CompilerRT_AlignedFree(value);
}

int main(void) {
  if (!KGEN_CompilerRT_Initialize())
    return 1;
  if (!KGEN_CompilerRT_GetOrCreateGlobalIndexed(0, create_value, destroy_value))
    return 2;
  KGEN_CompilerRT_DestroyGlobals();
  puts("MOJO_COMPILERRT_GLOBALS_PROBE_PASS");
  return 0;
}
