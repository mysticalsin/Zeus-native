import AppKit
import ApplicationServices
import CoreLocation
import EventKit
import Observation
import SwiftUI
import UserNotifications
import ZeusCore

/// "Allow all" in Settings > Permissions: runs `PermissionSweep` against the same request code the
/// single Allow buttons use. Nothing here grants access: macOS still asks, and switches in System
/// Settings are still turned on by the person. The sweep only removes the hunting: it asks for each
/// one in turn, opens the exact pane, shows a small guide and moves on as soon as the switch is on.
@MainActor
@Observable
final class PermissionSweepRunner {
    typealias Item = PermissionSweep.Item
    typealias Access = PermissionSweep.Access

    private(set) var state = PermissionSweep.State()
    /// The last read of every access, for "N of M allowed".
    private(set) var access: [Item: Access] = [:]

    @ObservationIgnored private let services: OnboardingServices
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var guide: PermissionSweepGuide?

    static let progressKey = "permissions.sweep.progress"

    init(services: OnboardingServices) {
        self.services = services
    }

    private var permissions: PermissionsModel { services.permissions }
    private static var now: Double { Date().timeIntervalSinceReferenceDate }

    var isRunning: Bool { state.isRunning }
    var progressLine: String { PermissionSweep.progressLine(access) }
    var allAllowed: Bool { PermissionSweep.allowedCount(access) == Item.allCases.count }
    var needsRestart: Bool { state.phase == .finished(needsRestart: true) }

    // MARK: Actions

    /// The "Allow all" button.
    func start() {
        Task { await send { .start(access: $0, resumed: nil, now: Self.now) } }
    }

    func skip() {
        Task { await send { .skip(access: $0, now: Self.now) } }
    }

    /// "Done" on a step that may only show as allowed after Zeus reopens (Screen Recording).
    func done() {
        Task { await send { .done(access: $0, now: Self.now) } }
    }

    func cancel() {
        perform(apply(.cancel))
    }

    /// Reads every access for the progress line without starting anything (the page calls this).
    func refreshProgress() {
        Task { access = await read() }
    }

    /// At launch: a sweep that macOS interrupted (Screen Recording's "Quit and Reopen") picks up where
    /// it stopped. `show` runs only when there is still something to do.
    func resumeIfSaved(show: @escaping @MainActor () -> Void) {
        let progress = Self.savedProgress()
        guard PermissionSweep.shouldResume(progress, now: Self.now) else {
            if progress != nil { UserDefaults.standard.removeObject(forKey: Self.progressKey) }
            return
        }
        Task {
            await send { .start(access: $0, resumed: progress, now: Self.now) }
            if isRunning { show() }
        }
    }

