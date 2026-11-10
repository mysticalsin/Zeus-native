import AppKit
import Intents
import Observation
import SwiftUI
import ZeusCore

/// Runs routines at their time. One NSBackgroundActivityScheduler is armed for the next run
/// only (no polling); the system defers it while the Mac sleeps, and a wake catches up once.
@MainActor
@Observable
final class RoutineRunner {
    static let shared = RoutineRunner()

    private(set) var routines: [Routine] = []
    private(set) var runs: [RoutineRun] = []
    private(set) var running: Set<UUID> = []
    private let store: RoutineStore
    private var scheduler: NSBackgroundActivityScheduler?
    private var wakeObserver: NSObjectProtocol?
    private let card = RoutineCardWindow()
    private var relaunchGuard = RoutineRelaunchGuard()

    /// Shown in the Routines pane: a file that was set aside, or a save that failed.
    private(set) var problem: String?
    /// Set when an unreadable file could not be moved aside; nothing is saved over it.
    private var saveBlocked = false

    init(store: RoutineStore = .standard) {
        self.store = store
        let loaded = store.loadChecked()
        routines = loaded.contents.routines
        runs = loaded.contents.runs
        if loaded.unreadable {
            do {
                let kept = try store.setAsideUnreadable()
                problem = "Your routines file couldn't be read. It was kept as \(kept.lastPathComponent)."
            } catch {
                saveBlocked = true
                problem = "Your routines file couldn't be read and couldn't be moved aside, so changes won't be saved."
            }
            NSLog("Zeus routines: %@", problem ?? "")
        }
    }

    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RoutineRunner.shared.runDue() }
        }
        runDue()
    }

    // MARK: Editing

    func add() -> Routine {
        let routine = Routine(name: "New routine", prompt: "", schedule: RoutineSchedule(days: .weekdays, hour: 9, minute: 0))
        routines.append(routine)
        persist()
        return routine
    }

    func add(_ routine: Routine) {
        routines.append(routine)
        persist()
    }

    func update(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        var updated = routine
        // Editing the time never fires a run for a slot that already passed today.
        if updated.schedule != routines[index].schedule, updated.lastRun == nil { updated.created = Date() }
        routines[index] = updated
        persist()
    }

    func delete(_ id: UUID) {
        routines.removeAll { $0.id == id }
        persist()
    }

    // MARK: Running

    /// Runs whatever is due now, then arms the scheduler for the next one.
    func runDue() {
        let now = Date()
        for routine in RoutinePlanner.due(routines, now: now) where !running.contains(routine.id) {
            guard let slot = routine.schedule.missed(lastRun: routine.lastRun, created: routine.created, now: now),
                  relaunchGuard.shouldRun(routine: routine, scheduled: slot) else { continue }
            relaunchGuard.markRan(routineID: routine.id, scheduled: slot)
            run(routine)
        }
        armScheduler()
    }

    func run(_ routine: Routine, manual: Bool = false) {
        guard !running.contains(routine.id) else { return }
        running.insert(routine.id)
        mark(routine.id, ranAt: Date())
        Task {
            let result = await Self.execute(routine)
            running.remove(routine.id)
            let run = RoutineRun(routineID: routine.id, routineName: routine.name, date: Date(), engine: result.engine?.rawValue,
                                 output: result.text, failed: result.failed)
            runs.insert(run, at: 0)
            persist()
            showCard(run, manual: manual)
        }
    }

    private static func execute(_ routine: Routine) async -> (text: String, engine: RouterEngine?, failed: Bool) {
        let settings = RouterSettings.shared
        let decision = ModelRouter.route(task: RouterTask.classify(routine.prompt), installed: Set(settings.installed.keys),
                                         usage: ModelRouter.usage(from: UsageModel.shared.providers), choice: routine.engine)
        guard let engine = decision.engine else { return (decision.reason, nil, true) }
        let provider: BrainProvider = if engine == .claude || settings.installed[engine] == nil {
            ClaudeCLIProvider()
        } else {
            CLIEngineProvider(engine: engine, path: settings.installed[engine]!)
        }
        let request = BrainRequest(transcript: routine.prompt, axSummary: VoiceTurnController.context(), systemPrompt: ChatPrompt.system)
        var parser = ZeusTagStreamParser()
        var text = ""
        do {
            for try await event in provider.send(request) {
                guard case .textDelta(let delta) = event else { continue }
                for case .text(let piece) in parser.feed(delta) { text += piece }
            }
            for case .text(let piece) in parser.finish() { text += piece }
            let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (answer.isEmpty ? "No answer came back." : answer, engine, answer.isEmpty)
        } catch {
            return (VoiceTurnController.spokenError(error), engine, true)
        }
    }

    private func mark(_ id: UUID, ranAt date: Date) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].lastRun = date
        persist()
    }

    /// A quiet card (no sound). In full screen or Focus the result waits in history.
    private func showCard(_ run: RoutineRun, manual: Bool) {
        let focused = INFocusStatusCenter.default.authorizationStatus == .authorized
            && INFocusStatusCenter.default.focusStatus.isFocused == true
        guard manual || ProactiveQuiet.allowsCard(fullScreen: FullScreenDetector.frontAppIsFullScreen(), focusActive: focused) else { return }
        card.show(run)
    }

    private func armScheduler() {
        scheduler?.invalidate()
        scheduler = nil
        guard let next = RoutinePlanner.nextWake(routines, now: Date()) else { return }
        let activity = NSBackgroundActivityScheduler(identifier: "app.zeus.mac.routines")
        activity.repeats = false
        activity.interval = max(next.timeIntervalSinceNow, 60)
        activity.tolerance = 60
        activity.qualityOfService = .utility
        activity.schedule { completion in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { RoutineRunner.shared.runDue() }
                completion(.finished)
            }
        }
        scheduler = activity
    }

    private func persist() {
        if !saveBlocked {
            do {
                try store.save(.init(routines: routines, runs: runs))
                if problem?.hasPrefix("Couldn't save") == true { problem = nil }
            } catch {
                problem = "Couldn't save your routines: \(error.localizedDescription)"
                NSLog("Zeus routines: %@", problem ?? "")
            }
        }
        runs = Array(runs.prefix(RoutineStore.historyLimit))
        armScheduler()
    }
}

