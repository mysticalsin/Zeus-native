import AppKit
import SwiftUI

/// An in-app control only. The coordinator owns permission, capture, transcription
/// and turn identity; this control emits intent and never accesses a device.
@MainActor
struct ExplanationTalkButton: NSViewRepresentable {
    var attemptID: UUID?
    var isListening: Bool
    var isEnabled: Bool
    var begin: () -> UUID?
    var finish: (UUID) -> Void
    var cancel: (UUID) -> Void

    func makeNSView(context: Context) -> ExplanationTalkControl { ExplanationTalkControl() }
    func updateNSView(_ view: ExplanationTalkControl, context: Context) {
        view.configure(attemptID: attemptID, isListening: isListening, isEnabled: isEnabled,
                       begin: begin, finish: finish, cancel: cancel)
    }
    static func dismantleNSView(_ view: ExplanationTalkControl, coordinator: ()) { view.dispose() }
}

@MainActor
final class ExplanationTalkControl: NSButton {
    private enum Origin { case mouse, keyboard, accessibility }
    private struct Hold {
        let origin: Origin
        let attemptID: UUID
        let finish: (UUID) -> Void
        let cancel: (UUID) -> Void
    }
    private var held: Hold?
    private var reportedAttemptID: UUID?
    private var reportedListening = false
    private weak var observedWindow: NSWindow?
    private var beginAction: (() -> UUID?)?
    private var finishAction: ((UUID) -> Void)?
    private var cancelAction: ((UUID) -> Void)?
    private(set) var disposed = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 13, weight: .semibold)
        focusRingType = .exterior
        target = self; action = #selector(accessibleToggle(_:))
        setAccessibilityIdentifier("explanation.talk")
        refreshAppearance()
    }
    required init?(coder: NSCoder) { nil }

    func configure(attemptID: UUID?, isListening: Bool, isEnabled: Bool,
                   begin: @escaping () -> UUID?, finish: @escaping (UUID) -> Void, cancel: @escaping (UUID) -> Void) {
        guard !disposed else { return }
        // The coordinator's identity also covers permission/start failures before
        // listening ever becomes true. A superseded hold must never finish or
        // cancel a replacement attempt, nor acquire its new callbacks.
        if let held, held.attemptID != attemptID { self.held = nil }
        reportedAttemptID = attemptID
        reportedListening = isListening && attemptID != nil
        beginAction = begin; finishAction = finish; cancelAction = cancel
        self.isEnabled = isEnabled
        if !isEnabled { cancelInteraction() }
        refreshAppearance()
    }

    override var acceptsFirstResponder: Bool { isEnabled && !disposed }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !disposed, held == nil else { return }
        window?.makeFirstResponder(self)
        beginHolding(.mouse)
    }
    override func mouseUp(with event: NSEvent) {
        guard held?.origin == .mouse else { return }
        finishInteraction()
    }
    override func keyDown(with event: NSEvent) {
        guard isEnabled && !disposed else { return }
        if event.keyCode == 53 { cancelInteraction(); return }
        guard event.keyCode == 49, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event); return
        }
        guard !event.isARepeat, held == nil else { return }
        beginHolding(.keyboard)
    }
    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49, held?.origin == .keyboard else { return }
        finishInteraction()
    }
    override func resignFirstResponder() -> Bool {
        if held?.origin == .keyboard { cancelInteraction() }
        return super.resignFirstResponder()
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled && !disposed else { return false }
        toggleListening()
        return true
    }
    @objc private func accessibleToggle(_ sender: Any?) { toggleListening() }
    private func toggleListening() {
        guard isEnabled && !disposed else { return }
        if held != nil || reportedListening { finishInteraction() }
        else { beginHolding(.accessibility) }
    }
    private func beginHolding(_ origin: Origin) {
        guard held == nil, isEnabled && !disposed, let finishAction, let cancelAction else { return }
        // An app shortcut may already own capture. Its existing attempt can be
        // finished by this control, but a second start must never be emitted.
        guard let attemptID = reportedAttemptID ?? beginAction?() else { refreshAppearance(); return }
        guard isEnabled && !disposed else { cancelAction(attemptID); return }
        reportedAttemptID = attemptID
        held = Hold(origin: origin, attemptID: attemptID, finish: finishAction, cancel: cancelAction)
        refreshAppearance()
    }
    private func finishInteraction() {
        guard !disposed else { return }
        let attemptID = held?.attemptID ?? (reportedListening ? reportedAttemptID : nil)
        let callback = held?.finish ?? finishAction
        guard let attemptID, let callback else { return }
        held = nil; reportedAttemptID = nil; reportedListening = false
        refreshAppearance()
        callback(attemptID)
    }
    private func cancelInteraction() {
        guard !disposed else { return }
        // The supplied identity covers capture startup as well as listening.
        // The caller withdraws it when capture has ended for transcription.
        let attemptID = held?.attemptID ?? reportedAttemptID
        let callback = held?.cancel ?? cancelAction
        guard let attemptID, let callback else { return }
        held = nil; reportedAttemptID = nil; reportedListening = false
        refreshAppearance()
        callback(attemptID)
    }
    private func refreshAppearance() {
        title = reportedListening ? (held == nil ? "Stop listening" : "Release to finish")
            : held == nil ? "Hold to talk" : "Keep holding"
        highlight(held != nil || reportedListening)
        setAccessibilityLabel(held != nil || reportedListening ? "Finish speaking" : "Start speaking")
        setAccessibilityValue(reportedListening ? "Listening" : held == nil ? "Ready" : "Starting")
        setAccessibilityHelp("Hold the mouse or Space to speak. Release to finish. Accessibility press toggles listening. Escape cancels.")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow {
            cancelInteraction()
            NotificationCenter.default.removeObserver(self)
            observedWindow = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !disposed, observedWindow !== window else { return }
        observedWindow = window
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowUnavailable(_:)), name: name, object: window)
        }
    }
    @objc private func windowUnavailable(_ notification: Notification) { cancelInteraction() }
    override func viewDidHide() { super.viewDidHide(); cancelInteraction() }

    func dispose() {
        guard !disposed else { return }
        cancelInteraction()
        disposed = true
        NotificationCenter.default.removeObserver(self)
        observedWindow = nil
        beginAction = nil; finishAction = nil; cancelAction = nil
        target = nil; action = nil; isEnabled = false
    }
}
