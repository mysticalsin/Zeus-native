import AppKit
import Foundation
import Observation
import Testing
import ZeusCore
@testable import Zeus

/// Navigation/storage and presentation policies, not actual control activation or OS-consent proof.
@MainActor @Suite("Onboarding isolated policies", .serialized)
struct OnboardingIsolationTests {
    @MainActor private final class Memory {
        var step = 0
        var completed = false
        var writes: [Int] = []
        var finishes = 0
        var sounds: [OnboardingSound] = []
        var persistence: OnboardingPersistence {
            .init(readStep: { self.step }, writeStep: { self.step = $0; self.writes.append($0) },
                  readCompleted: { self.completed }, markCompleted: { self.completed = true; self.finishes += 1 })
        }
        func flow() -> OnboardingFlow {
            OnboardingFlow(persistence: persistence,
                feedback: .init(reduceMotion: { true }, isSnapshot: { false }, playSound: { self.sounds.append($0) }))
        }
    }

    @MainActor @Observable fileprivate final class Services: OnboardingServing {
        var states: [OnboardingCapability: OnboardingAccess] = [:]
        var requests: [OnboardingCapability] = []
        var polls = 0
        var stops = 0
        var refreshes = 0
        var downloads = 0
        var connections: [OnboardingFlow.AgentChoice] = []
        var modelReady = false
        var modelProgress: Double?
        var modelProblem: String?
        var connectMessage: String?
        var automationMessage: String?
        func access(_ capability: OnboardingCapability) -> OnboardingAccess { states[capability] ?? .notGranted }
        func request(_ capability: OnboardingCapability) { requests.append(capability) }
        func downloadModel() { downloads += 1 }
        func connect(_ agent: OnboardingFlow.AgentChoice) { connections.append(agent) }
        func isConnected(_ agent: OnboardingFlow.AgentChoice) -> Bool { connections.contains(agent) }
        func refresh() { refreshes += 1 }
        func startPolling() { polls += 1 }
        func stopPolling() { stops += 1 }
    }

