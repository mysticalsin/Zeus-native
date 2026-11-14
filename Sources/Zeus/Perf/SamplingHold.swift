import AppKit
import SwiftUI

/// Holds one reference on a sampler while a view is on screen and its window can be seen.
/// `onDisappear` alone is not enough: a Settings window that is closed or minimised keeps its hosting view,
/// so the owner also reports the window's visibility. One flag keeps start and stop balanced in any order.
@MainActor
final class SamplingHold {
    private let start: () -> Void
    private let stop: () -> Void
    private var appeared = false
    private var windowVisible = true
    private(set) var isHolding = false

    init(start: @escaping () -> Void, stop: @escaping () -> Void) {
        self.start = start
        self.stop = stop
    }

    isolated deinit {
        // SwiftUI teardown must not depend on onDisappear being delivered first.
        if isHolding { stop() }
    }

    func appear() { appeared = true; sync() }
    func disappear() { appeared = false; sync() }
    func windowVisibility(_ visible: Bool) { windowVisible = visible; sync() }

    private func sync() {
        let wanted = TickRules.isRunning(appeared: appeared, paused: false, windowVisible: windowVisible)
        guard wanted != isHolding else { return }
        isHolding = wanted
        if wanted { start() } else { stop() }
    }
}

/// Reports whether the hosting window can be seen: when the view joins or leaves a window, and after the
/// window closes, is minimised or restored, or changes occlusion. Draws nothing and takes no clicks.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(onChange: onChange) }
    func updateNSView(_ view: ReaderView, context: Context) { view.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { onChange(false); return }
            for name in WindowVisibility.changeNotifications {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.onChange(WindowVisibility.reading(after: name, in: self.window))
                    }
                })
            }
            onChange(WindowVisibility.isVisible(window))
        }
    }
}
