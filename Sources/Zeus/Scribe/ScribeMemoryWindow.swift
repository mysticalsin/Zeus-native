import AppKit
import SwiftUI
import ZeusCore

/// The Scribe Memory window: every saved meeting in a left rail grouped Today, This week, Earlier, and the chosen
/// meeting on the right. Zeus walks in a reserved lane along the bottom. The window only reads meetings; it changes
/// one thing, the tick boxes of action items, through the same controller call the recap page uses.
@MainActor
final class ScribeMemoryWindowController {
    static let shared = ScribeMemoryWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let view = ScribeMemoryView(scribe: .shared) { WikiController.shared.showWindow() }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Scribe Memory"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        window.setAccessibilityLabel("Scribe Memory")
        window.center()
        return window
    }
}

/// One meeting prepared for the window: who spoke, the one-line outcome, and what search looks through.
struct ScribeMemoryRow: Identifiable {
    let recap: ScribeRecap
    let people: [ScribeMemoryPerson]
    let outcome: String
    let fields: ScribeMemoryFields

    var id: ScribeSessionID { recap.id }

    init(recap: ScribeRecap) {
        self.recap = recap
        let people = ScribeMemoryPeople.people(segments: recap.transcript)
        self.people = people
        outcome = ScribeMemoryOutcome.line(recap.notes)
        fields = ScribeMemoryFields(
            title: recap.title,
            summary: recap.notes.summary,
            decisions: recap.notes.decisions,
            actionItems: recap.notes.actionItems.map(\.text),
            people: people.map(\.name),
            transcript: recap.transcript.map(\.text).joined(separator: " ")
        )
    }
}

struct ScribeMemoryView: View {
    let scribe: ScribeController
    let openLearned: () -> Void

    @State private var query = ""
    @State private var filterPeople: [String] = []
    @State private var selectedID: ScribeSessionID?
    @State private var hoveredID: ScribeSessionID?
    @State private var side: ScribeMemoryLane.Side = .list
    @StateObject private var mascot = ScribeMascotDriver()

    private static let listWidth: CGFloat = 300

    var body: some View {
        ScribeOpenScope { content }
    }

    private var content: some View {
        let rows = scribe.recaps.map { ScribeMemoryRow(recap: $0) }
        let search = ScribeMemoryQuery(text: query, people: filterPeople)
        let shown = rows.filter { search.isEmpty || search.matches($0.fields) }
        let selection = shown.first { $0.id == selectedID } ?? shown.first
        return VStack(spacing: 0) {
            ScribeMemoryHeader(
                query: $query, filterPeople: $filterPeople,
                choices: ScribeMemoryQuery.filterChoices(rows.map { $0.people.map(\.name) }),
                openLearned: openLearned
            )
            HStack(spacing: 0) {
                ScribeMemoryList(
                    rows: shown, totalCount: rows.count, selectedID: selection?.id,
                    hoveredID: $hoveredID, select: { id in select(id) }
                )
                .frame(width: Self.listWidth)
                ScribeMemoryDetail(scribe: scribe, row: selection, hasAnyMeeting: !rows.isEmpty)
                    .id(selection?.id)
                    .transition(.opacity)
            }
            ScribeMemoryLane(
                driver: mascot, listWidth: Self.listWidth, side: side,
                hoveringList: hoveredID != nil, searching: !search.isEmpty, isEmpty: rows.isEmpty
            )
            .scribeEntrance(.mascot)
        }
        .background(Theme.storm)
        .preferredColorScheme(.dark)
        .onChange(of: query) { _, _ in side = .list }
    }

    private func select(_ id: ScribeSessionID) {
        selectedID = id
        side = .content
    }
}

// MARK: Header and search

