import Foundation
#if canImport(ZeusCore)
import ZeusCore
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Spoken labels and motion numbers for the session list.
/// The view draws with these strings. A host fails while they disagree with the contract.
enum SessionListAccessibility {
    static let openLabel = "Open"
    static let queuedWord = "Queued"
    /// The page rise, in points. Reduce Motion asks for none.
    static let rise = 8.0
    /// The page scale while it is arriving. Reduce Motion asks for 1.
    static let arrivingScale = 0.985

    static func offset(reduceMotion: Bool) -> Double { reduceMotion ? 0 : rise }
    static func scale(reduceMotion: Bool) -> Double { reduceMotion ? 1 : arrivingScale }

    /// `m:ss` as VoiceOver should say it. Empty text is omitted. Anything else is spoken as given.
    static func spokenElapsed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces[1].count == 2,
              let minutes = Int(pieces[0]), let seconds = Int(pieces[1]),
              minutes >= 0, (0..<60).contains(seconds) else {
            return trimmed
        }
        let minuteWord = minutes == 1 ? "minute" : "minutes"
        let secondWord = seconds == 1 ? "second" : "seconds"
        return "\(minutes) \(minuteWord) \(seconds) \(secondWord)"
    }

    /// "Agent, project, Running, 3 minutes 12 seconds." Queued is the badge, after the clock.
    static func rowLabel(name: String, project: String, statusWord: String, elapsedText: String, queued: Bool, hidesDetails: Bool) -> String {
        var parts: [String] = []
        let agent = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agent.isEmpty { parts.append(agent) }
        if !hidesDetails {
            let job = project.trimmingCharacters(in: .whitespacesAndNewlines)
            if !job.isEmpty { parts.append(job) }
        }
        let word = statusWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if !word.isEmpty { parts.append(word) }
        if let spoken = spokenElapsed(elapsedText) { parts.append(spoken) }
        if queued { parts.append(queuedWord) }
        return parts.joined(separator: ", ")
    }

    /// Header: name, count, expanded or collapsed, and the urgent clock when folded.
    static func groupLabel(name: String, count: Int, expanded: Bool, peekElapsed: String) -> String {
        let sessions = count == 1 ? "1 session" : "\(count) sessions"
        var label = "\(name), \(sessions), \(expanded ? "expanded" : "collapsed")"
        if !expanded, let spoken = spokenElapsed(peekElapsed) {
            label += ", \(spoken)"
        }
        return label
    }

    /// Earlier row wins a tie. `error.failed` and `error.quiet` share the error rank.
    static func mostUrgentIndex(storedLabels: [String], urgency: [String]) -> Int? {
        guard !storedLabels.isEmpty else { return nil }
        var best = 0
        var bestRank = rank(storedLabels[0], urgency: urgency)
        for index in storedLabels.indices.dropFirst() {
            let next = rank(storedLabels[index], urgency: urgency)
            if next < bestRank {
                best = index
                bestRank = next
            }
        }
        return best
    }

    static func contractMismatches() -> [String] {
        var mismatches: [String] = []
        func expect(_ name: String, _ got: String, _ want: String) {
            if got != want { mismatches.append("\(name): [\(got)] != [\(want)]") }
        }

        let canonical = SessionListLabels.row(SessionListRow(
            id: "canonical", name: "Agent A", project: "payments-api", task: "Run the migration script",
            status: .running, elapsedText: "3:12", queuedApproval: false, canOpen: true
        ), hidesDetails: false)
        expect("row", canonical, "Agent A, payments-api, Running, 3 minutes 12 seconds")
        if canonical.contains("Run the migration") { mismatches.append("row label includes the task line") }
        if canonical.contains(openLabel) { mismatches.append("row label includes Open") }
        if canonical.localizedCaseInsensitiveContains("selected") { mismatches.append("selected is in the label") }

        expect("queued", SessionListLabels.row(SessionListRow(
            id: "queued", name: "Agent B", project: "web-client", task: "Delete the build folder",
            status: .running, elapsedText: "0:30", queuedApproval: true, canOpen: false
        ), hidesDetails: false), "Agent B, web-client, Running, 0 minutes 30 seconds, Queued")

        expect("hidden details", SessionListLabels.row(SessionListRow(
            id: "hidden", name: "Agent A", project: "payments-api", task: "Run the migration script",
            status: .running, elapsedText: "3:12", queuedApproval: false, canOpen: false
        ), hidesDetails: true), "Agent A, Running, 3 minutes 12 seconds")

        expect("singular", SessionListLabels.row(SessionListRow(
            id: "singular", name: "Agent A", project: "docs-site", task: "Which heading style do you want?",
            status: .waitingForInput, elapsedText: "1:01", queuedApproval: false, canOpen: false
        ), hidesDetails: false), "Agent A, docs-site, Waiting for input, 1 minute 1 second")

        expect("announced", SessionListLabels.row(SessionListRow(
            id: "loading", name: "Agent A", project: "payments-api", task: "Starting up",
            status: .loading, elapsedText: "", queuedApproval: false, canOpen: false
        ), hidesDetails: false), "Agent A, payments-api, Announced")

        expect("failed", SessionListLabels.row(SessionListRow(
            id: "failed", name: "Agent B", project: "web-client", task: "The service had an error",
            status: .error(.failed), elapsedText: "6:00", queuedApproval: false, canOpen: true
        ), hidesDetails: false), "Agent B, web-client, Error, 6 minutes 0 seconds")

        expect("quiet", SessionListLabels.row(SessionListRow(
            id: "quiet", name: "Agent B", project: "web-client", task: "No activity for 6 min",
            status: .error(.quiet), elapsedText: "0:52", queuedApproval: false, canOpen: false
        ), hidesDetails: false), "Agent B, web-client, Error, 0 minutes 52 seconds")

        let words: [(HubSessionStatus, String)] = [
            (.running, "Running"), (.waitingForInput, "Waiting for input"), (.needsApproval, "Needs approval"),
            (.done, "Done"), (.error(.failed), "Error"), (.error(.quiet), "Error"), (.loading, "Announced"),
        ]
        for (status, word) in words where status.visibleWord != word {
            mismatches.append("status word \(status.storedLabel) is \(status.visibleWord ?? "nil")")
        }

        expect("one session", SessionListAccessibility.groupLabel(
            name: "Agent C", count: 1, expanded: false, peekElapsed: "6:03"
        ), "Agent C, 1 session, collapsed, 6 minutes 3 seconds")
        expect("expanded", SessionListAccessibility.groupLabel(
            name: "Agent A", count: 2, expanded: true, peekElapsed: "3:12"
        ), "Agent A, 2 sessions, expanded")

        let spoken = SessionListLabels.voiceOverOrder(groups: SessionListFixture.groups, hidesDetails: false)
        if spoken != SessionListFixture.expectedOrder {
            mismatches.append("voice over order:\n" + spoken.joined(separator: "\n") + "\n!=\n" + SessionListFixture.expectedOrder.joined(separator: "\n"))
        }

        if offset(reduceMotion: true) != 0 || scale(reduceMotion: true) != 1 {
            mismatches.append("reduce motion offset \(offset(reduceMotion: true)) scale \(scale(reduceMotion: true))")
        }
        if offset(reduceMotion: false) != rise || scale(reduceMotion: false) != arrivingScale {
            mismatches.append("motion offset \(offset(reduceMotion: false)) scale \(scale(reduceMotion: false))")
        }
        if openLabel != "Open" { mismatches.append("open label \(openLabel)") }
        if queuedWord != "Queued" { mismatches.append("queued word \(queuedWord)") }
        if mostUrgentIndex(storedLabels: ["running", "error.quiet", "needsApproval"], urgency: HubSessionStatus.urgencyLabels) != 2 {
            mismatches.append("urgent row is not the approval")
        }
        if mostUrgentIndex(storedLabels: ["error.failed", "error.quiet"], urgency: HubSessionStatus.urgencyLabels) != 0 {
            mismatches.append("tied errors did not keep the earlier row")
        }
        return mismatches
    }

    static func requireContract() {
        let mismatches = contractMismatches()
        precondition(mismatches.isEmpty, mismatches.joined(separator: "\n"))
    }

    private static func rank(_ storedLabel: String, urgency: [String]) -> Int {
        let key = storedLabel.hasPrefix("error.") ? "error" : storedLabel
        return urgency.firstIndex(of: key) ?? urgency.count
    }
}

