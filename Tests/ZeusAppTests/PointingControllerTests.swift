import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Production controller, synthetic services. No microphone, screen capture, key tap, provider
/// request, installed voice or sound.
@MainActor
@Suite("Pointing controller with synthetic services", .serialized)
struct PointingControllerTests {
    @MainActor private final class Calls {
        var begins = 0, finishes = 0, cancels = 0, providerRequests = 0, idles = 0, captures = 0
        var notices: [PointingNotice] = []
    }

    @MainActor private final class Provider: ExplanationModelProviding {
        let calls: Calls
        init(_ calls: Calls) { self.calls = calls }
        func respond(_ request: ExplanationModelRequest,
                     receive: @escaping @MainActor (ExplanationEvent) async throws -> Void) async throws {
            calls.providerRequests += 1
            throw ExplanationProviderError.notConfigured
        }
    }

    @MainActor private final class Speech: SpeechOutputProvider {
        func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
            throw ExplanationAudioError.unavailable
        }
    }

    private func make(permission: Bool = false, enabled: Bool = true, draw: Bool = true) -> (PointingController, Calls) {
        let calls = Calls()
        let context = ExplanationScreenContext(services: ExplanationScreenServices(
            hasPermission: { permission },
            identity: { _ in throw ExplanationScreenContextFailure.unavailable },
            capture: { _ in calls.captures += 1; throw ExplanationScreenContextFailure.unavailable },
            monotonicNow: { 10 },
            observeChanges: { _ in nil },
            observeTime: { _ in ExplanationScreenObservation {} }))
        let explanation = ExplanationController(provider: Provider(calls), speechProvider: Speech(),
                                                microphone: ExplanationMicrophone(acquire: {}, release: {}),
                                                screenContext: context, acquireAudio: {}, releaseAudio: {})
        var services = PointingController.Services()
        services.now = { 10 }
        services.mouseLocation = { CGPoint(x: 100, y: 100) }
        services.displays = { [PointingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)] }
        services.hasScreenPermission = { permission }
        services.frontmostBundleID = { nil }
        services.probe = { _ in nil }
        services.focusedInput = { nil }
        services.enabled = { enabled }
        services.sendScreenshot = { false }
        services.drawWhileHeld = { draw }
        let inputs = PointingController.Inputs(begin: { calls.begins += 1; return UUID() },
                                               finish: { _ in calls.finishes += 1 }, cancel: { _ in calls.cancels += 1 })
        let marker = PointingController.Marker(listen: {}, think: {}, idle: { calls.idles += 1 }, flight: { _, _ in true })
        let controller = PointingController(explanation: explanation, services: services, inputs: inputs, marker: marker,
                                            prepare: { [.zeusSetup] })
        controller.onNotice = { calls.notices.append($0) }
        return (controller, calls)
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func spoilCancelsWithoutSendingARequest() async {
        let (controller, calls) = make()
        controller.handle(.began)
        #expect(controller.state == .listening)
        controller.handle(.cancelled)
        #expect(controller.state == .idle)
        #expect(calls.finishes == 0 && calls.providerRequests == 0 && calls.cancels == 1)
        await settle { controller.leaks.isEmpty }
        #expect(controller.leaks.isEmpty)
    }

    @Test func aSecondHoldWhileHoldingStartsNoSecondSession() {
        let (controller, calls) = make()
        controller.handle(.began); controller.handle(.began)
        #expect(calls.begins == 1)
        controller.handle(.cancelled)
    }

    @Test func deniedScreenRecordingShowsOneNoticeAndNeverCaptures() async {
        let (controller, calls) = make(permission: false)
        controller.handle(.began)
        await settle { !calls.notices.isEmpty }
        controller.handle(.cancelled)
        controller.handle(.began)
        await settle { controller.metrics.captureAttempts >= 0 && calls.begins == 2 }
        controller.handle(.cancelled)
        let permission = calls.notices.compactMap { notice -> String? in
            if case .permission(_, let pane) = notice { return pane } else { return nil }
        }
        #expect(permission == ["Privacy_ScreenCapture"], "one notice, not a loop")
        #expect(calls.captures == 0 && controller.metrics.captureAttempts == 0)
    }

    @Test func drawWhileHeldTakesTheMouseAndReleasingGivesItBack() async {
        let (controller, _) = make(draw: true)
        controller.handle(.began)
        #expect(MarkOverlay.shared.capturesMouse, "drags are ink while the keys are held")
        controller.handle(.cancelled)
        await settle { controller.leaks.isEmpty }
        #expect(!MarkOverlay.shared.capturesMouse)
        #expect(controller.leaks.isEmpty)
    }

    @Test func withDrawWhileHeldOffTheMouseStaysWithTheApps() async {
        let (controller, calls) = make(draw: false)
        controller.handle(.began)
        #expect(controller.state == .listening && calls.begins == 1, "the hold still listens")
        #expect(!MarkOverlay.shared.capturesMouse, "no ink overlay, clicks reach the apps")
        controller.handle(.cancelled)
        await settle { controller.leaks.isEmpty }
        #expect(controller.leaks.isEmpty)
    }

    @Test func theHoldIsIgnoredWhileTheSettingIsOff() {
        let (controller, calls) = make(enabled: false)
        controller.handle(.began)
        #expect(controller.state == .idle && calls.begins == 0)
    }

    @Test func escapeWhileIdleDoesNothing() {
        let (controller, calls) = make()
        controller.handle(.escape)
        #expect(controller.state == .idle && calls.idles == 0)
    }

    @Test func noticesNeverUseAnEmDash() async {
        let (controller, calls) = make(permission: false)
        controller.handle(.began)
        await settle { !calls.notices.isEmpty }
        controller.handle(.cancelled)
        for notice in calls.notices {
            switch notice {
            case .hint(let text), .permission(let text, _): #expect(!text.contains("—"))
            }
        }
    }
}