// MARK: Result card

@MainActor
final class RoutineCardWindow {
    private var panel: BriefPanel?
    private var dismissal: DispatchWorkItem?

    func show(_ run: RoutineRun) {
        let panel = self.panel ?? {
            let panel = BriefPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onEscape = { [weak self] in self?.hide() }
            return panel
        }()
        panel.contentView = NSHostingView(rootView: RoutineCardView(run: run, dismiss: { [weak self] in self?.hide() }))
        let size = panel.contentView?.fittingSize ?? CGSize(width: 400, height: 200)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrame(CGRect(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 12, width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: "Routine \(run.routineName) finished",
            .priority: NSAccessibilityPriorityLevel.low.rawValue,
        ])
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
        self.panel = panel
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
    }
}

struct RoutineCardView: View {
    let run: RoutineRun
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: run.failed ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(run.failed ? Theme.ember : Theme.bolt).accessibilityHidden(true)
                Text(run.routineName).font(.system(size: 13.5, weight: .bold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let engine = run.engine.flatMap(RouterEngine.init(rawValue:)) { RouterEngineBadge(engine: engine, reason: nil) }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cloudQuiet)
                        .frame(width: 22, height: 22).contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Dismiss")
                .keyboardShortcut(.cancelAction)
            }
            MarkdownBlocksView(text: String(run.output.prefix(600)), size: 12, color: run.failed ? Theme.danger : Theme.cloudPrimary)
                .lineLimit(8)
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.output, forType: .string)
                }
                Button("Save to Brain…") { BrainCaptureWindow.shared.show(title: run.routineName, body: run.output, source: "routine") }
                Spacer()
            }
            .buttonStyle(PlainTextButtonStyle())
            .font(TopBarStyle.label(11, .semibold))
        }
        .padding(14)
        .frame(width: 400)
        .background(Theme.storm.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.panelRadius + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius + 4, style: .continuous).strokeBorder(TopBarStyle.tileStroke))
        .preferredColorScheme(.dark)
    }
}