/// One session row. The status is a hub name. The clock text is already formatted.
struct SessionListRow: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var project: String
    var task: String
    var status: HubSessionStatus
    var elapsedText: String
    var queuedApproval: Bool
    var canOpen: Bool
}

/// One agent group. Empty groups are not drawn. `expanded` is given, not decided here.
struct SessionListGroup: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var expanded: Bool
    var rows: [SessionListRow]
}

/// The labels the list actually applies, in VoiceOver order.
enum SessionListLabels {
    static func row(_ row: SessionListRow, hidesDetails: Bool) -> String {
        SessionListAccessibility.rowLabel(
            name: row.name, project: row.project, statusWord: row.status.visibleWord ?? "",
            elapsedText: row.elapsedText, queued: row.queuedApproval, hidesDetails: hidesDetails)
    }

    static func group(_ group: SessionListGroup) -> String {
        let peek = group.expanded ? "" : (urgentRow(group)?.elapsedText ?? "")
        return SessionListAccessibility.groupLabel(
            name: group.name, count: group.rows.count, expanded: group.expanded, peekElapsed: peek)
    }

    /// Header, then each visible row. Folded rows stay out. An empty group is omitted.
    static func voiceOverOrder(groups: [SessionListGroup], hidesDetails: Bool) -> [String] {
        groups.filter { !$0.rows.isEmpty }.flatMap { group in
            let header = self.group(group)
            guard group.expanded else { return [header] }
            return [header] + group.rows.map { row($0, hidesDetails: hidesDetails) }
        }
    }