    private func settle(_ flow: OnboardingFlow, at step: OnboardingStep) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while flow.step != step, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(flow.step == step)
    }

    @Test func nineStepsPersistAndCompletionIsExplicitAndExactlyOnce() async throws {
        let memory = Memory()
        let flow = memory.flow()
        #expect(flow.step == .welcome && !flow.completed)
        #expect(!flow.complete())
        for step in OnboardingStep.allCases.dropFirst() {
            flow.next()
            try await settle(flow, at: step)
            #expect(memory.step == step.rawValue)
            #expect(!memory.completed)
        }
        #expect(memory.writes == Array(1...8))
        #expect(flow.complete())
        #expect(!flow.complete())
        #expect(memory.completed && memory.finishes == 1)
        #expect(memory.step == OnboardingStep.welcome.rawValue)
        #expect(memory.sounds == Array(repeating: .advance, count: 8) + [.finish])
        let relaunched = memory.flow()
        #expect(relaunched.completed && relaunched.step == .welcome)
    }

    @Test func backDeferredSetupAndRelaunchPreserveProgressWithoutCompleting() async throws {
        let memory = Memory()
        let first = memory.flow()
        first.next()
        try await settle(first, at: .murmure)
        first.next() // Same route used by Set up later; no permission service is involved.
        try await settle(first, at: .agents)
        first.back()
        try await settle(first, at: .murmure)
        first.cancelPendingTransition()
        let resumed = memory.flow()
        #expect(resumed.step == .murmure)
        #expect(!resumed.completed && memory.finishes == 0)
        #expect(memory.sounds == [.advance, .advance])
        resumed.restart()
        #expect(memory.step == 0 && !memory.completed)
    }

    @Test func closingBeforeQueuedNavigationCannotAdvanceOrFinishLater() async throws {
        let memory = Memory()
        let flow = memory.flow()
        let services = Services()
        let controller = OnboardingWindowController(services: services, flow: flow, options: OnboardingOptions())
        #expect(controller.debugWindow == nil)
        #expect(services.polls == 0 && services.refreshes == 0)
        flow.next()
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        try await Task.sleep(for: .milliseconds(20))
        #expect(flow.step == .welcome && memory.writes.isEmpty && memory.finishes == 0)
        #expect(services.stops == 1)
        #expect(services.requests.isEmpty && services.connections.isEmpty && services.downloads == 0)
    }

    @Test func invalidResumeStepFallsBackAndReducedMotionStartsAwake() async {
        let memory = Memory()
        memory.step = 500
        let flow = memory.flow()
        #expect(flow.step == .welcome)
        #expect(flow.reducesMotion)
        #expect(flow.mascotPose == OnboardingStep.welcome.mascotPose(wake: .awake))
        await flow.playWake()
        #expect(memory.writes.isEmpty && memory.sounds.isEmpty)
    }

    @Test func deniedAccessOffersRecoveryAndAuthorizedAccessOffersNoRequest() {
        #expect(OnboardingAccess.notGranted.actionTitle == "Allow")
        #expect(OnboardingAccess.notGranted.recovery == nil)
        #expect(OnboardingAccess.denied.actionTitle == "Open Settings")
        #expect(OnboardingAccess.denied.recovery?.contains("set up later") == true)
        #expect(OnboardingAccess.allowed.actionTitle == nil)
        #expect(OnboardingAccess.allowed.recovery == nil)
    }

    @Test func reopeningCompletedPresentationAllowsAnotherExplicitFinish() async throws {
        let memory = Memory()
        memory.step = OnboardingStep.sounds.rawValue
        let flow = memory.flow()
        #expect(flow.complete())
        #expect(!flow.complete())
        flow.beginPresentation() // The same controller's show(restart: false), retaining its current step.
        #expect(flow.step == .welcome && flow.completed)
        flow.go(.sounds)
        try await settle(flow, at: .sounds)
        #expect(flow.complete())
        #expect(!flow.complete())
        #expect(memory.finishes == 2)
    }

    @Test func explicitMotionPolicyNeverOverridesSystemReduction() {
        #expect(OnboardingMotionPolicy.reduced(system: true, override: false))
        #expect(OnboardingMotionPolicy.reduced(system: false, override: true))
        #expect(OnboardingMotionPolicy.reduced(system: true, override: nil))
        #expect(!OnboardingMotionPolicy.reduced(system: false, override: nil))
    }

    @Test func bundledTypographyAndMascotAreRequiredForNativePresentation() throws {
        let bundle = try #require(ZeusResources.bundle,
            "The actual app resource bundle must accompany native fixtures. \(ZeusResources.lookupDescription)")
        let fontURL = try #require(bundle.url(forResource: "PlusJakartaSans", withExtension: "ttf", subdirectory: "Fonts"))
        #expect(FileManager.default.fileExists(atPath: fontURL.path))
        // The production registrar uses CoreText .process; it never installs in Font Book or writes preferences.
        GlassFonts.register()
        #expect(GlassFonts.registered)
        let face = try #require(NSFont(name: "PlusJakartaSans-Regular", size: 34), "Do not accept a system-font fallback")
        #expect(face.familyName == GlassFonts.family)
        #expect(OB.title == OB.display(34))
        let directory = try #require(bundle.url(forResource: "Anim", withExtension: nil))
        let sprites = MascotAtlasStore(directory: directory)
        for step in OnboardingStep.allCases {
            let pose = step.mascotPose(wake: .awake)
            #expect(sprites.frame(pose.clipID, elapsed: 0, points: 112, pixelScale: 2) != nil, "Missing shipped mascot: \(pose.clipID)")
        }
        for film in OnboardingFilm.allCases {
            let url = try #require(film.url)
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing shipped film: \(film.rawValue)")
        }
    }

    @Test func resourceLookupAddsOnlyExplicitLoadedTestBundleSiblings() {
        let app = URL(fileURLWithPath: "/synthetic/Applications/Zeus.app")
        let executable = app.appendingPathComponent("Contents/MacOS/Zeus")
        let resources = app.appendingPathComponent("Contents/Resources")
        let production = ZeusResources.candidateURLs(resourceURL: resources, executableURL: executable,
            mainBundleURL: app, moduleBundleURL: app)
        #expect(production.first == resources.appendingPathComponent("Zeus_Zeus.bundle"))
        #expect(!production.contains(app.deletingLastPathComponent().appendingPathComponent("Zeus_Zeus.bundle")))
        let test = URL(fileURLWithPath: "/synthetic/build/debug/ZeusPackageTests.xctest")
        let sibling = test.deletingLastPathComponent().appendingPathComponent("Zeus_Zeus.bundle")
        let hosted = ZeusResources.candidateURLs(resourceURL: nil, executableURL: nil,
            mainBundleURL: app, moduleBundleURL: test)
        #expect(hosted.last == sibling)
        let sameHost = ZeusResources.candidateURLs(resourceURL: nil, executableURL: nil,
            mainBundleURL: test, moduleBundleURL: test)
        #expect(sameHost.filter { $0 == sibling }.count == 1)
        #expect(!hosted.contains(where: { $0.path.contains("Sources") }))
    }

    @Test func optionsStayIndependentAndSoundOffPreventsPreviewDispatch() {
        var played: [ZeusSound.Event] = []
        let options = OnboardingOptions(values: ["sound.on": "false"], talkKey: "Fixture key", preview: { played.append($0) })
        let other = OnboardingOptions()
        options.preview(.done)
        #expect(played.isEmpty)
        options.boolBinding("sound.on").wrappedValue = true
        options.binding("appearance.cardStyle").wrappedValue = "Physical"
        options.preview(.done)
        #expect(played.count == 1)
        #expect(options.talkKey == "Fixture key")
        #expect(options.string("appearance.cardStyle") == "Physical")
        #expect(other.string("appearance.cardStyle") == "Liquid Glass")
        options.set("halo.thickness", "nan")
        #expect(options.double("halo.thickness") == 0)
        options.haloStyleTitle.wrappedValue = HaloStyle.classic.title
        #expect(options.string("halo.style") == HaloStyle.classic.rawValue)
    }
}
