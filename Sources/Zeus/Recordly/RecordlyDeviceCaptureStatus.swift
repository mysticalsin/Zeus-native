import SwiftUI
import ZeusCore

/// Microphone and camera status inside the Recordly page. Hidden while that capture is idle,
/// so the rest of the top bar keeps its layout. No new window.
struct RecordlyDeviceCaptureStatus: View {
    private var capture: RecordlyDeviceCaptureController { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if capture.showsRecordingIndicator {
                HStack(spacing: 6) {
                    RecordlyPulseDotView()
                    Text(capture.statusText)
                        .font(TopBarStyle.label(10, .semibold))
                        .foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(2)
                    if let started = capture.startedAt {
                        TickingView(interval: 0.5) { context in
                            Text(RecordlyElapsed.format(max(0, context.date.timeIntervalSince(started))))
                                .font(TopBarStyle.label(10, .semibold).monospacedDigit())
                                .foregroundStyle(TopBarStyle.rec)
                                .accessibilityLabel("Elapsed time")
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(capture.statusText)
            } else if !capture.statusText.isEmpty {
                Text(capture.statusText)
                    .font(TopBarStyle.label(10))
                    .foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        switch capture.phase {
        case .ready:
            Button(capture.recordButtonTitle) { capture.record() }
                .buttonStyle(.plain)
                .font(TopBarStyle.label(10, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
                .accessibilityIdentifier("recordly.device.record")
        case .recording:
            HStack(spacing: 8) {
                if capture.showsRecordingIndicator {
                    Button("Stop") { capture.stop() }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(10, .semibold))
                        .foregroundStyle(TopBarStyle.rec)
                }
                Button("Cancel") { capture.cancel() }
                    .buttonStyle(.plain)
                    .font(TopBarStyle.label(10, .semibold))
                    .foregroundStyle(Theme.cloudSecondary)
            }
        case .saved:
            Button("Done") { capture.dismiss() }
                .buttonStyle(.plain)
                .font(TopBarStyle.label(10, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(failure.settingsLinks, id: \.device) { link in
                    Button(link.device.settingsButtonTitle) { capture.openSettings(link) }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(10, .semibold))
                        .foregroundStyle(Theme.bolt)
                }
                Button("Done") { capture.dismiss() }
                    .buttonStyle(.plain)
                    .font(TopBarStyle.label(10, .semibold))
                    .foregroundStyle(Theme.cloudSecondary)
            }
        case .idle, .requestingPermission, .finishing:
            EmptyView()
        }
    }
}
