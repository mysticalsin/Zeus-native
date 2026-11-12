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
        var dismissed = false
        var dismissals = 0
        var writes: [Int] = []
        var finishes = 0
        var sounds: [OnboardingSound] = []
        var persistence: OnboardingPersistence {
            .init(readStep: { self.step }, writeStep: { self.step = $0; self.writes.append($0) },
                  readCompleted: { self.completed }, markCompleted: { self.completed = true; self.finishes += 1 },
                  readDismissed: { self.dismissed }, markDismissed: { self.dismissed = true; self.dismissals += 1 })
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
        #expect(memory.writes == Array(1...9))
        #expect(flow.complete())
        #expect(!flow.complete())
        #expect(memory.completed && memory.finishes == 1)
        #expect(memory.step == OnboardingStep.welcome.rawValue)
        #expect(memory.sounds == Array(repeating: .advance, count: 9) + [.finish])
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
        #expect(services.stops == 0) // A controller that never appeared owns no poller to stop.
        #expect(services.requests.isEmpty && services.connections.isEmpty && services.downloads == 0)
    }

    @Test func closingTheWindowMidwayRecordsADismissalOnceAndLaunchStopsReopening() async throws {
        let memory = Memory()
        let flow = memory.flow()
        let controller = OnboardingWindowController(services: Services(), flow: flow, options: OnboardingOptions())
        flow.beginPresentation()
        flow.next()
        try await settle(flow, at: .murmure)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(memory.dismissed && memory.dismissals == 1 && !memory.completed)
        let relaunched = memory.flow()
        #expect(relaunched.progress == .dismissed)
        #expect(!OnboardingProgress.opensAtLaunch(relaunched.progress, explicitStepRequested: false))
    }

    @Test func setUpLaterOnTheLastStepDismissesAndOnAMiddleStepOnlySkips() async throws {
        let memory = Memory()
        let flow = memory.flow()
        flow.beginPresentation()
        flow.skipStep()
        try await settle(flow, at: .murmure)
        #expect(!memory.dismissed)
        flow.step = .sounds
        flow.skipStep()
        #expect(memory.dismissed && memory.dismissals == 1 && flow.step == .sounds)
    }

    @Test func finishingThenClosingTheWindowStaysCompletedNotDismissed() async throws {
        let memory = Memory()
        let flow = memory.flow()
        let controller = OnboardingWindowController(services: Services(), flow: flow, options: OnboardingOptions())
        flow.beginPresentation()
        flow.step = .sounds
        #expect(flow.complete())
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(memory.completed && !memory.dismissed)
        #expect(flow.progress == .completed)
    }

    @Test func pollingVisibilityPolicyPausesForHiddenMinimizedOccludedAndClosedWindows() {
        // Pure visibility policy, not proof of AppKit notification delivery or actual controls.
        #expect(OnboardingPollingPolicy.shouldPoll(presented: true, windowVisible: true,
            miniaturized: false, appHidden: false, occluded: false))
        #expect(!OnboardingPollingPolicy.shouldPoll(presented: false, windowVisible: true,
            miniaturized: false, appHidden: false, occluded: false))
        #expect(!OnboardingPollingPolicy.shouldPoll(presented: true, windowVisible: false,
            miniaturized: false, appHidden: false, occluded: false))
        #expect(!OnboardingPollingPolicy.shouldPoll(presented: true, windowVisible: true,
            miniaturized: true, appHidden: false, occluded: false))
        #expect(!OnboardingPollingPolicy.shouldPoll(presented: true, windowVisible: true,
            miniaturized: false, appHidden: true, occluded: false))
        #expect(!OnboardingPollingPolicy.shouldPoll(presented: true, windowVisible: true,
            miniaturized: false, appHidden: false, occluded: true))
    }

    @Test func pollingOwnerStartsOncePerVisibleIntervalAndResumesWithoutActions() {
        // Synthetic service ownership test; no window, live permission service or OS action.
        let services = Services()
        let polling = OnboardingPollingLifecycle(services: services)
        polling.setVisible(false)
        #expect(services.polls == 0 && services.stops == 0)
        for _ in 0..<3 {
            polling.setVisible(true)
            polling.setVisible(true)
            #expect(polling.isPolling)
            polling.setVisible(false)
            polling.setVisible(false)
            #expect(!polling.isPolling)
        }
        #expect(services.polls == 3 && services.stops == 3)
        #expect(services.refreshes == 0 && services.requests.isEmpty)
        #expect(services.connections.isEmpty && services.downloads == 0)
    }

    @Test func pollingOwnerTeardownStopsAnActiveIntervalExactlyOnce() {
        let services = Services()
        var polling: OnboardingPollingLifecycle? = OnboardingPollingLifecycle(services: services)
        weak var released = polling
        polling?.setVisible(true)
        polling = nil
        #expect(released == nil)
        #expect(services.polls == 1 && services.stops == 1)
        var stopped: OnboardingPollingLifecycle? = OnboardingPollingLifecycle(services: services)
        stopped?.setVisible(true)
        stopped?.setVisible(false)
        stopped = nil
        #expect(services.polls == 2 && services.stops == 2)
        #expect(services.requests.isEmpty && services.connections.isEmpty && services.downloads == 0)
    }

    @Test func pollingFollowsOwnWindowMiniaturizeRestoreAndCloseWithoutActions() async throws {
        // Native own-window/delegate lifecycle, not button activation or OS-consent proof.
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let memory = Memory()
            let services = Services()
            let controller = OnboardingWindowController(services: services, flow: memory.flow(), options: OnboardingOptions())
            controller.show()
            let window = try #require(controller.debugWindow)
            defer { OwnedWindowFixtureApplication.close(window) }

            try await settlePolling { window.isVisible && !window.isMiniaturized && services.polls == 1 }
            controller.show()
            #expect(services.polls == 1 && services.stops == 0)
            window.miniaturize(nil)
            try await settlePolling { window.isMiniaturized && services.stops == 1 }
            #expect(services.polls == 1)
            window.deminiaturize(nil)
            try await settlePolling { !window.isMiniaturized && services.polls == 2 }
            #expect(services.stops == 1)
            controller.close()
            try await settlePolling { !window.isVisible && services.stops == 2 }
            #expect(services.polls == 2)
            #expect(services.requests.isEmpty && services.connections.isEmpty && services.downloads == 0)
            #expect(memory.writes.isEmpty && memory.finishes == 0)
        }
    }

    private func settlePolling(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition(), "The native host did not deliver the expected owned-window polling transition")
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
        // Completion is terminal and recorded once (OnboardingProgress); the second finish still closes the guide.
        #expect(memory.finishes == 1 && flow.completed)
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