    static func visibleRowIDs(groups: [SessionListGroup]) -> [SessionListRow.ID] {
        groups.filter(\.expanded).flatMap { $0.rows.map(\.id) }
    }

    static func urgentRow(_ group: SessionListGroup) -> SessionListRow? {
        guard let index = SessionListAccessibility.mostUrgentIndex(
            storedLabels: group.rows.map(\.status.storedLabel),
            urgency: HubSessionStatus.urgencyLabels
        ) else { return nil }
        return group.rows[index]
    }
}

/// Two synthetic groups for the preview host. Agent C has no sessions, so it is not drawn.
enum SessionListFixture {
    static let groups: [SessionListGroup] = [
        SessionListGroup(id: "agent-a", name: "Agent A", expanded: true, rows: [
            SessionListRow(id: "payments", name: "Agent A", project: "payments-api", task: "Run the migration script",
                           status: .needsApproval, elapsedText: "3:12", queuedApproval: false, canOpen: true),
            SessionListRow(id: "docs", name: "Agent A", project: "docs-site", task: "Rewrite the install page",
                           status: .running, elapsedText: "1:40", queuedApproval: true, canOpen: false),
        ]),
        SessionListGroup(id: "agent-c", name: "Agent C", expanded: true, rows: []),
        SessionListGroup(id: "agent-b", name: "Agent B", expanded: false, rows: [
            SessionListRow(id: "client", name: "Agent B", project: "web-client", task: "Refactor the client",
                           status: .running, elapsedText: "9:00", queuedApproval: false, canOpen: false),
            SessionListRow(id: "quiet", name: "Agent B", project: "web-client", task: "No activity for 6 min",
                           status: .error(.quiet), elapsedText: "0:52", queuedApproval: true, canOpen: true),
        ]),
    ]

    static let expectedOrder = [
        "Agent A, 2 sessions, expanded",
        "Agent A, payments-api, Needs approval, 3 minutes 12 seconds",
        "Agent A, docs-site, Running, 1 minute 40 seconds, Queued",
        "Agent B, 2 sessions, collapsed, 0 minutes 52 seconds",
    ]
}

#if canImport(SwiftUI)
/// Groups and rows for the open Agents page. The closed bar and the tab row stay where they are.
@MainActor
struct SessionListView: View {
    var groups: [SessionListGroup]
    var selectedID: SessionListRow.ID?
    var hidesDetails: Bool
    /// Set by a host. Nil follows System Settings › Accessibility › Display › Reduce motion.
    var reduceMotionOverride: Bool?
    var onToggleGroup: @MainActor (SessionListGroup.ID) -> Void
    var onSelectRow: @MainActor (SessionListRow.ID) -> Void
    var onOpenRow: @MainActor (SessionListRow.ID) -> Void

