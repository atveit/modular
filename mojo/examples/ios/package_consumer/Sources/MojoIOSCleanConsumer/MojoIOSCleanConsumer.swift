import Foundation
import MojoIOS
import SwiftUI

private enum PackageEvidence {
    static let message = MojoIOS.message()
    static let sum = MojoIOS.add(20, 22)

    static func validateAndRecord() {
        precondition(message == "Hello from Mojo on iOS.")
        precondition(sum == 42)

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        try! FileManager.default.createDirectory(
            at: documents,
            withIntermediateDirectories: true
        )
        try! "MOJO_IOS_PACKAGE_PASS\n".write(
            to: documents.appendingPathComponent("mojo-ios-package-pass.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(PackageEvidence.message)
            Text("20 + 22 = \(PackageEvidence.sum)")
        }
        .padding()
    }
}

@main
struct MojoIOSCleanConsumerApp: App {
    init() {
        PackageEvidence.validateAndRecord()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
