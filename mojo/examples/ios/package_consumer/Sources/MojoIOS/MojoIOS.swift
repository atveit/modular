import MojoIOSCore

public enum MojoIOS {
    public static func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        mojo_ios_package_add(lhs, rhs)
    }

    public static func message() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        let required = bytes.withUnsafeMutableBufferPointer { buffer in
            mojo_ios_package_hello_utf8(buffer.baseAddress, Int64(buffer.count))
        }
        precondition(required >= 0 && required <= Int64(bytes.count))
        return String(decoding: bytes.prefix(Int(required)), as: UTF8.self)
    }
}
