import Foundation

enum SpokenAnswerFirst {
    static func apply(_ draft: SpokenDraft, maxSentences: Int?) -> SpokenDraft {
        guard let maxSentences else { return draft }
        if maxSentences <= 0 { return SpokenDraft(text: "", runs: []) }
        var kept: [SpokenRun] = []
        var sentences = 0
        for run in draft.runs {
            kept.append(run)
            if run.pauseAfter == .sentence {
                sentences += 1
                if sentences >= maxSentences { break }
            }
        }
        let text = SpokenText.collapse(kept.map(\.text).joined(separator: " "))
        return SpokenDraft(text: text, runs: kept)
    }
}
