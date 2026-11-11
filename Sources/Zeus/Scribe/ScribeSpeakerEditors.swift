import SwiftUI
import ZeusCore

/// The accent of the finished notes (the writing glow's edge purple), kept local so this file stands alone.
private let editorAccent: Color = {
    let rgb = ScribeGlow.edgeColor
    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
}()

/// One block of the recap transcript: speaker chip, time and text, with "Reassign this block to" and
/// "Assign selected words to" in its context menu. Without speaker tools it is a plain block.
struct ScribeTranscriptBlock: View {
    let segment: ScribeTranscriptSegment
    let tools: ScribeSpeakerTools?
    /// Names offered first: the meeting's other speakers, then the invite.
    let names: [String]

    @State private var reassigning = false
    @State private var selectingWords = false

    var body: some View {
        let rgb = ScribeSpeakerPalette.color(for: segment.speaker)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(segment.speaker.displayName)
                    .font(TopBarStyle.label(9, .semibold))
                    .foregroundStyle(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                Text("\u{00B7} \(RecordlyElapsed.format(segment.start))")
                    .font(TopBarStyle.label(9).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
            }
            Text(segment.text).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .contextMenu { menu }
        .popover(isPresented: $reassigning) {
            ScribeNamePicker(title: "Reassign this block to", names: names) { name in
                tools?.reassignBlock(segment.id, name)
                reassigning = false
            }
        }
        .popover(isPresented: $selectingWords) {
            ScribeWordPicker(words: ScribeSpeakerEdits.words(of: segment), names: names) { range, name in
                tools?.assignWords(segment.id, range, name)
                selectingWords = false
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if tools != nil {
            Button("Reassign this block to\u{2026}") { reassigning = true }
            Button("Assign selected words to\u{2026}") { selectingWords = true }
        }
    }
}

/// A short list of names plus a field for a new one.
struct ScribeNamePicker: View {
    let title: String
    let names: [String]
    let choose: (String) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
            ForEach(names, id: \.self) { name in
                Button(name) { choose(name) }
                    .buttonStyle(.plain)
                    .font(TopBarStyle.label(11)).foregroundStyle(editorAccent)
                    .accessibilityLabel("\(title) \(name)")
            }
            TextField("Someone else", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
                .accessibilityLabel("A name that is not listed")
            NotchActionButton(title: "Assign", tint: TopBarStyle.rec) { submit() }
                .disabled(trimmed.isEmpty)
        }
        .padding(10)
        .frame(width: 230)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        choose(trimmed)
    }
}

/// Words of one block as chips: tap the first and the last word of the part to move, then pick the name.
struct ScribeWordPicker: View {
    let words: [String]
    let names: [String]
    let assign: (Range<Int>, String) -> Void

    @State private var first: Int?
    @State private var last: Int?

    private var selection: Range<Int>? {
        guard let first else { return nil }
        let end = last ?? first
        return min(first, end)..<(max(first, end) + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap the first and last word").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        chip(index, word)
                    }
                }
            }
            .frame(maxHeight: 140)
            if let selection {
                ScribeNamePicker(title: "Assign \(selection.count) word\(selection.count == 1 ? "" : "s") to", names: names) { name in
                    assign(selection, name)
                }
            }
        }
        .padding(10)
        .frame(width: 280)
    }

    private func chip(_ index: Int, _ word: String) -> some View {
        let chosen = selection?.contains(index) == true
        return Button { tap(index) } label: {
            Text(word).font(TopBarStyle.label(10)).lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .foregroundStyle(chosen ? Color.black : Theme.cloudPrimary)
                .background(Capsule().fill(chosen ? editorAccent : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func tap(_ index: Int) {
        if first == nil || last != nil {
            first = index
            last = nil
        } else {
            last = index
        }
    }
}
