import SwiftUI
import ZeusCore

/// Native text shaping owns wrapping, whitespace, ligatures and bidirectional layout. The renderer
/// changes only the paint of words already admitted by Scribe's existing presentation schedule.
/// macOS 14.2 keeps the original Text-prefix path at the call site.
@available(macOS 15.0, *)
struct ScribeIncomingWords: View {
    let layout: ScribeIncomingWordLayout
    let shownWords: Int
    let date: Date
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var cache = IncomingWordTextCache()

    var body: some View {
        let now = date.timeIntervalSinceReferenceDate
        Group {
            if reduceMotion || layout.isSettled(at: now, shownWords: shownWords) {
                Text(layout.text)
            } else {
                cache.text(for: layout, shownWords: shownWords)
                    .textRenderer(IncomingWordRenderer(layout: layout, shownWords: shownWords,
                        now: now, reduceTransparency: reduceTransparency))
            }
        }
        // The parent transcript line exposes its complete original text once, including provisional status.
        .accessibilityHidden(true)
    }
}

@available(macOS 15.0, *)
private struct IncomingWordAttribute: TextAttribute {
    let index: Int
}

/// Memoization only: no published state or body-driven observation updates. One attributed Text value
/// is composed per real text revision or admitted word, never per display frame. Hidden future
/// words do not reserve paragraph height or move the existing transcript out of the viewport.
@available(macOS 15.0, *)
@MainActor
private final class IncomingWordTextCache: ObservableObject {
    private var revision: UInt64?
    private var source: String?
    private var shown: Int?
    private var rendered = Text("")

    func text(for layout: ScribeIncomingWordLayout, shownWords: Int) -> Text {
        let count = min(max(0, shownWords), layout.words.count)
        if revision != layout.revision || source != layout.text || shown != count {
            rendered = layout.visibleRuns(shownWords: count).reduce(Text("")) { accumulated, run in
                let text = Text(run.text)
                if let index = run.wordIndex {
                    return accumulated + text.customAttribute(IncomingWordAttribute(index: index))
                }
                return accumulated + text
            }
            revision = layout.revision
            source = layout.text
            shown = count
        }
        return rendered
    }
}

@available(macOS 15.0, *)
private struct IncomingWordRenderer: TextRenderer {
    let layout: ScribeIncomingWordLayout
    let shownWords: Int
    let now: TimeInterval
    let reduceTransparency: Bool

    func draw(layout textLayout: Text.Layout, in context: inout GraphicsContext) {
        for line in textLayout {
            for run in line {
                var copy = context
                if let word = run[IncomingWordAttribute.self] {
                    let frame = layout.frame(forWord: word.index, shownWords: shownWords, at: now,
                        reduceTransparency: reduceTransparency)
                    guard frame.opacity > 0 else { continue }
                    copy.opacity *= frame.opacity
                    if frame.blur > 0 { copy.addFilter(.blur(radius: frame.blur)) }
                }
                copy.draw(run)
            }
        }
    }
}
