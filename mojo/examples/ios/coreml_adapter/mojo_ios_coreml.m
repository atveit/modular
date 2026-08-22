#import <CoreML/CoreML.h>

#include "mojo_ios_coreml.h"

int32_t mojo_coreml_framework_anchor(void) {
  // Keep a public Core ML class reference in the adapter object so that the
  // linker must resolve the framework. The smoke executable never calls this
  // function: model loading, prediction, and runtime scheduling are out of
  // scope for this artifact-only fixture.
  return [MLModel class] == Nil ? -1 : 0;
}
