# Compile-only D7 SIMD instruction probe. Dynamic scalar inputs prevent folding;
# the exported reduction gives the vector computation an observable result.


@export("mojo_ios_simd_weighted_sum")
def mojo_ios_simd_weighted_sum(
    a: Float32, b: Float32, c: Float32, d: Float32
) abi("C") -> Float32:
    var values = SIMD[DType.float32, 4](a, b, c, d)
    var weights = SIMD[DType.float32, 4](d, c, b, a)
    return (values * weights + values).reduce_add()
