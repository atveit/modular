#include "mojo_ios_runtime_probe.h"

#include <assert.h>

int main(void) {
  assert(mojo_ios_runtime_string_length(7) >= 64);
  return 0;
}
