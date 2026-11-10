// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zeus",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "Zeus", targets: ["Zeus"]),
        .executable(name: "zeus-hook", targets: ["zeus-hook"]),
        .executable(name: "zeus-bridge", targets: ["zeus-bridge"]),
        .executable(name: "zeus-cli", targets: ["zeus-cli"]),
        .executable(name: "zeus-silent-eval", targets: ["zeus-silent-eval"]),
        .library(name: "ZeusCore", targets: ["ZeusCore"]),
    ],
    dependencies: [
        // Parakeet speech-to-text on the Neural Engine (see docs/dictation-bench.md).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.18.0")),
        // Whisper large-v3 turbo on CoreML (WhisperKit, MIT). The model downloads only on click.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        .target(name: "ZeusCore"),
        .executableTarget(name: "Zeus", dependencies: [
            "ZeusCore",
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
        ], resources: [
            .copy("Avatar/Poses"), .copy("Avatar/Anim"), .copy("Fonts"),
            .copy("Onboarding/Media"), .copy("Integrations/Brands"), .copy("Sounds"),
        ]),
        .executableTarget(name: "zeus-hook", dependencies: ["ZeusCore"]),
        .executableTarget(name: "zeus-bridge", dependencies: ["ZeusCore"]),
        // Installed as `zeus` (a `zeus` target would clash with `Zeus` on a case-insensitive disk).
        .executableTarget(name: "zeus-cli", dependencies: ["ZeusCore"]),
        .executableTarget(name: "zeus-silent-eval", dependencies: ["ZeusCore"]),
        .testTarget(name: "ZeusCoreTests", dependencies: ["ZeusCore"], resources: [
            .copy("Fixtures"),
        ]),
        .testTarget(name: "ZeusAppTests", dependencies: ["Zeus", "ZeusCore"]),
    ]
)
