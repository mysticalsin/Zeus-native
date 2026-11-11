import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI
import ZeusCore

// The idle Scribe page (docs/SCRIBE-RECORDLY-REDESIGN.md). Red never appears here: the capture control is a
// glass ring, permission problems are banners with a button, and the one moving thing is a slow decorative wave
// that is drawn by the app (the microphone stays off until the person presses the control).

/// What the idle page needs to know about system access. Read without asking for anything.
struct ScribeAccess: Equatable {
    var microphone: PermissionState
    var namesTrusted: Bool

    nonisolated static func read() -> ScribeAccess {
        ScribeAccess(
            microphone: CapturePermissions.microphoneState(authorizationRaw: AVCaptureDevice.authorizationStatus(for: .audio).rawValue),
            namesTrusted: AXIsProcessTrusted()
        )
    }
}

enum ScribeSettingsLink {
    static func open(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct ScribeIdle: View {
    let scribe: ScribeController
    @State private var access = ScribeAccess.read()

    init(scribe: ScribeController) {
        self.scribe = scribe
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScribeIdleLeft(scribe: scribe, access: access)
                .frame(width: 340, alignment: .topLeading)
            ScribeRecentMeetings(scribe: scribe)
        }
        .background { ScribeAccessibilityFocusAnchor(label: "Scribe", focusToken: scribe.focusToken) }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        access = ScribeAccess.read()
        ScribeUpNextModel.shared.refresh()
    }
}

// MARK: Left column

private struct ScribeIdleLeft: View {
    let scribe: ScribeController
    let access: ScribeAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if access.microphone == .denied {
                ScribePermissionBanner(
                    symbol: "mic.slash.fill",
                    message: "Microphone access is off for Zeus.",
                    actionTitle: "Open Microphone settings",
                    hint: "Opens System Settings so you can turn the microphone on for Zeus."
                ) { ScribeSettingsLink.open(pane: "Privacy_Microphone") }
            }
            ScribeUpNextCard(scribe: scribe).scribeEntrance(.upNext)
            ScribeCaptureRow(scribe: scribe)
            ScribeSourceChipRow(access: access, captureAvailable: scribe.captureAvailable).scribeEntrance(.chips)
            if let disclosure = scribe.cloudDisclosure {
                ScribeIssueLine(text: disclosure, lineLimit: 2)
            }
        }
    }
}

/// A missing permission: an icon, one sentence and the button that fixes it.
struct ScribePermissionBanner: View {
    let symbol: String
    let message: String
    let actionTitle: String
    let hint: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ember)
                .accessibilityHidden(true)
            Text(message)
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            NotchActionButton(title: actionTitle, tint: Theme.cloudPrimary, filled: false, action: action)
                .accessibilityHint(hint)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ember.opacity(0.14)))
        .accessibilityElement(children: .contain)
    }
}

// MARK: Up next

private struct ScribeUpNextCard: View {
    let scribe: ScribeController