    /// Quits and opens Zeus again once this process has ended (a second copy would hand off and exit).
    func restartZeus() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$1\"",
                             String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("[ZEUS] permissions: restart failed: %@", error.localizedDescription)
        }
    }

    // MARK: Model

    private func send(_ make: ([Item: Access]) -> PermissionSweep.Event) async {
        let current = await read()
        access = current
        perform(apply(make(current)))
    }

    private func apply(_ event: PermissionSweep.Event) -> [PermissionSweep.Effect] {
        let (next, effects) = PermissionSweep.reduce(state, event)
        state = next
        return effects
    }

    private func perform(_ effects: [PermissionSweep.Effect]) {
        for effect in effects {
            switch effect {
            case .ask(let item):
                Task { await ask(item) }
            case .openSettings(let item, let request):
                openSettings(item, request: request)
            case .showGuide:
                if guide == nil { guide = PermissionSweepGuide(runner: self) }
                guide?.show()
            case .hideGuide:
                guide?.close()
                guide = nil
            case .startPolling:
                startPolling()
            case .stopPolling:
                polling?.cancel()
                polling = nil
            case .save(let progress):
                if let data = try? JSONEncoder().encode(progress) { UserDefaults.standard.set(data, forKey: Self.progressKey) }
            case .clearProgress:
                UserDefaults.standard.removeObject(forKey: Self.progressKey)
            }
        }
    }

    private static func savedProgress() -> PermissionSweep.Progress? {
        guard let data = UserDefaults.standard.data(forKey: progressKey) else { return nil }
        return try? JSONDecoder().decode(PermissionSweep.Progress.self, from: data)
    }

    /// Switches turned on in System Settings, and prompts without a completion (Location), show up here.
    private func startPolling() {
        polling?.cancel()
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.isRunning else { return }
                await self.send { .poll(access: $0, now: Self.now) }
            }
        }
    }

    // MARK: Requests (the same calls as each row's Allow button)

    private func ask(_ item: Item) async {
        switch item {
        case .microphone, .speech:
            // One "voice" request asks for both; the second step joins it instead of asking again.
            await permissions.requestVoice()
        case .camera:
            await permissions.requestCamera()
        case .calendar:
            await permissions.requestEventAccess(.calendar)
        case .reminders:
            await permissions.requestEventAccess(.reminders)
        case .notifications:
            await services.requestNotifications()
        case .location:
            // No completion: the poll sees the answer.
            services.allowLocation()
            return
        case .automation:
            permissions.requestAutomation()
            while permissions.automationAsking {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
        case .accessibility, .inputMonitoring, .fullDiskAccess, .screenRecording:
            return
        }
        await send { .promptAnswered(item, access: $0, now: Self.now) }
    }

    private func openSettings(_ item: Item, request: Bool) {
        if request {
            switch item {
            case .accessibility: permissions.requestAccessibility()
            case .inputMonitoring: KeyListenAccess.requestInputMonitoring()
            case .screenRecording: permissions.requestScreen()
            default: break
            }
        }
        if let url = URL(string: item.settingsURL) { NSWorkspace.shared.open(url) }
    }

    // MARK: Reading access (never prompts)

    private func read() async -> [Item: Access] {
        permissions.refresh()
        var notifications = Access.notAsked
        if OnboardingServices.hasBundle {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional { notifications = .allowed }
            else if status != .notDetermined { notifications = .denied }
        }
        let fullDisk = await Task.detached(priority: .utility) { OnboardingServices.hasFullDiskAccess() }.value

        var result: [Item: Access] = [:]
        result[.microphone] = Self.access(VoicePermissions.mic)
        result[.speech] = Self.access(VoicePermissions.speech)
        result[.camera] = Self.access(permissions.cameraPermissionState)
        result[.calendar] = Self.access(EKEventStore.authorizationStatus(for: .event))
        result[.reminders] = Self.access(EKEventStore.authorizationStatus(for: .reminder))
        result[.notifications] = notifications
        let place = location.authorizationStatus
        result[.location] = place == .authorizedAlways || place == .authorized ? .allowed
            : place == .notDetermined ? .notAsked : .denied
        if permissions.granted[.automation] == true {
            result[.automation] = .allowed
        } else {
            result[.automation] = Automation.accessByTarget.values.contains(.refused) ? .denied : .notAsked
        }
        result[.accessibility] = AXIsProcessTrusted() ? .allowed : .notAsked
        // Accessibility or Input Monitoring is enough for keys from other apps (the row says so).
        result[.inputMonitoring] = KeyListenAccess.granted ? .allowed : .notAsked
        result[.fullDiskAccess] = fullDisk ? .allowed : .notAsked
        result[.screenRecording] = Self.access(permissions.screenPermissionState)
        return result
    }

    private static func access(_ state: PermissionState) -> Access {
        switch state {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        case .denied: .denied
        }
    }

    private static func access(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}

/// The small floating guide shown while the sweep runs. It stays above System Settings and never
/// takes focus from it.
@MainActor
final class PermissionSweepGuide {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let panel: Panel
    static let size = NSSize(width: 560, height: 64)

    init(runner: PermissionSweepRunner) {
        panel = Panel(contentRect: NSRect(origin: .zero, size: Self.size),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PermissionSweepGuideView(runner: runner))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    func show() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.maxY - Self.size.height - 12))
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }
}

private struct PermissionSweepGuideView: View {
    let runner: PermissionSweepRunner

    var body: some View {
        let phase = runner.state.phase
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.title3).foregroundStyle(Theme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PermissionSweep.guideText(phase)).font(.callout.weight(.medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(runner.progressLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if case .guiding(let item) = phase, item.mayNeedRestart {
                Button("Done") { runner.done() }.accessibilityLabel("Done, \(item.title) is on")
            }
            Button("Skip") { runner.skip() }.accessibilityLabel("Skip this one")
            Button("Stop") { runner.cancel() }.accessibilityLabel("Stop allowing")
        }
        .padding(.horizontal, 16)
        .frame(width: PermissionSweepGuide.size.width, height: PermissionSweepGuide.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Allow all guide")
    }
}
