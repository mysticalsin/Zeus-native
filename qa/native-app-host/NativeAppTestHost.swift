import AppKit
import Darwin
import Foundation

// Swift Testing's documented tools ABI v0. Do not call the test bundle's generated
// async main: NSApplication must own this process's main run loop.
private typealias TestEntryPoint = @convention(thin) @Sendable (
    UnsafeRawBufferPointer?,
    @escaping @Sendable (UnsafeRawBufferPointer) -> Void
) async throws -> Bool

private struct HostFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func report(_ message: String) {
    FileHandle.standardError.write(Data("Owned-window test host: \(message)\n".utf8))
}

@MainActor
private final class TestSession: NSObject {
    private let entryPoint: TestEntryPoint
    private let wakeEvent: NSEvent
    private var task: Task<Void, Never>?
    private(set) var exitCode: CInt?

    init(entryPoint: @escaping TestEntryPoint, wakeEvent: NSEvent) {
        self.entryPoint = entryPoint
        self.wakeEvent = wakeEvent
    }

    @objc func didFinishLaunching(_ notification: Notification) {
        guard task == nil else { return }
        NSApplication.shared.activate()
        task = Task { @MainActor [self] in
            do {
                guard NSApplication.shared.isRunning else {
                    throw HostFailure("AppKit loop is not running")
                }
                // The library parses --filter and owns the version-0 JSONL file
                // writer and normal stderr summary. The callback is not evidence.
                let passed = try await entryPoint(nil) { _ in }
                exitCode = passed ? EXIT_SUCCESS : EXIT_FAILURE
            } catch {
                report(String(describing: error))
                exitCode = EXIT_FAILURE
            }
            NSApplication.shared.stop(nil)
            NSApplication.shared.postEvent(wakeEvent, atStart: false)
        }
    }
}

@main
@MainActor
private enum NativeAppTestHost {
    static func main() {
        do {
            let args = CommandLine.arguments
            // Authenticated later by the original test.log hash. This identifies
            // this synthetic host's crash report without launching another host.
            let timestamp = ISO8601DateFormatter()
            timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
                throw HostFailure("could not identify the synthetic host executable")
            }
            let identity: [String: Any] = [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "started": timestamp.string(from: Date()),
                "executable": executable
            ]
            let identityData = try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])
            var identityRecord = Data("Owned-window test host identity: ".utf8)
            identityRecord.append(identityData)
            identityRecord.append(Data("\n".utf8))
            FileHandle.standardError.write(identityRecord)
            let filters: Set<String> = [
                "^ZeusAppTests\\.OwnedWindowEventDriverTests/",
                "^ZeusAppTests\\.ScribeComponentJourneyTests/",
                "^ZeusAppTests\\.ScribeAccessibilityJourneyTests/",
                "^ZeusAppTests\\.OnboardingComponentJourneyTests/",
                "^ZeusAppTests\\.OnboardingFilmLifecycleTests/",
                "^ZeusAppTests\\.ExplanationRendererTests/",
                "^ZeusAppTests\\.ExplanationTalkButtonTests/",
                "^ZeusAppTests\\.ExplanationScreenContextTests/",
                "^ZeusAppTests\\.ExplanationChatLifecycleTests/",
                // Local trusted-Mac journey only (scripts/trusted-ax-journey.sh); CI never selects it.
                "^ZeusAppTests\\.ScribeTrustedAccessibilityJourneyTests/"
            ]
            guard args.count == 9,
                  args[1] == "--test-bundle-path",
                  args[3] == "--filter", filters.contains(args[4]),
                  args[5] == "--event-stream-output-path",
                  args[7] == "--event-stream-version", args[8] == "0",
                  (args[2] as NSString).isAbsolutePath,
                  (args[6] as NSString).isAbsolutePath else {
                throw HostFailure("unexpected host arguments")
            }
            if ProcessInfo.processInfo.environment["ZEUS_CI_REQUIRE_NORMAL_MOTION"] == "1" {
                let environment = ProcessInfo.processInfo.environment
                guard environment["GITHUB_ACTIONS"] == "true",
                      environment["RUNNER_ENVIRONMENT"] == "github-hosted",
                      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                    throw HostFailure("CI normal-motion profile unavailable in this fresh host")
                }
                report("CI normal-motion profile verified through NSWorkspace")
            }
            // Keep the image loaded for the process lifetime: discovered Swift
            // metadata can outlive the invocation. Never resolve or invoke main.
            guard let image = dlopen(args[2], RTLD_NOW | RTLD_GLOBAL) else {
                let detail = dlerror().map { String(cString: $0) } ?? "unknown loader error"
                throw HostFailure("could not load compiled test bundle: \(detail)")
            }
            guard let symbol = dlsym(image, "swt_abiv0_getEntryPoint") else {
                throw HostFailure("compiled test bundle has no Swift Testing ABI v0 entry point")
            }
            typealias GetEntryPoint = @convention(c) () -> UnsafeRawPointer
            let getter = unsafeBitCast(symbol, to: GetEntryPoint.self)
            let entryPoint = unsafeBitCast(getter(), to: TestEntryPoint.self)
            let application = NSApplication.shared
            if let delegate = application.delegate {
                throw HostFailure("unexpected application delegate: \(String(describing: type(of: delegate)))")
            }
            let originalPolicy = application.activationPolicy()
            if originalPolicy != .regular {
                guard application.setActivationPolicy(.regular) else {
                    throw HostFailure("regular activation policy was refused; original=\(originalPolicy.rawValue), current=\(application.activationPolicy().rawValue)")
                }
            }
            guard application.activationPolicy() == .regular else {
                throw HostFailure("owned application did not retain regular activation policy")
            }
            report("application initialized; originalPolicy=\(originalPolicy.rawValue), effectivePolicy=\(application.activationPolicy().rawValue)")
            guard let wakeEvent = NSEvent.otherEvent(with: .applicationDefined,
                location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) else {
                throw HostFailure("could not create the process-local shutdown event")
            }
            let session = TestSession(entryPoint: entryPoint, wakeEvent: wakeEvent)
            NotificationCenter.default.addObserver(session,
                selector: #selector(TestSession.didFinishLaunching(_:)),
                name: NSApplication.didFinishLaunchingNotification, object: application)
            application.run()
            NotificationCenter.default.removeObserver(session)
            guard let exitCode = session.exitCode else {
                throw HostFailure("AppKit returned before Swift Testing completed")
            }
            exit(exitCode)
        } catch {
            report(String(describing: error))
            exit(EXIT_FAILURE)
        }
    }
}
