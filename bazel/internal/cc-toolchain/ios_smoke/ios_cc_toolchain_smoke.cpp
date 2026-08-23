#include <cstdint>

extern "C" std::int64_t modular_ios_cc_add(std::int64_t lhs, std::int64_t rhs) {
  return lhs + rhs;
}

int main() { return modular_ios_cc_add(20, 22) == 42 ? 0 : 1; }