private struct ScribeMemoryHeader: View {
    @Binding var query: String
    @Binding var filterPeople: [String]
    let choices: [String]
    let openLearned: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                searchField
                personMenu
                Button("What Zeus learned", action: openLearned)
                    .buttonStyle(.plain)
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                    .accessibilityHint("Opens the pages Zeus wrote from your meetings.")
            }
            if !filterPeople.isEmpty {
                HStack(spacing: 6) {
                    ForEach(filterPeople, id: \.self) { name in
                        filterChip(name)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                .accessibilityHidden(true)
            TextField("Search meetings", text: $query)
                .textFieldStyle(.plain)
                .font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudPrimary)
                .focused($focused)
                .accessibilityLabel("Search meetings")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private var personMenu: some View {
        let options = choices.filter { name in !filterPeople.contains(name) }
        if !options.isEmpty {
            Menu {
                ForEach(options, id: \.self) { name in
                    Button(name) { filterPeople.append(name) }
                }
            } label: {
                Label("With", systemImage: "person.2")
                    .font(TopBarStyle.label(11, .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityHint("Shows only meetings with this person.")
        }
    }

    private func filterChip(_ name: String) -> some View {
        Button { filterPeople.removeAll { $0 == name } } label: {
            HStack(spacing: 5) {
                Text("With \(name)").font(TopBarStyle.label(10, .semibold)).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(ScribeNotesStyle.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().strokeBorder(ScribeNotesStyle.accent.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter, with \(name)")
    }
}

// MARK: Meeting list

private struct ScribeMemoryList: View {
    let rows: [ScribeMemoryRow]
    let totalCount: Int
    let selectedID: ScribeSessionID?
    @Binding var hoveredID: ScribeSessionID?
    let select: (ScribeSessionID) -> Void

    var body: some View {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = ScribeMemoryGrouping.sections(rows.map { (id: $0.id, date: $0.recap.endedAt) }, now: Date())
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 8)
                    }
                    Text(section.bucket.title)
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudQuiet)
                        .padding(.horizontal, 10).padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.ids, id: \.self) { id in
                        if let row = byID[id] {
                            ScribeMemoryListRow(
                                row: row, bucket: section.bucket, selected: id == selectedID,
                                hover: { inside in
                                    if inside { hoveredID = id } else if hoveredID == id { hoveredID = nil }
                                },
                                select: { select(id) }
                            )
                        }
                    }
                }
                if rows.isEmpty && totalCount > 0 {
                    Text("No meetings match.")
                        .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).padding(10)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
    }
}

private struct ScribeMemoryListRow: View {
    let row: ScribeMemoryRow
    let bucket: ScribeMemoryBucket
    let selected: Bool
    let hover: (Bool) -> Void
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.recap.title)
                        .font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                    ScribeInitialStack(names: row.people.map(\.name), limit: 3, size: 16)
                }
                Text(meta)
                    .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                Text(row.outcome)
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? ScribeNotesStyle.accent.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .accessibilityLabel("\(row.recap.title), \(meta)")
        .accessibilityValue(row.outcome)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var meta: String {
        let date = row.recap.endedAt
        let when: String
        switch bucket {
        case .today: when = date.formatted(date: .omitted, time: .shortened)
        case .thisWeek: when = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .earlier: when = date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        }
        return "\(when) \u{00B7} \(ScribeMemoryOutcome.durationLabel(row.recap.duration))"
    }
}

// MARK: Detail

private struct ScribeMemoryDetail: View {
    let scribe: ScribeController
    let row: ScribeMemoryRow?
    let hasAnyMeeting: Bool

    var body: some View {
        Group {
            if let row {
                ScribeMemoryMeeting(scribe: scribe, row: row)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(hasAnyMeeting ? "Nothing to show" : "No meetings yet")
                .font(TopBarStyle.label(15, .semibold)).foregroundStyle(Theme.cloudPrimary)
            Text(hasAnyMeeting ? "Clear the search to see your meetings."
                 : "Finished meetings and their notes will show up here.")
                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScribeMemoryMeeting: View {
    let scribe: ScribeController
    let row: ScribeMemoryRow
    @State private var showTranscript = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let notes = row.recap.notes
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                section("Summary") {
                    Text(notes.summary.isEmpty ? "Nothing was said that Scribe could summarize." : notes.summary)
                        .font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                section("Decisions") { decisionRows(notes.decisions) }
                section("Action items") { actionRows(notes.actionItems) }
                if !row.people.isEmpty {
                    section("People") { peopleRows }
                }
                transcriptBlock
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.recap.title)
                .font(TopBarStyle.label(18, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("\(row.recap.endedAt.formatted(date: .complete, time: .shortened)) \u{00B7} \(ScribeMemoryOutcome.durationLabel(row.recap.duration))")
                .font(TopBarStyle.label(11).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
        }
    }

    private func section<Inner: View>(_ title: String, @ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                .accessibilityAddTraits(.isHeader)
            inner()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func decisionRows(_ decisions: [String]) -> some View {
        if decisions.isEmpty {
            Text("None found.").font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary)
        } else {
            ForEach(Array(decisions.enumerated()), id: \.offset) { _, decision in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(ScribeNotesStyle.accent).frame(width: 4, height: 4).accessibilityHidden(true)
                    Text(decision).font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func actionRows(_ items: [ScribeActionItem]) -> some View {
        if items.isEmpty {
            Text("None found.").font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary)
        } else {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button { scribe.setActionItem(index, done: !item.done, for: row.recap.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(item.done ? Theme.cloudSecondary : ScribeNotesStyle.accent)
                            .scaleEffect(item.done ? 1 : 0.92)
                            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.5), value: item.done)
                        Text(item.text).font(TopBarStyle.label(12)).strikethrough(item.done)
                            .foregroundStyle(item.done ? Theme.cloudSecondary : Theme.cloudPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.text)
                .accessibilityValue(item.done ? "Done" : "Not done")
                .accessibilityHint("Toggles done.")
            }
        }
    }

    private var peopleRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(row.people.enumerated()), id: \.offset) { _, person in
                ScribeMemoryPersonRow(person: person)
            }
        }
    }

    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showTranscript.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTranscript ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(showTranscript ? "Hide transcript" : "Show transcript")
                        .font(TopBarStyle.label(11, .semibold))
                }
                .foregroundStyle(ScribeNotesStyle.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Folds the full transcript open or closed.")
            if showTranscript {
                if row.recap.transcript.isEmpty {
                    Text("No transcript was captured.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                } else {
                    ForEach(row.recap.transcript, id: \.id) { segment in
                        ScribeMemoryTranscriptLine(segment: segment)
                    }
                }
            }
        }
    }
}

private struct ScribeMemoryPersonRow: View {
    let person: ScribeMemoryPerson

    var body: some View {
        let tint = scribeColor(ScribeSpeakerPalette.color(for: person.speaker))
        HStack(spacing: 10) {
            ScribeSpeakerDisc(initials: person.initials, tint: tint, size: 22)
            Text(person.name).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .lineLimit(1).frame(width: 140, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(tint)
                        .frame(width: max(3, proxy.size.width * CGFloat(min(1, max(0, person.share)))))
                }
            }
            .frame(height: 4)
            Text("\(person.percent)%").font(TopBarStyle.label(11).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                .frame(width: 36, alignment: .trailing)
            Text(ScribeSpeakerStats.format(person.talkSeconds))
                .font(TopBarStyle.label(11).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.name)
        .accessibilityValue("\(ScribeSpeakerStats.format(person.talkSeconds)), \(person.percent) percent of the talking")
    }
}

private struct ScribeMemoryTranscriptLine: View {
    let segment: ScribeTranscriptSegment

    var body: some View {
        let tint = scribeColor(ScribeSpeakerPalette.color(for: segment.speaker))
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(segment.speaker.displayName).font(TopBarStyle.label(10, .semibold)).foregroundStyle(tint)
                Text("\u{00B7} \(RecordlyElapsed.format(segment.start))")
                    .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
            }
            Text(segment.text).font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
