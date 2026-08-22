#ifndef MODULAR_MOJO_IOS_COREGRAPHICS_H_
#define MODULAR_MOJO_IOS_COREGRAPHICS_H_

#ifdef __cplusplus
extern "C" {
#endif

// Constructs a CGRect and returns width * height. The CoreGraphics object used
// to anchor framework linkage is retained and released within the adapter; no
// Core Foundation/CoreGraphics object crosses this scalar/POD C ABI.
double mojo_coregraphics_rect_area(double width, double height);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_COREGRAPHICS_H_
