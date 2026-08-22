#include "mojo_ios_coregraphics.h"

#include <CoreGraphics/CoreGraphics.h>

double mojo_coregraphics_rect_area(double width, double height) {
  CGRect rectangle = CGRectMake(0.0, 0.0, width, height);

  // Keep CoreGraphics resource management inside the C adapter. This is only
  // a framework anchor; the public ABI remains two doubles in and one out.
  CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
  if (color_space == NULL) {
    return -1.0;
  }
  CGColorSpaceRelease(color_space);
  return CGRectGetWidth(rectangle) * CGRectGetHeight(rectangle);
}
