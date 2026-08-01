// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDLCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MacDLCore", targets: ["MacDLCore"]),
    ],
    targets: [
        .target(name: "MacDLCore"),
        .testTarget(
            name: "MacDLCoreTests",
            dependencies: ["MacDLCore"]
        ),
    ]
)
