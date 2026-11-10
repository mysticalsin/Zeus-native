import AppKit
import SwiftUI

/// When a ticking view may run, and how often the app's pollers wake up. Pure values, so tests pin them.
enum TickRules {
    /// A view ticks only while it is on screen, not paused by its owner, and its window can be seen
    /// (a hidden menu-bar panel or a locked screen used to keep drawing, which cost a core).
    static func isRunning(appeared: Bool, paused: Bool, windowVisible: Bool) -> Bool {
        appeared && !paused && windowVisible
    }

    /// How often the timer wakes: at the view's rate while its window can be seen, once a second otherwise.
    static func timerInterval(requested: TimeInterval, windowVisible: Bool) -> TimeInterval {
        windowVisible ? clamped(requested) : hiddenCheckSeconds
    }

    /// While a window is hidden its views only check once a second whether it is back.
    static let hiddenCheckSeconds: TimeInterval = 1

    /// Never faster than the display can show (120 Hz) and never a zero-length timer.
    static func clamped(_ interval: TimeInterval) -> TimeInterval {
        max(interval.isFinite ? interval : 1, 1.0 / 120)
    }

    /// The system notification mirror is read this often, only while the mirror is on.
    static let notificationPollSeconds: TimeInterval = 4
    /// Wake-word gate checks (mic in use, lock state).
    static let wakeGateSeconds: TimeInterval = 1.5
    /// "Is another app recording?" is asked of Core Audio this often, off the main thread.
    static let micCheckSeconds: TimeInterval = 4
}

/// What a `TickingView`'s content closure receives; `date` is the tick's time, like `TimelineView`'s.
struct TickContext {
    let date: Date
}

/// Drives a view at a fixed rate from a run-loop timer.
///
/// SwiftUI's `TimelineView` makes an `NSHostingView` lay out its whole tree on every display frame
/// (120 per second on ProMotion) for as long as the timeline exists, however slowly it ticks; the
/// 12 fps Mini ZEUS alone kept a core at 20%. A timer that publishes once per tick re-evaluates only
/// this view, once per tick. It also stops by itself while the owner pauses it or its window is hidden.
@MainActor
final class TickClock: ObservableObject {
    private(set) var interval: TimeInterval = 1
    private(set) var ticks = 0
    private var appeared = false
    private var paused = false
    private(set) var windowVisible = true
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    /// Asked on every tick, so a window that was ordered out or in without a notification is still noticed.
    var windowProbe: (() -> Bool)?

    var isRunning: Bool { timer != nil }

    func configure(interval: TimeInterval, paused: Bool) {
        self.interval = TickRules.clamped(interval)
        self.paused = paused
        sync()
    }

    func appear() { appeared = true; sync() }
    func disappear() {
        appeared = false
        HiddenTickWatch.untrack(self)
        sync()
    }

    /// Called by the window probe when the window's state changes.
    func recheckWindow() {
        let visible = windowProbe?() ?? true
        guard visible != windowVisible else { return }
        windowVisible = visible
        sync()
    }

    private func sync() {
        guard appeared, !paused else {
            timer?.invalidate(); timer = nil; timerInterval = 0
            HiddenTickWatch.untrack(self)
            return
        }
        guard windowVisible else {
            timer?.invalidate(); timer = nil; timerInterval = 0
            HiddenTickWatch.track(self)
            return
        }
        HiddenTickWatch.untrack(self)
        // Visible: tick at the view's own rate. A hidden window holds no timer.
        let wanted = TickRules.timerInterval(requested: interval, windowVisible: windowVisible)
        if timer != nil, timerInterval == wanted { return }
        timer?.invalidate()
        // Fire on a grid shared by every clock (multiples of the interval since the reference date), with no
        // slack: clocks at 24 and 12 fps then tick in the same run-loop turn and the notch redraws once for both.
        let now = Date.timeIntervalSinceReferenceDate
        let first = Date(timeIntervalSinceReferenceDate: (now / wanted).rounded(.up) * wanted)
        let timer = Timer(fire: first, interval: wanted, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        timerInterval = wanted
    }

    private func fire() {
        recheckWindow()
        guard TickRules.isRunning(appeared: appeared, paused: paused, windowVisible: windowVisible) else { return }
        ticks &+= 1
        objectWillChange.send()
    }
}

struct TickingView<Content: View>: View {
    let interval: TimeInterval
    var paused = false
    let content: (TickContext) -> Content

    @StateObject private var clock = TickClock()

    init(interval: TimeInterval, paused: Bool = false, @ViewBuilder content: @escaping (TickContext) -> Content) {
        self.interval = interval
        self.paused = paused
        self.content = content
    }

    var body: some View {
        let _ = clock.ticks // re-evaluated on every tick, nothing else
        content(TickContext(date: Date()))
            // The probe is an NSView; ImageRenderer (snapshots) would draw it as a yellow placeholder.
            .background { if !TopBarStyle.isSnapshot { WindowVisibilityProbe(clock: clock) } }
            .onAppear { clock.configure(interval: interval, paused: paused); clock.appear() }
            .onDisappear { clock.disappear() }
            .onChange(of: interval) { clock.configure(interval: interval, paused: paused) }
            .onChange(of: paused) { clock.configure(interval: interval, paused: paused) }
    }
}

/// One slow timer for every hidden clock, so a hidden window does not keep its own timer
/// and still notices when it is shown again.
@MainActor
enum HiddenTickWatch {
    private final class Box {
        weak var clock: TickClock?
        init(_ clock: TickClock) { self.clock = clock }
    }

    private static var clocks: [ObjectIdentifier: Box] = [:]
    private static var timer: Timer?

    static var isWatching: Bool { timer != nil }

    static func track(_ clock: TickClock) {
        clocks[ObjectIdentifier(clock)] = Box(clock)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: TickRules.hiddenCheckSeconds, repeats: true) { _ in
            MainActor.assumeIsolated { sweep() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func untrack(_ clock: TickClock) {
        clocks.removeValue(forKey: ObjectIdentifier(clock))
        if clocks.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func sweep() {
        let snapshot = clocks
        for (id, box) in snapshot {
            guard let clock = box.clock else {
                clocks.removeValue(forKey: id)
                continue
            }
            clock.recheckWindow()
        }
        if clocks.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// Tells the clock about the hosting window: whether it is ordered in, not minimised and not faded out
/// (the buddy overlay stays ordered in at alpha 0 while hidden).
/// (Occlusion is not used: the transparent notch panel reports itself occluded while it is drawn.)
private struct WindowVisibilityProbe: NSViewRepresentable {
    let clock: TickClock

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.clock = clock
        clock.windowProbe = { [weak view] in view?.windowIsVisible ?? true }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        weak var clock: TickClock?
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        var windowIsVisible: Bool {
            guard let window else { return false }
            return window.isVisible && !window.isMiniaturized && window.alphaValue > 0.01
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clock?.recheckWindow() }
                })
            }
            clock?.recheckWindow()
        }
    }
}
