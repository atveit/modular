# ===----------------------------------------------------------------------=== #
# Copyright (c) 2026, Modular Inc. All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
# ===----------------------------------------------------------------------=== #

# RUN: mkdir %t
# RUN: %mojo-build %s -o %t/libstatic.a --emit static-lib
# RUN: file %t/libstatic.a | FileCheck %s
# CHECK: current ar archive

def main():
    pass