    @FocusState private var focusedRow: SessionListRow.ID?

    private var reduceMotion: Bool { reduceMotionOverride ?? Motion.reduced }

    var body: some View {
        let shown = groups.filter { !$0.rows.isEmpty }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { groupIndex, group in
                groupBlock(group, index: groupIndex)
            }
        }
        .accessibilityElement(children: .contain)
        .animation(Motion.page(reduceMotion: reduceMotion), value: groups.map { "\($0.id):\($0.expanded)" })
    }

    private func groupBlock(_ group: SessionListGroup, index groupIndex: Int) -> some View {
        let urgent = SessionListLabels.urgentRow(group)
        return VStack(alignment: .leading, spacing: 6) {
            header(group, urgent: urgent, groupIndex: groupIndex)
            if group.expanded {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { rowIndex, row in
                    rowLine(row, groupIndex: groupIndex, rowIndex: rowIndex)
                        .transition(entrance)
                }
            }
        }
    }

    private func header(_ group: SessionListGroup, urgent: SessionListRow?, groupIndex: Int) -> some View {
        let tint = urgent.map { color(for: $0.status) } ?? Theme.cloudQuiet
        return Button {
            onToggleGroup(group.id)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.85), radius: 3)
                Text(group.name)
                    .font(Glass.bodyStrong)
                    .foregroundStyle(Theme.cloudPrimary)
                    .lineLimit(1)
                Text("\(group.rows.count)")
                    .font(Glass.caption.monospacedDigit())
                    .foregroundStyle(Theme.cloudQuiet)
                Spacer(minLength: 4)
                if !group.expanded, let elapsed = urgent?.elapsedText, !elapsed.isEmpty {
                    Text(elapsed)
                        .font(Glass.caption.monospacedDigit())
                        .foregroundStyle(Theme.cloudQuiet)
                }
                Image(systemName: group.expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.cloudQuiet)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SessionListLabels.group(group))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(sortPriority(group: groupIndex, slot: 0))
    }

    private func rowLine(_ row: SessionListRow, groupIndex: Int, rowIndex: Int) -> some View {
        let selected = selectedID == row.id
        return HStack(spacing: 8) {
            Button {
                onSelectRow(row.id)
            } label: {
                summary(row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
            .focused($focusedRow, equals: row.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SessionListLabels.row(row, hidesDetails: hidesDetails))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
            .accessibilitySortPriority(sortPriority(group: groupIndex, slot: 1 + rowIndex * 2))
            .onKeyPress(.upArrow) { moved(from: row.id, by: -1) ? .handled : .ignored }
            .onKeyPress(.downArrow) { moved(from: row.id, by: 1) ? .handled : .ignored }

            if row.canOpen {
                CardButton(title: SessionListAccessibility.openLabel, tint: Theme.cloudPrimary, filled: false) {
                    onOpenRow(row.id)
                }
                .accessibilityLabel(SessionListAccessibility.openLabel)
                .accessibilitySortPriority(sortPriority(group: groupIndex, slot: 2 + rowIndex * 2))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: Glass.rowRadius, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            }
        }
        .notchCard(CardFinish.current, radius: Glass.rowRadius)
        .animation(Motion.page(reduceMotion: reduceMotion), value: selected)
    }

    private func summary(_ row: SessionListRow) -> some View {
        let tint = color(for: row.status)
        return HStack(spacing: 10) {
            BotAvatarView.forAgent(row.name, state: avatarState(for: row.status), size: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                        .shadow(color: tint.opacity(0.85), radius: 3)
                    Text(row.name)
                        .font(Glass.bodyStrong)
                        .foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1)
                    if !hidesDetails, !row.project.isEmpty {
                        Text(row.project)
                            .font(Glass.caption)
                            .foregroundStyle(Theme.cloudQuiet)
                            .lineLimit(1)
                    }
                }
                if !hidesDetails, !row.task.isEmpty {
                    Text(row.task)
                        .font(Glass.caption)
                        .foregroundStyle(isError(row.status) ? Theme.danger : Theme.cloudSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    if row.queuedApproval { queuedBadge }
                    if let word = row.status.visibleWord {
                        Text(word)
                            .font(Glass.font(11, .semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    if row.status == .running { wave(tint) }
                    if !row.elapsedText.isEmpty {
                        Text(row.elapsedText)
                            .font(Glass.caption.monospacedDigit())
                            .foregroundStyle(Theme.cloudSecondary)
                    }
                }
            }
        }
    }

    private var queuedBadge: some View {
        Text(SessionListAccessibility.queuedWord)
            .font(Glass.font(10, .semibold))
            .foregroundStyle(Theme.ember)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(Theme.ember.opacity(0.16)))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func wave(_ tint: Color) -> some View {
        if reduceMotion {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(Self.stillBars.enumerated()), id: \.offset) { _, height in
                    Capsule().fill(tint).frame(width: 2.6, height: height)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        } else {
            LevelBars(count: 5, color: tint, active: true, height: 12)
                .accessibilityHidden(true)
        }
    }

    private var entrance: AnyTransition {
        .modifier(
            active: SessionListEntrance(
                y: CGFloat(SessionListAccessibility.offset(reduceMotion: reduceMotion)),
                scale: CGFloat(SessionListAccessibility.scale(reduceMotion: reduceMotion)),
                opacity: reduceMotion ? 1 : 0
            ),
            identity: SessionListEntrance(y: 0, scale: 1, opacity: 1)
        )
    }

    private func moved(from id: SessionListRow.ID, by step: Int) -> Bool {
        let ids = SessionListLabels.visibleRowIDs(groups: groups)
        guard let index = ids.firstIndex(of: id) else { return false }
        let next = index + step
        guard ids.indices.contains(next) else { return false }
        let target = ids[next]
        focusedRow = target
        onSelectRow(target)
        return true
    }

    private func color(for status: HubSessionStatus) -> Color {
        switch status {
        case .needsApproval: Theme.ember
        case .done: Theme.leaf
        case .error: Theme.danger
        case .loading, .absent: Theme.cloudQuiet
        case .running, .waitingForInput: Theme.accent
        }
    }

    private func isError(_ status: HubSessionStatus) -> Bool {
        if case .error = status { return true }
        return false
    }

    private func avatarState(for status: HubSessionStatus) -> BotAvatarState {
        switch status {
        case .running, .waitingForInput, .needsApproval:
            .forActivity(running: true, idleFor: 0)
        case .error(.quiet):
            .forActivity(running: false, idleFor: 600)
        default:
            .forActivity(running: false, idleFor: 0)
        }
    }

    /// Header, then the row, then Open, before the next row.
    private func sortPriority(group: Int, slot: Int) -> Double {
        Double(10_000 - group * 40 - slot)
    }

    private static let stillBars: [CGFloat] = [5, 9, 12, 8, 6]
}

/// Arriving rows use the page rise and scale. Reduce Motion passes 0 and 1, so this rests in place.
private struct SessionListEntrance: ViewModifier, Animatable {
    var y: CGFloat
    var scale: CGFloat
    var opacity: Double

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, Double> {
        get { AnimatablePair(AnimatablePair(y, scale), opacity) }
        set {
            y = newValue.first.first
            scale = newValue.first.second
            opacity = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.opacity(opacity).offset(y: y).scaleEffect(scale, anchor: .top)
    }
}

#if DEBUG
/// Hosts two synthetic groups. Opening the preview traps until the spoken labels match.
private struct SessionListPreviewHost: View {
    var reduceMotion: Bool
    @State private var groups = SessionListFixture.groups
    @State private var selectedID: String? = "docs"

    var body: some View {
        SessionListView(
            groups: groups,
            selectedID: selectedID,
            hidesDetails: false,
            reduceMotionOverride: reduceMotion,
            onToggleGroup: { id in
                guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
                groups[index].expanded.toggle()
            },
            onSelectRow: { selectedID = $0 },
            onOpenRow: { _ in }
        )
        .frame(width: 270)
        .padding(16)
        .background(Color.black)
        .onAppear { SessionListAccessibility.requireContract() }
    }
}

/// Preview host. It fails while a spoken label disagrees with the contract.
@MainActor
private struct SessionListViewPreviews: PreviewProvider {
    @ViewBuilder static var previews: some View {
        SessionListPreviewHost(reduceMotion: false).previewDisplayName("Two groups")
        SessionListPreviewHost(reduceMotion: true).previewDisplayName("Reduce Motion")
    }
}
#endif
#endif
