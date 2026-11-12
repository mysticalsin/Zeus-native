import AppKit
import QuartzCore
import SwiftUI
import ZeusCore

/// Native display timing for active assistant motion. Unlike a fixed Timer, the NSView-bound link
/// follows its current screen, including 240 Hz-capable displays. The OS chooses delivered cadence.
/// Main-run-loop callbacks publish synchronously: no Tasks or queued main updates can accumulate.
struct DisplaySynchronizedView<Content: View>: View {
    var paused = false
    var preferredFramesPerSecond = 240
    var until: Date?
    let content: (TickContext) -> Content
    @StateObject private var clock = DisplayAnimationClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(paused: Bool = false, preferredFramesPerSecond: Int = 240, until: Date? = nil,
         @ViewBuilder content: @escaping (TickContext) -> Content) {
        self.paused = paused
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.until = until
        self.content = content
    }

    var body: some View {
        let now = Date()
        let expired = until.map { !$0.timeIntervalSinceReferenceDate.isFinite || $0 <= now } ?? false
        content(clock.presentationContext(at: now, staticFrame: paused || reduceMotion || expired || TopBarStyle.isSnapshot))
            .background { if !TopBarStyle.isSnapshot { DisplayAnimationProbe(clock: clock) } }
            .onAppear { configure(); clock.appear() }
            .onDisappear { clock.disappear() }
            .onChange(of: paused) { configure() }
            .onChange(of: preferredFramesPerSecond) { configure() }
            .onChange(of: until) { configure() }
            .onChange(of: reduceMotion) { configure() }
    }

    private func configure() {
        clock.configure(paused: paused || TopBarStyle.isSnapshot, reduceMotion: reduceMotion,
                        preferredFramesPerSecond: preferredFramesPerSecond, until: until)
    }
}

@MainActor
final class DisplayAnimationClock: ObservableObject {
    private(set) var context = TickContext(date: Date())
    private(set) var metrics = DisplayCallbackMetrics()
    private(set) var appeared = false
    private(set) var paused = true
    private(set) var reduceMotion = false
    private(set) var preferredFramesPerSecond = 240
    private(set) var deadline = DisplayAnimationDeadline()
    weak var probe: DisplayAnimationProbeView?

    func configure(paused: Bool, reduceMotion: Bool, preferredFramesPerSecond: Int, until: Date? = nil) {
        self.paused = paused
        self.reduceMotion = reduceMotion
        self.preferredFramesPerSecond = preferredFramesPerSecond
        deadline.configure(until: until?.timeIntervalSinceReferenceDate, now: Date.timeIntervalSinceReferenceDate)
        probe?.synchronize()
    }

    func appear() { appeared = true; probe?.synchronize() }
    func disappear() { appeared = false; probe?.invalidateLink() }
    var wantsLink: Bool { appeared && !paused && !reduceMotion && !deadline.reached }

    /// A paused display link must not freeze the timestamp used to present new producer states.
    /// A normal SwiftUI update still samples now; it does not start a timer or a display callback.
    func presentationContext(at now: Date, staticFrame: Bool) -> TickContext {
        if deadline.reached {
            return TickContext(date: Date(timeIntervalSinceReferenceDate: deadline.settledTime(
                now: now.timeIntervalSinceReferenceDate, lastFrame: context.date.timeIntervalSinceReferenceDate)))
        }
        return staticFrame || !wantsLink ? TickContext(date: now) : context
    }

    func settleExpiredDeadline(at now: Date, notify: Bool) {
        guard deadline.finishIfNeeded(at: now.timeIntervalSinceReferenceDate) else { return }
        if notify { objectWillChange.send() }
        context = TickContext(date: now)
        probe?.invalidateLink()
    }

    fileprivate func publish(targetTimestamp: Double, deliveredAt: Double) {
        guard wantsLink, probe?.mayPublish == true,
              let date = DisplayAnimationPolicy.presentationTime(wallNow: Date.timeIntervalSinceReferenceDate,
                  targetTimestamp: targetTimestamp, deliveredAt: deliveredAt),
              metrics.record(target: targetTimestamp, delivered: deliveredAt) else { return }
        objectWillChange.send()
        context = TickContext(date: Date(timeIntervalSinceReferenceDate: date))
        if deadline.finishIfNeeded(at: date) { probe?.invalidateLink() }
        metrics.recordCallbackWork(CACurrentMediaTime() - deliveredAt)
    }
}

