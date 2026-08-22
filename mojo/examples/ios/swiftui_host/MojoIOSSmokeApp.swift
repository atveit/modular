import SwiftUI

import MojoIOSSmoke

private let mojoMessageLength: Int64 = 23
private let expectedMojoMessage = "Hello from Mojo on iOS."

private func messageFromMojo() -> String {
    var bytes = [UInt8](repeating: 0, count: Int(mojoMessageLength))
    let requiredLength = bytes.withUnsafeMutableBufferPointer { buffer in
        mojo_hello_utf8(buffer.baseAddress, Int64(buffer.count))
    }

    guard requiredLength == mojoMessageLength else {
        return "Mojo returned an invalid message length"
    }
    return String(decoding: bytes, as: UTF8.self)
}

struct ContentView: View {
    private let sum: Int64
    private let message: String

    init() {
        sum = mojo_add(20, 22)
        message = messageFromMojo()
        precondition(sum == 42)
        precondition(message == expectedMojoMessage)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
            Text("20 + 22 = \(sum)")
        }
        .padding()
    }
}

@main
struct MojoIOSSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
