// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimanagerCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SimanagerCore", targets: ["SimanagerCore"])],
    targets: [
        .target(name: "SimanagerCore"),
        .testTarget(name: "SimanagerCoreTests", dependencies: ["SimanagerCore"], resources: [.copy("Fixtures")]),
    ]
)
