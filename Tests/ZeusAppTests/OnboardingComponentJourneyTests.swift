import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
@testable import Zeus

/// Actual production Setup-card and guide controls, using own-window pointer events and inert
/// services. This is not full Settings/AppDelegate routing, keyboard, AX, OS-consent or motion proof.
@MainActor @Suite("Onboarding native component journey", .serialized)
struct OnboardingComponentJourneyTests {
    @MainActor private final class Memory {
        var step = OnboardingStep.welcome.rawValue
        var completed = false
        var writes: [Int] = []
        var completions = 0
        var openActions = 0
        var finishCallbacks = 0
        var cues: [OnboardingSound] = []
        var previews = 0

        var persistence: OnboardingPersistence {
            .init(readStep: { self.step },
                  writeStep: { self.step = $0; self.writes.append($0) },
                  readCompleted: { self.completed },
                  markCompleted: { self.completed = true; self.completions += 1 })
        }
    }

    /// No live permission model, polling task, provider, download or sound service is constructed.
    // Observable emits a file-scope conformance extension; a nested private type is inaccessible there.
    @MainActor @Observable fileprivate final class Services: OnboardingServing {
        var states: [OnboardingCapability: OnboardingAccess] = [:]
        var requests: [OnboardingCapability] = []
        var downloads = 0
        var connections: [OnboardingFlow.AgentChoice] = []
        var refreshes = 0
        var pollingStarts = 0
        var pollingStops = 0
        var modelReady = false
        var modelProgress: Double?
        var modelProblem: String?
        var connectMessage: String?
        var automationMessage: String?

        func access(_ capability: OnboardingCapability) -> OnboardingAccess { states[capability] ?? .notGranted }
        func request(_ capability: OnboardingCapability) { requests.append(capability) }
        func downloadModel() { downloads += 1 }
        func connect(_ agent: OnboardingFlow.AgentChoice) { connections.append(agent) }
        func isConnected(_ agent: OnboardingFlow.AgentChoice) -> Bool { false }
        func refresh() { refreshes += 1 }
        func startPolling() { pollingStarts += 1 }
        func stopPolling() { pollingStops += 1 }
    }

    @MainActor private struct Fixture {
        let memory: Memory
        let services: Services
        let flow: OnboardingFlow
        let guide: OnboardingWindowController
        let setupWindow: NSWindow
        let registry: OwnedWindowControlRegistry
        let driver: OwnedWindowEventDriver
        let requestedReduction: Bool

        func waitFor(_ description: String, _ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while !condition(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(condition(), "Owned onboarding fixture did not reach: \(description)")
        }

        func openGuide() async throws -> NSWindow {
            #expect(guide.debugWindow == nil && memory.openActions == 0)
            try await driver.click("settings.general.openGuide", in: setupWindow)
            try await waitFor("visible production guide") { guide.debugWindow?.isVisible == true }
            let window = try #require(guide.debugWindow)
            driver.register(window)
            #expect(memory.openActions == 1)
            #expect(flow.step == .welcome && memory.writes == [0])
            #expect(!memory.completed && memory.completions == 0 && memory.finishCallbacks == 0)
            return window
        }

        func navigate(_ control: String, to step: OnboardingStep, in window: NSWindow) async throws {
            try await driver.click(control, in: window)
            try await waitFor("\(step) with its current footer") {
                let next = step == .sounds ? "onboarding.finish" : "onboarding.next"
                return window.isVisible && flow.step == step && memory.step == step.rawValue
                    && registry.probes(for: next, in: window).count == 1
            }
            #expect(!memory.completed && memory.completions == 0 && memory.finishCallbacks == 0)
        }

        func requireNoBackgroundActions() {
            #expect(services.requests.isEmpty)
            #expect(services.downloads == 0 && services.connections.isEmpty && memory.previews == 0)
        }
    }

