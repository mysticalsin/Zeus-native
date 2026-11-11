import AVFoundation
import Foundation
import ZeusCore

/// Performs what the core `ScribeAutoStartMachine` decides. It reads the signals the call watcher already
/// gathers (calendar, running call apps, which process holds the microphone), asks the machine, and then
/// shows the banner, starts Scribe or opens the end window. It never asks for any permission: automatic start
/// needs Microphone to be allowed already, otherwise the machine asks instead.
@MainActor
final class ScribeAutoStartController {
    static let shared = ScribeAutoStartController()

    private(set) var machine = ScribeAutoStartMachine()
    private var timer: Timer?

    private init() {
        let banner = ScribeMeetingBanner.shared.model
        banner.onPrimary = { [weak self] in self?.accept() }
        banner.onSecondary = { [weak self] in self?.decline() }
    }

    /// The monotonic clock the machine's deadlines use.
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// One reading from the call watcher, every poll and every microphone wake-up.
    func ingest(scan: ScribeCallScan, slots: [ScribeCalendarSlot], date: Date) {
        let evidence = ScribeMeetingEvidence(
            date: date,
            slots: slots,
            micApps: scan.calls.map(\.app),
            presentApps: scan.runningCallApps.map(\.app),
            mode: ScribeAutoStartMode.current(),
            micPermissionGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            activity: ScribeActivity(ScribeController.shared.phase),
            autoConsentGiven: ScribeAutoStartConsent.isGiven(),
            callWindows: scan.callWindows
        )
        perform(machine.handle(.evidence(evidence, now: now)))
        syncTimer()
    }

    func accept() {
        perform(machine.handle(.accept(now: now)))
        syncTimer()
    }

    func decline() {
        perform(machine.handle(.decline(now: now)))
        syncTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ScribeMeetingBanner.shared.hide()
    }

    private func tick() {
        perform(machine.handle(.tick(now: now)))
        if case .countingDown(let meeting, let deadline) = machine.state {
            ScribeMeetingBanner.shared.updateCountdown(meeting, seconds: Self.secondsLeft(deadline: deadline, now: now))
        }
        // The end timer only advances on evidence, so while the call looks over, read the signals again each second.
        if machine.needsFreshEvidence { ScribeCallWatcher.shared.pollNow() }
        syncTimer()
    }

    private func perform(_ effects: [ScribeAutoStartMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .showAsk(let meeting):
                // The earlier "Starts in N min" card has done its job.
                ScribeCallPopup.shared.hide()
                ScribeMeetingBanner.shared.showAsk(meeting)
            case .showCountdown(let meeting):
                ScribeCallPopup.shared.hide()
                let seconds = machine.bannerDeadline.map { Self.secondsLeft(deadline: $0, now: now) } ?? 0
                ScribeMeetingBanner.shared.showCountdown(meeting, seconds: seconds)
            case .showConsentAsk(let meeting):
                ScribeCallPopup.shared.hide()
                ScribeMeetingBanner.shared.showConsent(meeting)
            case .recordConsent:
                ScribeAutoStartConsent.record()
            case .showNextMeeting(let meeting):
                ScribeMeetingBanner.shared.showNextMeeting(meeting)
            case .hideBanner:
                ScribeMeetingBanner.shared.hide()
            case .startRecording(let meeting):
                startScribe(for: meeting)
            case .requestEnd:
                ScribeController.shared.requestEnd()
            }
        }
    }

    private func startScribe(for meeting: ScribeMeeting) {
        let controller = ScribeController.shared
        guard !controller.phase.isActive else { return }
        controller.meetingTitleHint = ScribeCallPromptText.meetingTitle(for: meeting.promptDecision)
        if let slot = meeting.slot { controller.meetingAttendeeHint = slot.attendeeNames }
        controller.meetingCallHint = ScribeCallWatcher.shared.recordingIdentity(for: .callDetected(meeting.callApp))
        controller.start()
    }

    /// Whole seconds left, counting the one in progress (5, 4, 3, 2, 1).
    private static func secondsLeft(deadline: TimeInterval, now: TimeInterval) -> Int {
        max(0, Int((deadline - now).rounded(.up)))
    }

    /// One second timer, only while a banner has a deadline or the call looks over.
    private func syncTimer() {
        if machine.needsTick {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
}
