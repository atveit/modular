// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MojoIOSPackage",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MojoIOS", targets: ["MojoIOS"]),
        .executable(
            name: "MojoIOSCleanConsumer",
            targets: ["MojoIOSCleanConsumer"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "MojoIOSCore",
            path: "Artifacts/MojoIOSCore.xcframework"
        ),
        .target(
            name: "MojoIOS",
            dependencies: ["MojoIOSCore"]
        ),
        .executableTarget(
            name: "MojoIOSCleanConsumer",
            dependencies: ["MojoIOS"]
        ),
    ]
)
