// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PromptInsertProbe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PromptInsertProbeCLI", targets: ["PromptInsertProbeCLI"]),
        .executable(name: "PromptInsertProbeReceiver", targets: ["PromptInsertProbeReceiver"]),
    ],
    targets: [
        .target(name: "ProbeCore", path: "Sources/Core"),
        .executableTarget(name: "PromptInsertProbeCLI", dependencies: ["ProbeCore"], path: "Sources/CLI"),
        .executableTarget(name: "PromptInsertProbeReceiver", dependencies: ["ProbeCore"], path: "Sources/Receiver"),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"], path: "Tests/ProbeCoreTests"),
    ]
)
