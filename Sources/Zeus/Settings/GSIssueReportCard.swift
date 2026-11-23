import SwiftUI
import ZeusCore

/// Settings › Report. One section: pick a bug or a feature request, write a short note, send.
/// The recent local log is attached. With no destination configured, the report stays in the outbox.
struct ReportSettingsPage: View {
    var body: some View {
        GSPageHeading(section: .report, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        IssueReportCard()
    }
}

struct IssueReportCard: View {
    @State private var kind: IssueReportKind = .bug
    @State private var note = ""
    @State private var notice: String?
    @State private var accepted = false

    private var motion: IssueReportMotion { IssueReportMotion(reduced: Motion.reduced) }
    private var canSend: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let motion = motion
        GSCard {
            Text("Send a bug or a feature request. The recent local log is attached.")
                .font(GS.rowText).foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Kind").font(GS.rowTitle).foregroundStyle(GS.text)
                GSSegmentedChoice(
                    label: "Kind",
                    options: IssueReportKind.allCases.map { ($0.title, $0) },
                    selection: kind,
                    onSelect: { kind = $0 }
                )
            }
            .padding(.vertical, 12)
            .animation(motion.selectionDuration.map { .easeOut(duration: $0) }, value: kind)
            .accessibilityIdentifier("settings.report.kind")
            GSDivider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Note").font(GS.rowTitle).foregroundStyle(GS.text)
                TextEditor(text: noteBinding)
                    .snapshotSafeText(note, placeholder: "What happened, or what you want", multiline: true)
                    .font(OB.font(13.5))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(GS.text)
                    .padding(8)
                    .frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                    .accessibilityLabel("Note")
            }
            .padding(.vertical, 14)
            .accessibilityIdentifier("settings.report.note")
            GSDivider()
            VStack(alignment: .leading, spacing: 8) {
                Button("Send", action: send)
                    .buttonStyle(IssueReportSendStyle(reduced: motion.reduced))
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send report")
                    .accessibilityIdentifier("settings.report.send")
                if let notice {
                    if accepted {
                        GSStatus(ok: true, text: notice)
                    } else {
                        Text(notice).font(GS.rowText).foregroundStyle(GS.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 14)
            .animation(motion.statusDuration.map { .easeOut(duration: $0) }, value: notice)
            .accessibilityIdentifier("settings.report.status")
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { note },
            set: { note = String($0.prefix(IssueReportMailbox.noteLimit)) }
        )
    }

    private func send() {
        let root = IssueReportLocations.root(support: ZeusPaths.supportDirectory)
        let destination = IssueReportDestination.read(file: IssueReportLocations.destinationFile(in: root))
        let delivery = IssueReportMailbox.submit(
            kind: kind,
            note: note,
            log: localLog(),
            destination: destination,
            outbox: IssueReportLocations.outbox(in: root)
        )
        notice = delivery.message
        accepted = delivery.folder != nil
        if accepted { note = "" }
    }

    /// The in-memory recorder, plus the voice log when it is a real file. Vault folders are never passed in.
    private func localLog() -> String {
        let voice = VoiceLog.url
        let file = FileManager.default.fileExists(atPath: voice.path) ? voice : nil
        return IssueReportLog.attach(recorder: FlightRecorder.shared.text(), file: file)
    }
}

/// The shared press: a quieter fill while held, and a 2% scale only when motion is allowed.
private struct IssueReportSendStyle: ButtonStyle {
    var reduced: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let motion = IssueReportMotion(reduced: reduced)
        configuration.label
            .font(OB.font(14, .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OB.controlAccentFill)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? motion.pressScale : 1)
            .animation(motion.pressDuration.map { .easeOut(duration: $0) }, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
