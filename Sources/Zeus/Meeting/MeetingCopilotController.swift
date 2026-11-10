import AppKit
import Observation
import SwiftUI
import ZeusCore

@MainActor
@Observable
final class MeetingCopilotController {
    static let shared = MeetingCopilotController()

    private(set) var transcript: MeetingTranscript?
    private(set) var isActive = false
    private let archive = MeetingArchive(url: ZeusPaths.supportDirectory.appendingPathComponent("meeting/events.jsonl"))

    func loadFixture(at url: URL) throws {
        transcript = try MeetingCopilotEngine.transcribeFixture(at: url)
        isActive = true
        try archive.append(.init(date: Date(), kind: "transcript_loaded", detail: url.lastPathComponent))
    }

    func answer(_ question: String) -> String {
        transcript?.answer(question: question) ?? "No meeting transcript yet."
    }

    func stop() {
        isActive = false
        transcript = nil
    }

    var hiddenFromCapture: Bool {
        MeetingPanelVisibility.isHiddenFromCapture(meetingActive: isActive, showInScreenShare: !ExtraPreferences.shared.hideFromScreenShare)
    }
}

struct MeetingCopilotPanel: View {
    @Bindable var model: MeetingCopilotController
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question).font(.system(size: 11, weight: .semibold, design: .rounded))
            Text(answer).font(.system(size: 11, weight: .regular, design: .rounded)).lineLimit(6)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
