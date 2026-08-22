//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//===----------------------------------------------------------------------===//

#include "KGEN/ToolCommon/CompilationOptions.h"
#include "Target/TargetTraits.h"

#include "gtest/gtest.h"
#include "llvm/TargetParser/Triple.h"

using namespace M::KGEN;

TEST(CompilationOptionsTest, ClassifiesApplePlatforms) {
  EXPECT_EQ(getApplePlatform(llvm::Triple("arm64-apple-darwin25")),
            ApplePlatform::MacOS);
  EXPECT_EQ(getApplePlatform(llvm::Triple("arm64-apple-macosx17.0")),
            ApplePlatform::MacOS);
  EXPECT_EQ(getApplePlatform(llvm::Triple("arm64-apple-ios17.0")),
            ApplePlatform::IOSDevice);
  EXPECT_EQ(
      getApplePlatform(llvm::Triple("arm64-apple-ios17.0-simulator")),
      ApplePlatform::IOSSimulator);
  EXPECT_EQ(getApplePlatform(llvm::Triple("aarch64-unknown-linux-gnu")),
            ApplePlatform::None);
}

TEST(CompilationOptionsTest, ComparesCompleteTargetIdentity) {
  const llvm::Triple host("arm64-apple-darwin25");
  const llvm::Triple sameArchMac("arm64-apple-darwin25");
  const llvm::Triple device("arm64-apple-ios17.0");
  const llvm::Triple simulator("arm64-apple-ios17.0-simulator");
  const llvm::Triple differentArch("x86_64-apple-darwin25");

  EXPECT_FALSE(isCrossCompilation(sameArchMac, host));
  EXPECT_TRUE(isCrossCompilation(device, host));
  EXPECT_TRUE(isCrossCompilation(simulator, host));
  EXPECT_TRUE(isCrossCompilation(differentArch, host));
}

TEST(CompilationOptionsTest, UsesConservativeIOSCPUBaselines) {
  CompilationOptions simulatorOptions(
      3, CompilationOptions::kNoDebug, std::nullopt, M::Sanitizers(),
      "arm64-apple-ios17.0-simulator", "", "", "");
  CompilationOptions deviceOptions(3, CompilationOptions::kNoDebug,
                                   std::nullopt, M::Sanitizers(),
                                   "arm64-apple-ios17.0", "", "", "");

  EXPECT_EQ(simulatorOptions.targetCpu, "apple-m1");
  EXPECT_EQ(deviceOptions.targetCpu, "apple-a7");
}
