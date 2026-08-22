#ifndef MODULAR_MOJO_IOS_COREML_H_
#define MODULAR_MOJO_IOS_COREML_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Compile/link-only framework anchor. This does not load a model, make a
// prediction, select a compute unit, or make any runtime/device claim.
int32_t mojo_coreml_framework_anchor(void);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_COREML_H_
