#include "mojo_ios_smoke.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>

int main(void) {
  assert(mojo_add(20, 22) == 42);

  uint8_t message[23] = {0};
  assert(mojo_hello_utf8(message, (int64_t)sizeof(message)) == 23);
  static const uint8_t expected[] = "Hello from Mojo on iOS.";
  for (int64_t i = 0; i < 23; ++i) {
    assert(message[i] == expected[i]);
  }

  // Querying the required size must not dereference a null output pointer.
  assert(mojo_hello_utf8(NULL, 0) == 23);
  return 0;
}
