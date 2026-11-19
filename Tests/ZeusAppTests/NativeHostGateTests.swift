import Foundation
import Testing

/// The AppKit journey suites drive real windows and need NSApplication to own the main loop. Under a plain
/// `swift test` process that loop never runs, and the first real window event ends the whole process through
/// exit(), so the run stops with no summary. They run only in the native test host; this is how they tell.
@Suite("Hosted suites only run in the native host")
struct NativeHostGateTests {
    @Test func theNativeHostIsRecognisedByItsExecutableName() {
        #expect(NativeTestHost.isHost(arguments: ["/x/Products/Debug/zeus-native-test-host", "--test-bundle-path", "/x/y"]))
        #expect(NativeTestHost.isHost(arguments: ["zeus-native-test-host"]))
    }

    @Test func aPlainSwiftTestProcessIsNotTheHost() {
        #expect(!NativeTestHost.isHost(arguments: ["/usr/bin/swiftpm-testing-helper", "--test-bundle-path", "/x/y"]))
        #expect(!NativeTestHost.isHost(arguments: ["/x/zeus-native-test-host-not"]))
        #expect(!NativeTestHost.isHost(arguments: []))
    }
}
