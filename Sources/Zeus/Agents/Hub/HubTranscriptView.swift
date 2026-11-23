import Foundation
import ZeusCore

/// One transcript line. Keep `id` stable while tokens arrive so the agent bubble grows in place.
struct HubTranscriptLine: Equatable, Identifiable, Sendable {
    var id: String
    var role: HubLineRole
    var text: String
}

/// Entrance motion for a transcript line. Reduce Motion is offset 0 and scale 1.
struct HubTranscriptMotion: Equatable, Sendable {
    var offset: Double
    var scale: Double
}

/// How one line is drawn. Failed and stopped are plain text. Agent lines use the markdown view.
enum HubTranscriptAppearance: Equatable, Sendable {
    case userBubble
    case markdown
    case waitingBars
    case plain
}

enum HubTranscriptDrawing {
    /// The markdown view is for agent lines only. A failed line never takes this path.
    static func usesMarkdownView(_ role: HubLineRole) -> Bool {
        role == .agent
    }

    static func appearance(line: HubTranscriptLine, status: HubTranscriptStatus, isLast: Bool) -> HubTranscriptAppearance {
        switch line.role {
        case .failed, .stopped:
            return .plain
        case .person:
            return .userBubble
        case .agent:
            if line.text.isEmpty {
                return (status == .streaming && isLast) ? .waitingBars : .plain
            }
            return .markdown
        }
    }

    /// Lines the view shows. An empty agent line is the waiting bubble, and only while streaming.
    static func rows(lines: [HubTranscriptLine], status: HubTranscriptStatus) -> [HubTranscriptLine] {
        var kept = lines.filter { line in
            guard line.role == .agent, line.text.isEmpty else { return true }
            return status == .streaming && line.id == lines.last?.id
        }
        if status == .streaming, kept.last?.role != .agent,
           !kept.contains(where: { $0.id == HubTranscriptContract.waitingLineID }) {
            kept.append(HubTranscriptLine(id: HubTranscriptContract.waitingLineID, role: .agent, text: ""))
        }
        return kept
    }

    /// Spoken text for one line, in top-to-bottom order. Failed text is the raw string.
    static func spokenLine(line: HubTranscriptLine, status: HubTranscriptStatus, isLast: Bool) -> String {
        switch appearance(line: line, status: status, isLast: isLast) {
        case .waitingBars:
            return HubTranscriptContract.waitingLabel
        case .userBubble, .markdown, .plain:
            return HubTranscriptContract.lineLabel(role: line.role, text: line.text)
        }
    }
}

/// Focus-contract values for the transcript. The view reads these. It does not keep a second copy.
enum HubTranscriptContract {
    /// Spoken name of `HubFocusTarget.transcript`. VoiceOver reads the transcript, then Copy.
    static let accessibilityLabel = "Transcript"
    static let voiceOverOrder: [HubFocusTarget] = [.transcript, .copy]
    /// The page crossfade: an 8 pt rise and a 0.985 scale. Reduce Motion uses neither.
    static let rise = 8.0
    static let entranceScale = 0.985
    static let waitingLabel = "Waiting for a reply"
    static let waitingLineID = "hub.transcript.waiting"

    static func motion(reduceMotion: Bool) -> HubTranscriptMotion {
        reduceMotion
            ? HubTranscriptMotion(offset: 0, scale: 1)
            : HubTranscriptMotion(offset: rise, scale: entranceScale)
    }

    static func lineLabel(role: HubLineRole, text: String) -> String {
        switch role {
        case .person: "You, \(text)"
        case .agent: "Agent"
        case .failed: "Failed, \(text)"
        case .stopped: text
        }
    }

    /// True when the spoken label, the VoiceOver order, and the motion profile match the focus contract.
    static func holds(reduceMotion: Bool) -> Bool {
        let labelMatches = accessibilityLabel.caseInsensitiveCompare(HubFocusTarget.transcript.storedLabel) == .orderedSame
        let order = HubFocusTarget.screenOrder
        let approval = HubFocusTarget.selectedApprovalOrder
        guard labelMatches,
              voiceOverOrder == [.transcript, .copy],
              let transcript = order.firstIndex(of: .transcript),
              let copy = order.firstIndex(of: .copy),
              transcript < copy,
              let row = approval.firstIndex(of: .row),
              let transcriptAfterRow = approval.firstIndex(of: .transcript),
              let reply = approval.firstIndex(of: .reply),
              row < transcriptAfterRow,
              transcriptAfterRow < reply,
              !HubTranscriptDrawing.usesMarkdownView(.failed),
              !HubTranscriptDrawing.usesMarkdownView(.stopped),
              HubTranscriptDrawing.usesMarkdownView(.agent)
        else { return false }
        let profile = motion(reduceMotion: reduceMotion)
        if reduceMotion {
            return profile.offset == 0 && profile.scale == 1
        }
        return profile.offset == rise && profile.scale == entranceScale
    }
}

