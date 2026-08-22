//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

#include "Target/TargetTraits.h"

#include "Support/Configuration.h"

#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/Host.h"
#include "llvm/Support/ManagedStatic.h"
#include "llvm/TargetParser/Triple.h"

namespace M::KGEN {

ApplePlatform getApplePlatform(const llvm::Triple &triple) {
  switch (triple.getOS()) {
  // LLVM uses both `darwin` and `macosx` spellings for macOS triples.
  case llvm::Triple::Darwin:
  case llvm::Triple::MacOSX:
    return ApplePlatform::MacOS;
  case llvm::Triple::IOS:
    return triple.getEnvironment() == llvm::Triple::Simulator
               ? ApplePlatform::IOSSimulator
               : ApplePlatform::IOSDevice;
  default:
    return ApplePlatform::None;
  }
}

bool isCrossCompilation(const llvm::Triple &target,
                        const llvm::Triple &host) {
  // Do not use architecture alone here: arm64 macOS -> arm64 iOS is a
  // cross-OS compilation, and the Simulator environment is distinct from a
  // physical-device environment.
  return target.getArch() != host.getArch() ||
         target.getVendor() != host.getVendor() ||
         target.getOS() != host.getOS() ||
         target.getEnvironment() != host.getEnvironment();
}

bool isCrossCompilation(const llvm::Triple &target) {
  return isCrossCompilation(target,
                             llvm::Triple(llvm::sys::getDefaultTargetTriple()));
}

ErrorOrSuccess requireMaxForAccelerator(bool isMaxOnly) {
  if (!isMaxOnly)
    return success();
  // MAX presence is a process-level fact; cache it to avoid a config/filesystem
  // probe on every registry lookup.
  static const bool maxInstalled = isMaxInstalled();
  if (!maxInstalled)
    return Error("please install MAX for accelerator support");
  return success();
}

void requireMaxForAcceleratorRequest(llvm::StringRef targetAccelerator) {
  if (targetAccelerator.empty())
    return;
  static const bool maxInstalled = isMaxInstalled();
  if (!maxInstalled) {
    llvm::report_fatal_error("please install MAX for accelerator support",
                             /*gen_crash_diag=*/false);
  }
}

static llvm::ManagedStatic<TargetTraitsRegistry> theTraitsRegistry;

TargetTraitsRegistry &TargetTraitsRegistry::get() { return *theTraitsRegistry; }

void TargetTraitsRegistry::add(std::unique_ptr<TargetTraits> traits) {
  Targets.push_back(std::move(traits));
}

ErrorOr<const TargetTraits *>
TargetTraitsRegistry::lookup(const llvm::Triple &triple) const {
  // A traits object that resolves `triple` to one it owns takes precedence over
  // a direct self-match.
  const TargetTraits *result = [&]() -> const TargetTraits * {
    const TargetTraits *directMatch = nullptr;
    for (const std::unique_ptr<TargetTraits> &traits : Targets) {
      const TargetTraits *resolved = traits->resolve(triple);
      if (!resolved)
        continue;
      if (resolved != traits.get())
        return resolved;
      if (!directMatch)
        directMatch = resolved;
    }
    return directMatch;
  }();
  if (!result) {
    return Error("target '" + triple.str() +
                 "' is not supported by this build");
  }
  if (ErrorOrSuccess e = requireMaxForAccelerator(!result->isBaseTarget()))
    return Error(e.getError());
  return result;
}

} // namespace M::KGEN
