import SwiftUI

import MojoIOSSmoke

private let mojoMessageLength: Int64 = 23

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
    private let sum = mojo_add(20, 22)
    private let message = messageFromMojo()

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
