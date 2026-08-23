#include "mojo_ios_core_abi_probe.h"
#include "mojo_ios_smoke.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern int64_t mojo_ios_runtime_string_length(int64_t value);

int main(void) {
  static const uint8_t expected[] = "Hello from Mojo on iOS.";
  for (int64_t iteration = 0; iteration < 10000; ++iteration) {
    assert(mojo_add(iteration, 1) == iteration + 1);

    uint8_t message[23] = {0};
    assert(mojo_hello_utf8(message, (int64_t)sizeof(message)) == 23);
    assert(memcmp(message, expected, sizeof(message)) == 0);
    assert(mojo_hello_utf8(NULL, 0) == 23);

    MojoIOSHandle *handle = mojo_ios_handle_create(iteration);
    assert(handle != NULL);
    int64_t handle_value = -1;
    assert(mojo_ios_handle_read(handle, &handle_value) == 0);
    assert(handle_value == iteration);
    assert(mojo_ios_handle_destroy(handle) == 0);

    int64_t doubled = -1;
    assert(mojo_ios_checked_double(iteration, &doubled) == 0);
    assert(doubled == iteration * 2);
    assert(mojo_ios_checked_double(-1, &doubled) == 2);
    assert(mojo_ios_checked_double(iteration, NULL) == 2);

    assert(mojo_ios_runtime_string_length(iteration) >= 64);
  }

  puts("MOJO_COMPILERRT_CORE_ABI_STRESS_PASS");
  return 0;
}
