import MojoIOSAccelerate

@main
struct AccelerateConsumer {
    static func main() {
        let lhs: [Float] = [1, 2, 3, 4]
        let rhs: [Float] = [10, 20, 30, 40]
        var output = [Float](repeating: 0, count: lhs.count)

        let status = lhs.withUnsafeBufferPointer { lhsBuffer in
            rhs.withUnsafeBufferPointer { rhsBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    mojo_accelerate_vector_add(
                        lhsBuffer.baseAddress,
                        rhsBuffer.baseAddress,
                        outputBuffer.baseAddress,
                        Int64(outputBuffer.count)
                    )
                }
            }
        }

        precondition(status == 0)
        precondition(output == [11, 22, 33, 44])
        print("MOJO_ACCELERATE_VDSP_PASS")
    }
}
