#include "mojo_ios_runtime_probe.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
  assert(mojo_ios_runtime_string_length(7) >= 64);
  puts("MOJO_RUNTIME_STRING_PROBE_PASS");
  return 0;
}