    private func withFixture(requestedReduction: Bool, microphone: OnboardingAccess = .notGranted,
                             operation: @MainActor (Fixture) async throws -> Void) async throws {
        try await OwnedWindowJourneyLease.perform {
            let originalPolicy = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(originalPolicy) }
            try #require(!TopBarStyle.isSnapshot, "This journey must use live production controls")
            GlassFonts.register() // Process-scoped bundled typography, as at production launch.
            try #require(GlassFonts.registered, "The guide must not silently use a fallback font")
            let memory = Memory(), services = Services(), registry = OwnedWindowControlRegistry()
            services.states[.microphone] = microphone
            let flow = OnboardingFlow(persistence: memory.persistence,
                feedback: .init(reduceMotion: { requestedReduction || OnboardingTransition.reduceMotion },
                                isSnapshot: { false }, playSound: { memory.cues.append($0) }))
            let options = OnboardingOptions(preview: { _ in memory.previews += 1 })
            let guide = OnboardingWindowController(services: services, flow: flow, options: options,
                                                   journeyRegistry: registry)
            guide.onFinish = { memory.finishCallbacks += 1 }
            let root = GSSetupCard {
                memory.openActions += 1
                guide.show(restart: true)
            }
            .padding(24)
            .frame(width: 720, height: 180)
            .environment(\.ownedWindowControlRegistry, registry)
            let setupWindow = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 720, height: 180),
                                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
            setupWindow.title = "Synthetic production Setup card"
            setupWindow.isReleasedWhenClosed = false
            setupWindow.contentView = NSHostingView(rootView: root)
            defer {
                // Teardown may close directly; no asserted user action uses these calls.
                flow.cancelPendingTransition()
                guide.onFinish = nil
                if let window = guide.debugWindow { OwnedWindowFixtureApplication.close(window) }
                OwnedWindowFixtureApplication.close(setupWindow)
            }
            setupWindow.makeKeyAndOrderFront(nil)
            let driver = OwnedWindowEventDriver(registry: registry)
            driver.register(setupWindow)
            let fixture = Fixture(memory: memory, services: services, flow: flow, guide: guide,
                                  setupWindow: setupWindow, registry: registry, driver: driver,
                                  requestedReduction: requestedReduction)
            #expect(services.pollingStarts == 0 && services.pollingStops == 0)
            try await operation(fixture)
        }
    }

    @Test(arguments: [false, true])
    func setupCardOpensGuideAndDeferredStepsFinishOnce(requestedReduction: Bool) async throws {
        try await withFixture(requestedReduction: requestedReduction) { fixture in
            let window = try await fixture.openGuide()
            fixture.requireNoBackgroundActions()
            try await fixture.navigate("onboarding.start", to: .murmure, in: window)
            try await fixture.navigate("onboarding.skip", to: .agents, in: window)
            try await fixture.navigate("onboarding.back", to: .murmure, in: window)
            try await fixture.navigate("onboarding.next", to: .agents, in: window)
            for step in [OnboardingStep.control, .reach, .day, .theme, .halo, .languages, .sounds] {
                try await fixture.navigate("onboarding.skip", to: step, in: window)
                fixture.requireNoBackgroundActions()
            }
            #expect(fixture.memory.writes == [0, 1, 2, 1, 2, 3, 4, 5, 6, 7, 8, 9])
            try await fixture.driver.click("onboarding.finish", in: window)
            try await fixture.waitFor("completed guide closed") {
                !window.isVisible && fixture.memory.completed && fixture.memory.finishCallbacks == 1
            }
            #expect(fixture.memory.completions == 1)
            #expect(fixture.memory.writes == [0, 1, 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
            #expect(fixture.flow.step == .welcome)
            #expect(fixture.memory.cues == Array(repeating: .advance, count: 10) + [.finish])
            #expect(fixture.services.pollingStops == fixture.services.pollingStarts)
            fixture.requireNoBackgroundActions()
            print("Owned onboarding pointer journey finished: requestedReduction=\(fixture.requestedReduction), " +
                  "effectiveReduction=\(fixture.flow.reducesMotion); Setup card → ten steps with Back/defer → Finish. " +
                  "No keyboard, AX, permission, temporal or full-Settings acceptance is inferred.")
        }
    }

    @Test func deniedRecoveryCallsOnlyInertServiceAndStillAllowsSkip() async throws {
        try await withFixture(requestedReduction: true, microphone: .denied) { fixture in
            let window = try await fixture.openGuide()
            try await fixture.navigate("onboarding.start", to: .murmure, in: window)
            fixture.requireNoBackgroundActions()
            try await fixture.driver.click("onboarding.permission.microphone", in: window)
            try await fixture.waitFor("one inert recovery request") { fixture.services.requests == [.microphone] }
            #expect(fixture.services.access(.microphone) == .denied)
            #expect(fixture.flow.step == .murmure && !fixture.memory.completed)
            #expect(fixture.services.downloads == 0 && fixture.services.connections.isEmpty && fixture.memory.previews == 0)
            try await fixture.navigate("onboarding.skip", to: .agents, in: window)
            #expect(fixture.services.requests == [.microphone])
            #expect(fixture.memory.writes == [0, 1, 2])
            #expect(fixture.memory.finishCallbacks == 0 && fixture.memory.completions == 0)
            print("Owned onboarding denied-state pointer journey deferred setup; only the inert microphone service was requested.")
        }
    }
}
