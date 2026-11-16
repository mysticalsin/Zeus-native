import Foundation
import ZeusCore

/// What the talk turn asks of the on-screen drawing. The turn calls these on the main actor and never
/// reads anything back, so a fake stands in for the screen in tests.
@MainActor
protocol TalkVisualPresenting: AnyObject {
    /// A draw tag arrived for this capture. Nothing is shown yet.
    func begin(_ draw: TalkDraw, shot: ScreenShot)
    /// The line for this sentence index has started to play: show its marks.
    func reveal(sentence: Int)
    /// The last sentence has finished playing: hide the marks soon.
    func answerFinished()
    /// Hide everything now.
    func clear()
}

/// Holds the marks of the answer in flight, grouped by the sentence they appear with.
@MainActor
final class TalkVisualPresenter: TalkVisualPresenting {
    private(set) var pending: [Int: [ExplanationObject]] = [:]
    private(set) var shown: [ExplanationObject] = []
    private var shot: ScreenShot?

    func begin(_ draw: TalkDraw, shot: ScreenShot) {
        clear()
        self.shot = shot
        pending = TalkDrawScene.objects(draw, shot: shot, captureID: UUID())
    }

    func reveal(sentence: Int) {
        guard let marks = pending.removeValue(forKey: sentence) else { return }
        shown += marks
    }

    func answerFinished() {}

    func clear() {
        pending = [:]
        shown = []
        shot = nil
    }
}