    var body: some View {
        Group {
            if let meeting = ScribeUpNextModel.shared.meeting {
                ScribeUpNextContent(scribe: scribe, meeting: meeting)
            } else {
                ScribeReadyContent()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

private struct ScribeReadyContent: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready when you are")
                    .font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Text("Press the button to take notes on a call or in the room.")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScribeUpNextContent: View {
    let scribe: ScribeController
    let meeting: ScribeUpNextMeeting

    var body: some View {
        HStack(spacing: 10) {
            ScribeCallLogo(app: meeting.app)
            VStack(alignment: .leading, spacing: 3) {
                Text("Up next")
                    .font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudQuiet)
                Text(meeting.slot.title)
                    .font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                ScribeUpNextDetail(meeting: meeting)
            }
            Spacer(minLength: 0)
            NotchActionButton(title: "Take notes", tint: Theme.accent) { startWith(meeting) }
                .accessibilityHint("Starts Scribe with the title and guests of this meeting.")
        }
    }

    private func startWith(_ meeting: ScribeUpNextMeeting) {
        scribe.meetingTitleHint = meeting.slot.title
        scribe.meetingAttendeeHint = meeting.slot.attendeeNames
        scribe.start()
    }
}

/// "in 4 min", the call app and who is invited. The minute text is the only thing that refreshes (every 30 s,
/// and not while the window is hidden).
private struct ScribeUpNextDetail: View {
    let meeting: ScribeUpNextMeeting

    var body: some View {
        HStack(spacing: 8) {
            TickingView(interval: 30) { context in
                Text(summary(at: context.date))
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
            .fixedSize()
            ScribeInitialStack(names: meeting.slot.attendeeNames)
        }
    }

    private func summary(at now: Date) -> String {
        let time = ScribeUpNext.startsIn(meeting.slot.start, now: now)
        guard let app = ScribeUpNext.appName(meeting.app) else { return time }
        return "\(time) \u{00B7} \(app)"
    }
}

private struct ScribeCallLogo: View {
    let app: ScribeCallApp?

    private var bundleID: String? {
        switch app {
        case .teams: "com.microsoft.teams2"
        case .zoom: "us.zoom.xos"
        case .meet, .other, nil: nil
        }
    }

    var body: some View {
        Group {
            if let bundleID {
                AlertAppIcon(bundleID: bundleID, size: 28)
            } else {
                Image(systemName: app == nil ? "calendar" : "video.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.10)))
            }
        }
        .accessibilityLabel(ScribeUpNext.appName(app) ?? "Calendar meeting")
    }
}

/// Overlapping initial discs for the first few people, then "+N".
struct ScribeInitialStack: View {
    let names: [String]
    var limit = 4
    var size: CGFloat = 18

    var body: some View {
        let shown = Array(names.prefix(limit))
        HStack(spacing: -5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                ScribeInitialDisc(name: name, size: size)
            }
            if names.count > shown.count {
                Text("+\(names.count - shown.count)")
                    .font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudSecondary)
                    .padding(.leading, 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.isEmpty ? "No guests listed" : "Guests: \(names.joined(separator: ", "))")
    }
}

struct ScribeInitialDisc: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        let tint = scribeColor(ScribeSpeakerPalette.color(for: .participant(name)))
        Text(ScribeInitials.of(name))
            .font(TopBarStyle.label(size * 0.45, .bold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.storm))
            .overlay(Circle().fill(tint.opacity(0.22)))
            .overlay(Circle().strokeBorder(Theme.storm, lineWidth: 1.5))
    }
}

// MARK: Capture control and the breathing wave

private struct ScribeCaptureRow: View {
    let scribe: ScribeController

    private static let bars = 28

    var body: some View {
        HStack(spacing: 14) {
            ScribeBreathingWaveView(bars: Self.bars, range: 0..<(Self.bars / 2)).scribeEntrance(.wave)
            RecordlyCaptureControl(
                visual: .idle, enabled: scribe.captureAvailable, countdownBeganAt: nil,
                help: scribe.unavailableReason ?? "Start taking notes",
                spokenSource: nil, idleSymbol: "waveform", idleLabel: "Start Scribe", stopLabel: "Stop Scribe"
            ) { scribe.start() }
            .accessibilityHint("Starts listening to a meeting and writes your notes when it ends.")
            .scribeLightSweep()
            .scribeEntrance(.capture)
            .ownedJourneyControl("scribe.start")
            ScribeBreathingWaveView(bars: Self.bars, range: (Self.bars / 2)..<Self.bars).scribeEntrance(.wave)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Half of a slow, synthetic waveform: it breathes about once every six seconds. It is drawn by the app and does
/// not read the microphone. It stands still under Reduce Motion and while the window is hidden (TickingView).
struct ScribeBreathingWaveView: View {
    let bars: Int
    let range: Range<Int>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TickingView(interval: 1.0 / 15, paused: reduceMotion) { context in
            wave(at: reduceMotion || TopBarStyle.isSnapshot ? 1.5 : context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: CGFloat(range.count) * 6, height: 30)
        .accessibilityHidden(true)
    }

    private func wave(at t: Double) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(range), id: \.self) { index in
                let level = ScribeBreathingWave.level(index: index, count: bars, t: t)
                Capsule()
                    .fill(Theme.cloudPrimary.opacity(0.16 + 0.34 * level))
                    .frame(width: 3, height: 4 + 24 * CGFloat(level))
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: Source chips

private struct ScribeSourceChipRow: View {
    let access: ScribeAccess
    let captureAvailable: Bool

    var body: some View {
        let chips = ScribeSourceChips.chips(
            microphone: access.microphone, captureAvailable: captureAvailable, namesTrusted: access.namesTrusted)
        HStack(spacing: 6) {
            ForEach(chips, id: \.kind) { chip in
                ScribeSourceChipView(chip: chip)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScribeSourceChipView: View {
    let chip: ScribeSourceChip

    var body: some View {
        if chip.status == .needsPermission {
            Button { open() } label: { label }
                .buttonStyle(.plain)
                .help(chip.detail)
                .accessibilityLabel("\(chip.kind.title), \(chip.status.label)")
                .accessibilityHint(chip.detail)
        } else {
            label
                .help(chip.detail)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(chip.kind.title), \(chip.status.label)")
                .accessibilityHint(chip.detail)
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            marker
            Text(chip.kind.title)
                .font(TopBarStyle.label(10, .semibold))
                .foregroundStyle(chip.status == .on ? Theme.cloudPrimary : Theme.cloudSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(chip.status == .needsPermission ? Theme.ember.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private var marker: some View {
        switch chip.status {
        case .on:
            Circle().fill(Theme.leaf).frame(width: 6, height: 6)
        case .off:
            Circle().strokeBorder(Theme.cloudQuiet, lineWidth: 1.2).frame(width: 6, height: 6)
        case .needsPermission:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.ember)
        }
    }

    private func open() {
        switch chip.kind {
        case .microphone: ScribeSettingsLink.open(pane: "Privacy_Microphone")
        case .names: ScribeSettingsLink.open(pane: "Privacy_Accessibility")
        case .callAudio: break
        }
    }
}

// MARK: Recent meetings

private struct ScribeRecentMeetings: View {
    let scribe: ScribeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Recent meetings").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                NotchActionButton(title: "Memory", tint: Theme.cloudSecondary, filled: false) {
                    ScribeMemoryWindowController.shared.show()
                }
                .accessibilityHint("Opens all your meetings with search, notes and who spoke.")
            }
            if scribe.recaps.isEmpty {
                ScribeNoRecentMeetings()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(scribe.recaps) { recap in
                            ScribeRecentCard(scribe: scribe, recap: recap)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ScribeNoRecentMeetings: View {
    var body: some View {
        HStack(spacing: 10) {
            if let image = LivingPoseArt.image(.idle) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 48, height: 48).accessibilityHidden(true)
            }
            Text("Finished meetings and their notes show up here.")
                .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

/// One finished meeting: title, when and how long, who was there and the first thing left to do.
private struct ScribeRecentCard: View {
    let scribe: ScribeController
    let recap: ScribeRecap

    var body: some View {
        let people = ScribeMemoryPeople.people(segments: recap.transcript)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button { scribe.openRecap(recap.id) } label: {
                    ScribeRecentCardText(recap: recap, people: people)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open notes for \(recap.title)")
                .accessibilityHint("Shows the summary, action items, private notes and transcript.")
                Button { scribe.requestDelete(recap.id) } label: {
                    Image(systemName: "trash").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(recap.title) permanently")
                Button { scribe.dismissRecap(recap.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(recap.title) from recent meetings")
                .accessibilityHint("Hides it from this list. The saved meeting stays on this Mac until you delete it permanently.")
            }
            if scribe.pendingDeleteID == recap.id {
                ScribeDeleteConfirm(scribe: scribe, id: recap.id)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct ScribeRecentCardText: View {
    let recap: ScribeRecap
    let people: [ScribeMemoryPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(recap.title).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                Text(when).font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
            if !people.isEmpty {
                ScribePeopleChips(people: people)
            }
            nextStep
            if let badge = ScribeRecapNote.badge(for: recap.transcriptionNote) {
                Text(badge).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.ember)
            }
            if recap.micExcludedDuringCall {
                Text(ScribeMicCallText.recapLine).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.ember)
            }
        }
    }

    private var when: String {
        "\(recap.endedAt.formatted(date: .abbreviated, time: .shortened)) \u{00B7} \(ScribeMemoryOutcome.durationLabel(recap.duration))"
    }

    @ViewBuilder
    private var nextStep: some View {
        if let action = ScribeMemoryOutcome.firstOpenAction(recap.notes) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "square").font(.system(size: 9)).foregroundStyle(ScribeNotesStyle.accent)
                Text(action).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("First action item: \(action)")
        } else {
            Text(ScribeMemoryOutcome.line(recap.notes, limit: 110))
                .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
        }
    }
}

/// The first few people of a meeting with their colour and first name, then "+N".
struct ScribePeopleChips: View {
    let people: [ScribeMemoryPerson]
    var limit = 3

    var body: some View {
        let shown = Array(people.prefix(limit))
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, person in
                let tint = scribeColor(ScribeSpeakerPalette.color(for: person.speaker))
                HStack(spacing: 4) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(Self.firstName(person.name)).font(TopBarStyle.label(10, .semibold)).foregroundStyle(tint).lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.14)))
            }
            if people.count > shown.count {
                Text("+\(people.count - shown.count)").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("People: \(people.map(\.name).joined(separator: ", "))")
    }

    static func firstName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
}
