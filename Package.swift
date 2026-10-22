// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ayre",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ayre", targets: ["AyreCLI"]),
        .executable(name: "AyreReceiver", targets: ["AyreReceiver"]),
    ],
    targets: [
        .target(name: "AyreCore", path: "Sources/Core"),
        .executableTarget(name: "AyreCLI", dependencies: ["AyreCore"], path: "Sources/CLI"),
        .executableTarget(name: "AyreReceiver", dependencies: ["AyreCore"], path: "Sources/Receiver"),
        .testTarget(name: "AyreCoreTests", dependencies: ["AyreCore"], path: "Tests/AyreCoreTests"),
    ]
)
