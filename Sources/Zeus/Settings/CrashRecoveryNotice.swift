import Observation
import SwiftUI
import ZeusCore

/// The sentence Settings shows after a crash log is saved, or when a restart loop stops.
@MainActor
@Observable
final class CrashRecoveryNoticeModel {
    static let shared = CrashRecoveryNoticeModel()
    var message: String?
    var saved = false

    func apply(_ outcome: CrashRecoveryOutcome) {
        saved = outcome.savedMessage != nil
        message = outcome.fallback
    }
}

/// Quiet status under the report form. Absent unless a crash was saved or a restart was refused.
struct CrashRecoveryNotice: View {
    private var model: CrashRecoveryNoticeModel { .shared }

    var body: some View {
        let saved = model.saved
        let message = model.message
        let motion = IssueReportMotion(reduced: Motion.reduced)
        if !saved, message == nil {
            EmptyView()
        } else {
            GSCard {
                if saved {
                    GSStatus(ok: true, text: IssueReportMailbox.savedMessage)
                        .padding(.top, 16)
                        .accessibilityLabel(IssueReportMailbox.savedMessage)
                }
                if let message, !message.isEmpty {
                    GSInfo(text: message)
                }
            }
            .animation(motion.statusDuration.map { .easeOut(duration: $0) }, value: message)
            .accessibilityIdentifier("settings.report.recovery")
        }
    }
}
