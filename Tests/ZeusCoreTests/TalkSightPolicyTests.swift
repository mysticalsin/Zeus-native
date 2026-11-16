import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkSightPolicyTests {
    private static let shots = [
        ScreenShot(jpegData: Data([1]), label: "screen 1 of 2", pixelWidth: 1280, pixelHeight: 800,
                   displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
        ScreenShot(jpegData: Data([2]), label: "screen 2 of 2", pixelWidth: 1000, pixelHeight: 600,
                   displayFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
    ]

    private func plan(see: Bool = true, draw: Bool = false, restricted: Bool = false, page: Bool = false,
                      textEnough: Bool = false, shots: [ScreenShot] = TalkSightPolicyTests.shots) -> TalkSightPolicy.Plan {
        TalkSightPolicy.plan(seeScreen: see, drawConsent: draw, restricted: restricted, pageRoute: page,
                             textAnswersIt: textEnough, captured: shots)
    }

    @Test func seeingTheScreenSendsEveryDisplayToTheImageProviderWithoutDrawing() {
        let p = plan(see: true, draw: false)
        #expect(p.keptCount == 2)
        #expect(p.requestLabels == ["screen 1 of 2", "screen 2 of 2"])
        #expect(p.sendsImages)
        #expect(!p.drawing)
    }

    @Test func seeingTheScreenOffAndDrawingOffKeepsTheOldTextRoute() {
        let p = plan(see: false, draw: false)
        #expect(p.requestLabels.count == 2)
        #expect(!p.sendsImages)
        #expect(!p.drawing)
    }

    @Test func seeingTheScreenKeepsPixelsEvenWhenWindowTextAlreadyAnswers() {
        #expect(plan(see: true, textEnough: true).keptCount == 2)
        #expect(plan(see: true, textEnough: true).sendsImages)
        #expect(plan(see: false, textEnough: true).keptCount == 0)
    }

    @Test func drawingStillCutsTheRequestToTheCursorDisplayWhetherOrNotTheScreenIsSeen() {
        for see in [true, false] {
            let p = plan(see: see, draw: true)
            #expect(p.drawing, "see \(see)")
            #expect(p.sendsImages, "see \(see)")
            #expect(p.requestLabels == ["screen 1 of 2"], "see \(see)")
            #expect(p.keptCount == 2, "POINT screenN and drive keep every capture")
        }
    }

    @Test func drawingWithoutSeeingTheScreenNeverDrawsOnNothing() {
        let p = plan(see: false, draw: true, shots: [])
        #expect(!p.drawing && !p.sendsImages && p.requestLabels.isEmpty)
    }

    @Test func restrictedAndPageRouteTurnsStayImageFreeEvenWhenSeeingIsOn() {
        for p in [plan(see: true, draw: true, restricted: true), plan(see: true, draw: true, page: true)] {
            #expect(p.keptCount == 0)
            #expect(p.requestLabels.isEmpty)
            #expect(!p.sendsImages && !p.drawing)
        }
    }

    @Test func noCapturesMeansNoImageRouteEvenWhenSeeingIsOn() {
        let p = plan(see: true, shots: [])
        #expect(!p.sendsImages && p.keptCount == 0)
    }

    @Test func theAnthropicApiEngineIsTextOnlySoItNeverDraws() {
        #expect(TalkDrawPolicy.accepts(winner: "claude"))
        #expect(!TalkDrawPolicy.accepts(winner: "anthropic-api"))
    }

    @Test func seeScreenDefaultsOnAndIsSeparateFromDrawOnScreen() {
        let name = NSTemporaryDirectory() + "talk.seeScreen.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(FeatureSettings.talkSeeScreen(defaults: defaults))
        #expect(!FeatureSettings.talkDrawOnScreen(defaults: defaults))
        defaults.set("false", forKey: FeatureSettings.key("talk.seeScreen"))
        #expect(!FeatureSettings.talkSeeScreen(defaults: defaults))
        defaults.set("true", forKey: FeatureSettings.key("talk.drawOnScreen"))
        #expect(FeatureSettings.talkDrawOnScreen(defaults: defaults))
        #expect(!FeatureSettings.talkSeeScreen(defaults: defaults))
    }
}

@Suite struct ScreenSightNoteTests {
    @Test func attachedScreensAreListedAndNeverCalledOff() {
        let text = ScreenSightNote.line(labels: ["screen 1 of 2", "screen 2 of 2"], reason: nil)
        #expect(text.contains("Screenshots attached"))
        #expect(text.contains("- screen 1 of 2") && text.contains("- screen 2 of 2"))
        #expect(!text.lowercased().contains("permission"))
        #expect(!text.contains("No screenshots"))
    }

    @Test func permissionOffTellsTheModelItCannotSeeAndWhy() {
        let text = ScreenSightNote.line(labels: [], reason: .permissionOff)
        #expect(text.contains("No screenshots"))
        #expect(text.contains("Screen Recording permission is off"))
        #expect(text.contains("cannot see the screen"))
        #expect(text.contains("[POINT:none]"))
    }

    @Test func notCapturedThisTurnDoesNotBlameThePermission() {
        for reason in [ScreenSightReason.notCaptured, nil] {
            let text = ScreenSightNote.line(labels: [], reason: reason)
            #expect(text.contains("No screenshots"), "\(String(describing: reason))")
            #expect(text.contains("cannot see the screen"), "\(String(describing: reason))")
            #expect(!text.lowercased().contains("permission"), "\(String(describing: reason))")
        }
    }

    @Test func theScreenReasonSurvivesACopyOfTheRequest() {
        let request = BrainRequest(transcript: "x", systemPrompt: "s", screenReason: .permissionOff)
        #expect(request.screenReason == .permissionOff)
        #expect(request.with(deep: true, firstTextBudget: 8).screenReason == .permissionOff)
        #expect(BrainRequest(transcript: "x", systemPrompt: "s").screenReason == nil)
    }
}

@Suite struct TextOnlyEngineSightTests {
    private let shot = ScreenShot(jpegData: Data([1]), label: "screen 1 of 1", pixelWidth: 10, pixelHeight: 10, displayFrame: .zero)

    @Test func aTextOnlyEngineIsToldItCannotSeeEvenWhenScreenshotsRideTheRequest() {
        let request = BrainRequest(transcript: "what is this", screenshots: [shot], systemPrompt: "SYS")
        let prompt = ScreenSightNote.textOnlySystemPrompt(for: request)
        #expect(prompt.hasPrefix("SYS"))
        #expect(prompt.contains("you cannot see the screen"))
        #expect(!prompt.contains("Screenshots attached"))
    }

    @Test func aSpokenTurnWithNoCaptureIsToldTheSameToATextOnlyEngine() {
        let spoken = BrainRequest(transcript: "hi", systemPrompt: "SYS", firstTextBudget: 8)
        #expect(ScreenSightNote.textOnlySystemPrompt(for: spoken).contains("you cannot see the screen"))
        let blocked = BrainRequest(transcript: "hi", systemPrompt: "SYS", screenReason: .permissionOff)
        #expect(ScreenSightNote.textOnlySystemPrompt(for: blocked).contains("you cannot see the screen"))
    }

    @Test func aPlainChatRequestKeepsItsSystemPromptAsWritten() {
        let chat = BrainRequest(transcript: "hi", systemPrompt: "SYS")
        #expect(ScreenSightNote.textOnlySystemPrompt(for: chat) == "SYS")
    }
}

@Suite struct ScreenSightNoticeTests {
    @Test func theFirstTurnWithoutPermissionGetsOnePlainNotice() {
        var notice = ScreenSightNotice()
        let text = notice.take(permissionGranted: false)
        #expect(text == ScreenSightNotice.message)
        #expect(text?.contains("can't see your screen") == true)
        #expect(text?.contains("Screen Recording") == true)
        #expect(text?.contains("System Settings") == true)
        #expect(text?.contains("Privacy") == true)
        #expect(text?.contains("\u{2014}") == false && text?.contains("\u{2013}") == false)
    }

    @Test func laterTurnsWithoutPermissionStayQuietForTheRestOfTheLaunch() {
        var notice = ScreenSightNotice()
        _ = notice.take(permissionGranted: false)
        for _ in 0..<5 { #expect(notice.take(permissionGranted: false) == nil) }
    }

    @Test func grantedTurnsNeverGetANoticeAndDoNotUseItUp() {
        var notice = ScreenSightNotice()
        #expect(notice.take(permissionGranted: true) == nil)
        #expect(notice.take(permissionGranted: true) == nil)
        #expect(notice.take(permissionGranted: false) == ScreenSightNotice.message)
        #expect(notice.take(permissionGranted: false) == nil)
    }

    @Test func aFreshLaunchGetsItsOwnNotice() {
        var first = ScreenSightNotice(), second = ScreenSightNotice()
        #expect(first.take(permissionGranted: false) != nil)
        #expect(second.take(permissionGranted: false) != nil)
    }
}
