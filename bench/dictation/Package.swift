// swift-tools-version: 6.0
// Standalone benchmark: kept out of the main package so the app build never pulls model SDKs.
import PackageDescription

let package = Package(
    name: "DictationBench",
    platforms: [.macOS("14.2")],
    dependencies: [
        .package(name: "Zeus", path: "../.."),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.9.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.14.0"),
    ],
    targets: [
        .executableTarget(name: "dictation-bench", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "WhisperKit", package: "WhisperKit"),
            .product(name: "ZeusCore", package: "Zeus"),
        ], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
