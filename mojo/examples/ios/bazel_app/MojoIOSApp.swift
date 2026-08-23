import SwiftUI

import mojo_examples_ios_mojo_ios_archive
import mojo_examples_ios_bazel_app_MojoIOSSerialCoreAnchor

public enum MojoIOSValues {
    public static let expectedMessage = "Hello from Mojo on iOS."

    public static func message() -> String {
        mojo_ios_serial_core_anchor()
        var bytes = [UInt8](repeating: 0, count: 64)
        let required = bytes.withUnsafeMutableBufferPointer { buffer in
            mojo_hello_utf8(buffer.baseAddress, Int64(buffer.count))
        }
        guard required >= 0, required <= Int64(bytes.count) else {
            return "Mojo returned an invalid message length"
        }
        return String(decoding: bytes.prefix(Int(required)), as: UTF8.self)
    }

    public static func sum() -> Int64 {
        mojo_add(20, 22)
    }
}

struct ContentView: View {
    private let message = MojoIOSValues.message()
    private let sum = MojoIOSValues.sum()

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .accessibilityIdentifier("mojo-greeting")
            Text("20 + 22 = \(sum)")
                .accessibilityIdentifier("mojo-sum")
        }
        .padding()
    }
}

@main
struct MojoIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
