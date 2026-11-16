import CoreGraphics
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// One shared, ordered log of what the turn asked of the voice and of the drawing.
@MainActor
private final class TurnLog {
    var events: [String] = []
}

@MainActor
private final class FakeSpeaker: LineSpeaking {
    let log: TurnLog
    init(_ log: TurnLog) { self.log = log }
    var isSpeaking: Bool { false }
    var engineDescription: String { "fake" }
    func stop() {}
    func speak(_ text: String, onStart: (@MainActor () -> Void)?) {
        log.events.append("line \(text)")
        onStart?()
    }
}

@MainActor
private final class FakePresenter: TalkVisualPresenting {
    let log: TurnLog
    init(_ log: TurnLog) { self.log = log }
    func begin(_ draw: TalkDraw, shot: ScreenShot, token: UUID) { log.events.append("begin marks=\(draw.marks.count) w=\(shot.pixelWidth)") }
    func reveal(sentence: Int, token: UUID) { log.events.append("reveal \(sentence)") }
    func answerFinished(token: UUID) { log.events.append("finished") }
    func clear() { log.events.append("clear") }
}

@MainActor
@Suite("Talk turn drawing", .serialized)
struct TalkVisualTurnTests {
    private static let shots = [
        ScreenShot(jpegData: Data([1]), label: "screen 1", pixelWidth: 1280, pixelHeight: 800,
                   displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
        ScreenShot(jpegData: Data([2]), label: "screen 2", pixelWidth: 1000, pixelHeight: 600,
                   displayFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
    ]

    private static let reply = #"[DRAW:{"s":1,"m":[{"k":"ring","x":412,"y":88,"r":24,"at":0},{"k":"card","x":440,"y":120,"t":"Export","at":1}]}]"#
        + " Open the File menu. Choose Export as PDF. Then save it."

    private func controller(consent: Bool, log: TurnLog) -> VoiceTurnController {
        VoiceTurnController(buddy: BuddyController(), notch: NotchController(), brain: ClaudeCLIProvider(),
                            speaker: FakeSpeaker(log), presenter: FakePresenter(log), drawConsent: { consent })
    }

    private func run(_ controller: VoiceTurnController, winner: String, sighted: Bool = true) async -> TurnResult {
        let events = AsyncThrowingStream<BrainEvent, Error> { continuation in
            for chunk in stride(from: 0, to: Self.reply.count, by: 11) {
                let from = Self.reply.index(Self.reply.startIndex, offsetBy: chunk)
                let to = Self.reply.index(from, offsetBy: 11, limitedBy: Self.reply.endIndex) ?? Self.reply.endIndex
                continuation.yield(.textDelta(String(Self.reply[from..<to])))
            }
            continuation.yield(.done(nil))
            continuation.finish()
        }
        return await controller.runScriptedTurn(transcript: "where do I export this as a PDF", screenshots: Self.shots,
                                                replay: (id: winner, events: events), replaySawScreen: sighted)
    }

    @Test func aMarkIsRevealedWithItsSentenceBeforeTheNextLineBegins() async {
        let log = TurnLog()
        let result = await run(controller(consent: true, log: log), winner: "claude")
        #expect(result.error == nil)
        #expect(log.events.prefix(4) == ["begin marks=2 w=1280", "line Open the File menu.", "reveal 0", "line Choose Export as PDF."])
        let lines = log.events.filter { $0.hasPrefix("line ") }
        #expect(lines.count == 3)
        #expect(!lines.contains { $0.contains("[") || $0.contains("DRAW") })
        let firstReveal = log.events.firstIndex(of: "reveal 0")!
        let secondLine = log.events.firstIndex(of: "line Choose Export as PDF.")!
        #expect(firstReveal < secondLine)
        #expect(log.events.contains("reveal 1"))
    }

    @Test func consentOffMakesNoPresenterCallAndStillSpeaksEverySentence() async {
        let log = TurnLog()
        let result = await run(controller(consent: false, log: log), winner: "claude")
        #expect(result.error == nil)
        #expect(log.events == ["line Open the File menu.", "line Choose Export as PDF.", "line Then save it."])
    }

    @Test func aWinnerThatNeverSawPixelsDrawsNothing() async {
        let log = TurnLog()
        _ = await run(controller(consent: true, log: log), winner: "codex")
        #expect(!log.events.contains { $0.hasPrefix("begin") || $0.hasPrefix("reveal") })
        #expect(log.events.filter { $0.hasPrefix("line ") }.count == 3)
    }

    @Test func consentOffSendsEveryShotAndConsentOnSendsTheCursorDisplayOnly() {
        #expect(TalkDrawPolicy.requestShots(consent: false, shots: Self.shots).count == 2)
        let one = TalkDrawPolicy.requestShots(consent: true, shots: Self.shots)
        #expect(one.count == 1)
        #expect(one.first?.label == "screen 1")
        #expect(TalkDrawPolicy.requestShots(consent: true, shots: []).isEmpty)
    }

    @Test func theNextKeyPressClearsADrawingAndANeverDrawnTurnClearsNothing() async {
        let log = TurnLog()
        let drawn = controller(consent: true, log: log)
        _ = await run(drawn, winner: "claude")
        log.events.removeAll()
        drawn.clearDrawingForNewTurn()
        drawn.clearDrawingForNewTurn()
        #expect(log.events == ["clear"])

        let quiet = TurnLog()
        let off = controller(consent: false, log: quiet)
        _ = await run(off, winner: "claude")
        quiet.events.removeAll()
        off.clearDrawingForNewTurn()
        #expect(quiet.events.isEmpty)
    }

    // MARK: What the turn really sends

    private func observe(_ controller: VoiceTurnController) -> Box {
        let box = Box()
        controller.turnObserver = { box.observation = $0 }
        return box
    }

    @MainActor private final class Box { var observation: VoiceTurnController.TurnObservation? }

    @Test func consentOffSendsTheBaseRequestWithEveryShotAndNoDrawPrompt() async throws {
        let log = TurnLog()
        let off = controller(consent: false, log: log)
        let box = observe(off)
        _ = await run(off, winner: "claude")
        let seen = try #require(box.observation)
        #expect(seen.request.screenshots.count == 2)
        #expect(seen.request.screenshots.map(\.label) == ["screen 1", "screen 2"])
        #expect(!seen.preferAppClaude)
        #expect(!seen.request.carriesDrawImage)
        #expect(!seen.request.systemPrompt.contains("[DRAW:"))
        #expect(seen.shots.count == 2)
    }

    @Test func consentOnSendsOneShotToTheBrainButKeepsEveryCaptureForPointAndDrive() async throws {
        let log = TurnLog()
        let on = controller(consent: true, log: log)
        let box = observe(on)
        _ = await run(on, winner: "claude")
        let seen = try #require(box.observation)
        #expect(seen.request.screenshots.map(\.label) == ["screen 1"])
        #expect(seen.preferAppClaude)
        #expect(seen.request.carriesDrawImage)
        #expect(seen.request.systemPrompt.contains("[DRAW:"))
        #expect(seen.shots.count == 2, "POINT screenN and the drive and walkthrough actions still see every display")
    }

    @Test func aReplayedSpeculativeTurnNeverDraws() async {
        let log = TurnLog()
        _ = await run(controller(consent: true, log: log), winner: "claude", sighted: false)
        #expect(!log.events.contains { $0.hasPrefix("begin") || $0.hasPrefix("reveal") })
        #expect(log.events.filter { $0.hasPrefix("line ") }.count == 3)
    }

    // MARK: One turn's drawing cannot be changed by another turn

    private func presenter() -> TalkVisualPresenter {
        let frame = Self.shots[0].displayFrame
        return TalkVisualPresenter(screens: { [.init(id: 7, frame: frame, scale: 2)] }, reduceMotion: { true })
    }

    private static let draw = TalkDraw(screen: 1, marks: [
        .init(shape: .ring(center: .init(x: 100, y: 100), radius: 20), at: 0),
        .init(shape: .ring(center: .init(x: 300, y: 200), radius: 20), at: 1),
    ])

    @Test func anOldTurnCannotRevealOrArmTheHideAgainstANewTurnsCapture() {
        let drawing = presenter()
        defer { drawing.clear() }
        let old = UUID(), new = UUID()
        drawing.begin(Self.draw, shot: Self.shots[0], token: old)
        drawing.begin(Self.draw, shot: Self.shots[0], token: new)
        drawing.reveal(sentence: 0, token: old)
        #expect(!drawing.isShowing, "a stale turn's reveal is ignored")
        drawing.answerFinished(token: old)
        #expect(!drawing.hideIsArmed, "a stale turn cannot arm the hide")
        drawing.reveal(sentence: 0, token: new)
        #expect(drawing.isShowing)
        drawing.answerFinished(token: new)
        #expect(drawing.hideIsArmed)
        drawing.clear()
        #expect(!drawing.isShowing && !drawing.hideIsArmed)
    }

    @Test func revealsOfOneTurnShareOneSceneAndOnlyAdvanceItsRevision() {
        let drawing = presenter()
        defer { drawing.clear() }
        let token = UUID()
        drawing.begin(Self.draw, shot: Self.shots[0], token: token)
        drawing.reveal(sentence: 0, token: token)
        let first = drawing.sceneIdentity
        drawing.reveal(sentence: 1, token: token)
        let second = drawing.sceneIdentity
        #expect(first != nil && first?.session == second?.session && first?.scene == second?.scene)
        #expect((second?.revision ?? 0) > (first?.revision ?? 0))
    }
}