private struct DisplayAnimationProbe: NSViewRepresentable {
    let clock: DisplayAnimationClock
    func makeNSView(context: Context) -> DisplayAnimationProbeView { DisplayAnimationProbeView(clock: clock) }
    func updateNSView(_ view: DisplayAnimationProbeView, context: Context) { view.synchronize(notifyDeadline: false) }
    static func dismantleNSView(_ view: DisplayAnimationProbeView, coordinator: ()) { view.detach() }
}

/// Non-drawing, non-interactive native attachment. No application-wide window discovery or timers.
@MainActor
final class DisplayAnimationProbeView: NSView {
    private weak var clock: DisplayAnimationClock?
    // AppKit owns mutations on the main actor. Nonisolated destruction only invalidates resources.
    nonisolated(unsafe) private var link: CADisplayLink?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var alphaObservation: NSKeyValueObservation?
    private let callbackTarget = DisplayAnimationTarget()
    private var closing = false
    private(set) var requestedFramesPerSecond = 0
    var hasDisplayLink: Bool { link != nil }
    var isDisplayLinkPaused: Bool { link?.isPaused ?? true }

    init(clock: DisplayAnimationClock) {
        self.clock = clock
        super.init(frame: .zero)
        setAccessibilityElement(false)
        callbackTarget.owner = self
        clock.probe = self
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        link?.invalidate()
        alphaObservation?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateLink()
        removeObservers()
        closing = false
        if let window {
            let names: [Notification.Name] = [
                NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if self.window?.isVisible == true { self.closing = false }
                        self.synchronize()
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closing = true; self?.invalidateLink() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.synchronize() }
            })
            alphaObservation = window.observe(\.alphaValue, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            }
        }
        synchronize()
    }

    override func viewDidHide() { super.viewDidHide(); synchronize() }
    override func viewDidUnhide() { super.viewDidUnhide(); synchronize() }

    var mayPublish: Bool {
        guard let clock, let window else { return false }
        return DisplayAnimationPolicy.mayPublish(appeared: clock.appeared, paused: clock.paused,
            reduceMotion: clock.reduceMotion, attached: true, hidden: isHiddenOrHasHiddenAncestor,
            windowVisible: window.isVisible && !closing, miniaturized: window.isMiniaturized,
            windowAlpha: window.alphaValue)
    }

    func synchronize(notifyDeadline: Bool = true) {
        clock?.settleExpiredDeadline(at: Date(), notify: notifyDeadline)
        guard let clock, clock.wantsLink, !closing, let window, let screen = window.screen else {
            invalidateLink()
            return
        }
        let rate = DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: screen.maximumFramesPerSecond,
                                                                  preferred: clock.preferredFramesPerSecond)
        guard rate > 0 else { invalidateLink(); return }
        if link == nil {
            let newLink = displayLink(target: callbackTarget, selector: #selector(DisplayAnimationTarget.tick(_:)))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
        if requestedFramesPerSecond != rate {
            let frames = Float(rate)
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: frames, maximum: frames, preferred: frames)
            requestedFramesPerSecond = rate
        }
        // NSView's display link itself suppresses callbacks while ordered out/off-display, then
        // resumes on that view's display. Keeping it attached avoids a hidden polling timer.
        // Alpha/miniaturization are explicit because transparent panels can remain ordered in.
        link?.isPaused = isHiddenOrHasHiddenAncestor || window.isMiniaturized
            || !window.alphaValue.isFinite || window.alphaValue <= 0.01
    }

    func invalidateLink() {
        link?.invalidate()
        link = nil
        requestedFramesPerSecond = 0
    }

    func detach() {
        invalidateLink()
        removeObservers()
        if clock?.probe === self { clock?.probe = nil }
        clock = nil
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        alphaObservation?.invalidate()
        alphaObservation = nil
    }

    fileprivate func tick(_ displayLink: CADisplayLink) {
        guard displayLink === link, let clock else { displayLink.invalidate(); return }
        guard mayPublish else { synchronize(); return }
        let target = displayLink.targetTimestamp
        clock.publish(targetTimestamp: target, deliveredAt: CACurrentMediaTime())
    }
}

@MainActor
private final class DisplayAnimationTarget: NSObject {
    weak var owner: DisplayAnimationProbeView?
    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.tick(link)
    }
}
