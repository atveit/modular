#include "mojo_ios_runtime_string.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
  // "allocation-" (11 bytes) + "42" (2 bytes).
  assert(mojo_runtime_string_byte_count(42) == 13);
  puts("MOJO_RUNTIME_STRING_PROBE_PASS");
  return 0;
}
