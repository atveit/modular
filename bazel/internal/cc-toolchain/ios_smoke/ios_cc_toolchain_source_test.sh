#!/bin/bash

set -euo pipefail

readonly source_file="${TEST_SRCDIR}/${TEST_WORKSPACE}/bazel/internal/cc-toolchain/ios_smoke/ios_cc_toolchain_smoke.cpp"

grep -Fq 'extern "C" std::int64_t modular_ios_cc_add' "${source_file}"
grep -Fq 'modular_ios_cc_add(20, 22) == 42' "${source_file}"