/// Red line for this view. Fails until the accessibility label matches the focus contract.
enum HubTranscriptRedLine {
    static func sampleFailures() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) {
            if !ok { failures.append(message) }
        }
        let person = HubTranscriptLine(id: "person", role: .person, text: "Show a sample")
        let waiting = HubTranscriptDrawing.rows(lines: [person], status: .streaming)
        check(waiting.last?.role == .agent && waiting.last?.text.isEmpty == true,
              "streaming before the first token shows the waiting bubble")
        if let last = waiting.last {
            check(HubTranscriptDrawing.appearance(line: last, status: .streaming, isLast: true) == .waitingBars,
                  "waiting bars")
        }
        let arriving = HubTranscriptLine(id: "agent", role: .agent, text: "# Title\n\n- One")
        check(HubTranscriptDrawing.appearance(line: arriving, status: .streaming, isLast: true) == .markdown,
              "streaming lines use the markdown view")
        let settled = HubTranscriptLine(id: "agent", role: .agent, text: "# Title\n\n- One\n\n```\nprint(1)\n```")
        check(HubTranscriptDrawing.appearance(line: settled, status: .settled, isLast: true) == .markdown,
              "settled lines use the markdown view")
        let failed = HubTranscriptLine(id: "failed", role: .failed, text: "# Not a heading")
        check(HubTranscriptDrawing.appearance(line: failed, status: .failed, isLast: true) == .plain,
              "a failed line is plain text")
        check(HubTranscriptDrawing.spokenLine(line: failed, status: .failed, isLast: true) == "Failed, # Not a heading",
              "a failed line keeps the raw text")
        let fenced = HubTranscriptLine(id: "fenced", role: .failed, text: "```\nprint(1)\n```")
        check(HubTranscriptDrawing.appearance(line: fenced, status: .failed, isLast: true) == .plain,
              "a fenced failed line is not a code block")
        let stopped = HubTranscriptLine(id: "stopped", role: .stopped, text: HubTranscriptNotice.stopped.storedLabel)
        check(HubTranscriptDrawing.appearance(line: stopped, status: .settled, isLast: true) == .plain,
              "Stopped is plain text")
        let reduced = HubTranscriptContract.motion(reduceMotion: true)
        check(reduced.offset == 0 && reduced.scale == 1, "Reduce Motion requests zero offset and scale 1")
        check(HubTranscriptContract.holds(reduceMotion: true), "Reduce Motion contract")
        check(HubTranscriptContract.holds(reduceMotion: false), "motion contract")
        return failures
    }

    static func require(reduceMotion: Bool) {
        let failures = sampleFailures()
        precondition(
            failures.isEmpty && HubTranscriptContract.holds(reduceMotion: reduceMotion),
            "HubTranscriptView accessibility label does not match the focus contract. \(failures.joined(separator: " "))"
        )
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// Scrolling transcript for one session or one Zeus conversation.
///
/// Person lines use the existing user bubble. Streaming and settled agent lines use `MarkdownBlocksView`.
/// A failed line is plain danger text and is never parsed as markdown. Stopped is plain text too.
/// Before the first token, the existing level bars sit in the agent bubble and stay still under Reduce Motion.
struct HubTranscriptView: View {
    var lines: [HubTranscriptLine]
    var status: HubTranscriptStatus
    /// Set by the red-line host. Production reads the system Reduce Motion setting.
    var prefersReducedMotion: Bool? = nil

    #if DEBUG
    /// Runs the red line once, the first time a transcript is built.
    private static let contractChecked: Void = {
        HubTranscriptRedLine.require(reduceMotion: true)
        HubTranscriptRedLine.require(reduceMotion: false)
    }()
    #endif

    init(lines: [HubTranscriptLine], status: HubTranscriptStatus, prefersReducedMotion: Bool? = nil) {
        self.lines = lines
        self.status = status
        self.prefersReducedMotion = prefersReducedMotion
        #if DEBUG
        _ = Self.contractChecked
        #endif
    }

    var body: some View {
        let reduced = prefersReducedMotion ?? Motion.reduced
        let shown = HubTranscriptDrawing.rows(lines: lines, status: status)
        let tail = shown.last.map { "\($0.id)\u{1}\($0.text)" } ?? ""
        ScrollViewReader { proxy in
            ScrollView {
                // Oldest line at the top, newest at the bottom. VoiceOver follows that order.
                // Copy stays inside the code block, so it is read with the transcript and before Reply.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, line in
                        HubTranscriptBubble(
                            line: line,
                            status: status,
                            isLast: index == shown.count - 1,
                            reduceMotion: reduced
                        )
                        .id(line.id)
                        .transition(Self.insertion(reduceMotion: reduced))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.page(reduceMotion: reduced), value: shown.map(\.id))
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.never)
            .onChange(of: tail) { scroll(shown, proxy, reduced) }
            .onAppear { scroll(shown, proxy, reduced) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(HubTranscriptContract.accessibilityLabel)
            .accessibilityIdentifier(HubFocusTarget.transcript.storedLabel)
            .focusable()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Reduce Motion inserts the line in place. Motion uses the page crossfade, then rests at full size.
    static func insertion(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let motion = HubTranscriptContract.motion(reduceMotion: false)
        return .opacity
            .combined(with: .offset(y: CGFloat(motion.offset)))
            .combined(with: .scale(scale: CGFloat(motion.scale), anchor: .bottom))
    }

    private func scroll(_ shown: [HubTranscriptLine], _ proxy: ScrollViewProxy, _ reduceMotion: Bool) {
        guard let id = shown.last?.id else { return }
        if reduceMotion {
            proxy.scrollTo(id, anchor: .bottom)
        } else if let animation = Motion.feedback(reduceMotion: false) {
            withAnimation(animation) { proxy.scrollTo(id, anchor: .bottom) }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

/// One bubble. The glass fill and stroke are the notch tiles the rest of the bar already uses.
private struct HubTranscriptBubble: View {
    let line: HubTranscriptLine
    let status: HubTranscriptStatus
    let isLast: Bool
    let reduceMotion: Bool

    private var appearance: HubTranscriptAppearance {
        HubTranscriptDrawing.appearance(line: line, status: status, isLast: isLast)
    }

    var body: some View {
        let person = appearance == .userBubble
        let width: CGFloat? = person ? nil : .infinity
        HStack(alignment: .top, spacing: 0) {
            if person { Spacer(minLength: 60) }
            content
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(person ? Theme.cloudPrimary : TopBarStyle.tile,
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    if !person {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(TopBarStyle.tileStroke)
                    }
                }
                .frame(maxWidth: width, alignment: person ? .trailing : .leading)
            if !person { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: accessChildren)
        .accessibilityLabel(HubTranscriptDrawing.spokenLine(line: line, status: status, isLast: isLast))
        .animation(Motion.feedback(reduceMotion: reduceMotion), value: line.text)
    }

    private var accessChildren: AccessibilityChildBehavior {
        switch appearance {
        case .markdown: .contain
        case .userBubble: .combine
        case .waitingBars, .plain: .ignore
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appearance {
        case .userBubble:
            Text(Self.inline(line.text))
                .font(TopBarStyle.label(13))
                .foregroundStyle(Theme.storm)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .markdown:
            MarkdownBlocksView(text: line.text, size: 13)
                .textSelection(.enabled)
        case .waitingBars:
            LevelBars(color: Theme.bolt, active: !reduceMotion, height: 10)
        case .plain:
            Text(verbatim: line.text)
                .font(TopBarStyle.label(13))
                .foregroundStyle(line.role == .failed ? Theme.danger : Theme.cloudPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The existing user bubble's inline markdown. Failed and stopped lines do not call this.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Preview host. It draws the streaming, settled, and failed appearances, and it refuses to
/// draw them when the accessibility label misses the focus contract.
struct HubTranscriptRedLineHost: View {
    var reduceMotion: Bool

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        HubTranscriptRedLine.require(reduceMotion: reduceMotion)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pane("Streaming", lines: Self.beforeTokens, status: .streaming)
                pane("Streaming", lines: Self.arriving, status: .streaming)
                pane("Settled", lines: Self.settled, status: .settled)
                pane("Failed", lines: Self.failed, status: .failed)
                pane("Stopped", lines: Self.stopped, status: .settled)
            }
            .padding(12)
        }
        .background(Color.black)
    }

    private func pane(_ title: String, lines: [HubTranscriptLine], status: HubTranscriptStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TopBarStyle.label(11, .semibold))
                .foregroundStyle(Theme.cloudQuiet)
                .accessibilityHidden(true)
            HubTranscriptView(lines: lines, status: status, prefersReducedMotion: reduceMotion)
                .frame(height: 210)
        }
    }

    static let beforeTokens = [
        HubTranscriptLine(id: "you", role: .person, text: "Show a sample"),
    ]

    static let arriving = [
        HubTranscriptLine(id: "you", role: .person, text: "Show a sample"),
        HubTranscriptLine(id: "agent", role: .agent, text: "# Title\n\n- One"),
    ]

    static let settled = [
        HubTranscriptLine(id: "you", role: .person, text: "Show a sample"),
        HubTranscriptLine(id: "agent", role: .agent, text: "# Title\n\n- One\n\n```\nprint(1)\n```"),
    ]

    static let failed = [
        HubTranscriptLine(id: "you", role: .person, text: "Fail empty"),
        HubTranscriptLine(id: "empty", role: .failed, text: HubTranscriptNotice.noAnswer.storedLabel),
        HubTranscriptLine(id: "raw", role: .failed, text: "# Not a heading"),
    ]

    static let stopped = [
        HubTranscriptLine(id: "you", role: .person, text: "Stop this"),
        HubTranscriptLine(id: "stop", role: .stopped, text: HubTranscriptNotice.stopped.storedLabel),
    ]
}

struct HubTranscriptView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HubTranscriptRedLineHost(reduceMotion: false)
                .frame(width: 460, height: 720)
                .previewDisplayName("Transcript")
            HubTranscriptRedLineHost(reduceMotion: true)
                .frame(width: 460, height: 720)
                .previewDisplayName("Transcript, Reduce Motion")
        }
    }
}
#endif
