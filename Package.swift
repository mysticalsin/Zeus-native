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
        .executable(name: "zeus-native-test-host", targets: ["zeus-native-test-host"]),
        // Test-only: one Fling endpoint driven over stdin and stdout. Never bundled into the app.
        .executable(name: "zeus-fling-peer", targets: ["zeus-fling-peer"]),
        .library(name: "ZeusCore", targets: ["ZeusCore"]),
    ],
    dependencies: [
        // Parakeet speech-to-text on the Neural Engine (see docs/dictation-bench.md).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.18.0")),
        // Whisper large-v3 turbo on CoreML (WhisperKit, MIT). The model downloads only on click.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
        // Signed updates. Exact pin. The app target links it on macOS only.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "ZeusCore"),
        // Fling transport on Network.framework. Its callbacks are not Sendable-annotated, so it builds in Swift 5 mode.
        .target(name: "ZeusFling", dependencies: ["ZeusCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Catches Objective-C exceptions from Apple frameworks that Swift cannot catch (see header).
        .target(name: "ZeusObjCGuard"),
        .executableTarget(name: "Zeus", dependencies: [
            "ZeusCore",
            "ZeusFling",
            "ZeusObjCGuard",
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
        ], resources: [
            .copy("Avatar/Poses"), .copy("Avatar/Anim"), .copy("Fonts"),
            .copy("Onboarding/Media"), .copy("Integrations/Brands"), .copy("Sounds"), .copy("Personality"),
        ]),
        .executableTarget(name: "zeus-hook", dependencies: ["ZeusCore"]),
        .executableTarget(name: "zeus-bridge", dependencies: ["ZeusCore"]),
        // Installed as `zeus` (a `zeus` target would clash with `Zeus` on a case-insensitive disk).
        .executableTarget(name: "zeus-cli", dependencies: ["ZeusCore"]),
        .executableTarget(name: "zeus-silent-eval", dependencies: ["ZeusCore"]),
        // Test-only AppKit lifecycle owner. Never included in the Zeus app bundle.
        .executableTarget(name: "zeus-native-test-host", path: "qa/native-app-host"),
        .executableTarget(name: "zeus-fling-peer", dependencies: ["ZeusFling", "ZeusCore"], path: "qa/fling-peer",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ZeusCoreTests", dependencies: ["ZeusCore"], resources: [
            .copy("Fixtures"),
        ]),
        .testTarget(name: "ZeusAppTests", dependencies: ["Zeus", "ZeusCore", "ZeusFling"]),
    ]
)
