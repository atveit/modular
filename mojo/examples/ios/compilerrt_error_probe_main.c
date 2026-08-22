#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern int64_t mojo_ios_error_symbol_probe(int64_t value);

int main(void) {
  assert(mojo_ios_error_symbol_probe(17) == 17);
  puts("MOJO_COMPILERRT_ERROR_PROBE_PASS");
  return 0;
}
