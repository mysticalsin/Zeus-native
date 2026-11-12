import AppKit
import SwiftUI
import ZeusCore

private final class ExplanationCardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The card's only interactive control. It accepts the first click so a non-key, non-activating
/// panel never needs to take focus from the app the owner is working in.
private final class ExplanationCardCloseButton: NSButton {
    var onPress: (@MainActor () -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc fileprivate func pressed() { onPress?() }
}

/// A desktop card for explanations that are not marks on the screen (charts, diagrams, cards, 3D)
/// from one pointing turn. It is placed by the pure layout in ZeusCore beside, never over, what
/// the owner pointed at; the only interactive piece is its close button, and Esc also closes it.
/// A card belongs to one turn generation: a late callback from a cancelled turn is ignored.
@MainActor
final class ExplanationDesktopCard {
    struct Input {
        var token: UUID
        var scene: ExplanationScene
        /// The exact spoken text of the current beat.
        var caption: String
        /// Non-capture objects created by the current beat. Used only by the split-into-beats rung.
        var beatIDs: Set<String>
        var anchors: PointingCardAnchors
        var displayID: UInt32?
        var pointer: CGPoint?
    }

    private struct Signature: Equatable {
        var objects: [String]
        var beatIDs: [String]
        var caption: String
        var anchors: PointingCardAnchors
        var displayID: UInt32?
    }

    /// Match the pointing overlay: above menus. Chat-owned surfaces never use this card.
    var windowLevel: NSWindow.Level = .floating
    var visibleInShare = false
    /// The owner closed the card (button or Esc).
    var onDismissed: (() -> Void)?
    /// The display's visible frame and the bands to keep clear. Live by default; fixtures inject a fixed frame.
    var screenProvider: @MainActor (UInt32?, CGPoint?) -> (usable: ExplanationRect, reserved: [ExplanationRect])? = { displayID, pointer in
        ExplanationDesktopCard.screenGeometry(displayID: displayID, pointer: pointer)
    }

    private(set) var lifecycle = ExplanationCardLifecycle()
    private(set) var lastLayout: ExplanationCardLayout?
    private let model = ExplanationCardModel()
    private var cardPanel: ExplanationCardPanel?
    private var closePanel: ExplanationCardPanel?
    private var connectorPanel: ExplanationCardPanel?
    private var connectorHost: NSHostingView<ExplanationCardConnectorView>?
    private var signature: Signature?
    private var fit: ExplanationCardContentBuilder.Fit?
    private var focus: Set<String>?
    private var keyMonitors: [Any] = []
    private var lingerTask: Task<Void, Never>?

    var isVisible: Bool { cardPanel?.isVisible == true }
    var ownedWindows: [NSWindow] { [cardPanel, closePanel, connectorPanel].compactMap { $0 } }
    var caption: String { model.caption }

    isolated deinit {
        lingerTask?.cancel()
        removeKeyMonitors()
        closeWindows()
    }

    // MARK: Lifecycle

    /// A new pointing turn. Whatever an earlier turn left on screen goes first.
    func begin(token: UUID) {
        lifecycle.begin(token: token)
        lingerTask?.cancel(); lingerTask = nil
        closeWindows()
        signature = nil; lastLayout = nil; fit = nil; focus = nil
    }

    /// The turn ended or was cancelled: the card goes and no late callback can bring it back.
    func end() {
        lifecycle.end()
        lingerTask?.cancel(); lingerTask = nil
        closeWindows()
        signature = nil; lastLayout = nil; fit = nil; focus = nil
    }

    func dismissByOwner() {
        guard lifecycle.token != nil else { return }
        lifecycle.dismissByOwner()
        lingerTask?.cancel(); lingerTask = nil
        closeWindows()
        onDismissed?()
    }

    /// After the turn finishes normally the card stays long enough to read, then goes.
    func beginLinger(seconds: Double = 25) {
        guard let token = lifecycle.token, isVisible else { return }
        lingerTask?.cancel()
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.lifecycle.token == token else { return }
            self.end()
        }
    }

    // MARK: Update

    func update(_ input: Input) {
        guard lifecycle.admits(input.token) else { return }
        guard let full = ExplanationCardContentBuilder.cardScene(from: input.scene) else {
            closeWindows(); signature = nil; return
        }
        let current = Signature(objects: full.objects.values.map { "\($0.id):\($0.geometry.kind.rawValue)" }.sorted(),
                                beatIDs: input.beatIDs.sorted(), caption: input.caption,
                                anchors: input.anchors, displayID: input.displayID)
        if current != signature {
            signature = current
            place(input, full: full)
        }
        refresh(input)
    }

    private func place(_ input: Input, full: ExplanationScene) {
        let beatScene = input.beatIDs.isEmpty ? nil
            : ExplanationCardContentBuilder.cardScene(from: input.scene, focus: input.beatIDs)
        let fullFit = ExplanationCardContentBuilder.fit(full)
        let beatFit = beatScene.map { ExplanationCardContentBuilder.fit($0) }
        guard let screen = screenProvider(input.displayID, input.pointer) else {
            lastLayout = nil; closeWindows(); return
        }
        let request = ExplanationCardRequest(
            usable: screen.usable, anchor: input.anchors.anchor, protected: input.anchors.protected,
            reserved: screen.reserved, content: ExplanationCardContentBuilder.content(fullFit, caption: input.caption),
            beat: beatFit.map { ExplanationCardContentBuilder.content($0, caption: input.caption) })
        let layout = ExplanationCardPlacement.place(request)
        lastLayout = layout
        fit = layout.beatOnly ? beatFit : fullFit
        focus = layout.beatOnly ? input.beatIDs : nil
        show(layout)
    }

    /// Per-frame content refresh. The placement is not recomputed here.
    private func refresh(_ input: Input) {
        guard let fit, lastLayout?.frame != nil,
              let scene = ExplanationCardContentBuilder.cardScene(from: input.scene, focus: focus) else { return }
        let shifted = ExplanationCardContentBuilder.applying(fit, to: scene)
        model.scene = shifted
        model.caption = input.caption
        model.accessibilitySummary = shifted.objects.values.filter { $0.geometry.kind != .group }
            .sorted { $0.id < $1.id }.map(\.accessibleDescription).joined(separator: ". ")
    }

    // MARK: Windows

    private func show(_ layout: ExplanationCardLayout) {
        guard let frame = layout.frame else { closeWindows(); return }
        let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        model.visualSize = layout.visualSize.map { CGSize(width: $0.width, height: $0.height) }
        model.worldHeight = layout.showsWorld ? CGFloat(layout.worldHeight) : 0
        model.captionHeight = CGFloat(layout.captionHeight)
        let card = cardPanel ?? makeCardPanel()
        card.setFrame(rect, display: true)
        card.level = windowLevel
        let close = closePanel ?? makeClosePanel()
        close.setFrame(NSRect(x: rect.maxX - 34, y: rect.maxY - 34, width: 28, height: 28), display: true)
        close.level = windowLevel
        showConnector(layout.connector)
        card.orderFrontRegardless() // Non-activating: never makeKey, never activates another app.
        close.orderFrontRegardless()
        installKeyMonitors()
    }

    private func showConnector(_ connector: ExplanationCardConnector?) {
        guard let connector, hypot(connector.to.x - connector.from.x, connector.to.y - connector.from.y) >= 6 else {
            connectorPanel?.orderOut(nil); return
        }
        let minX = min(connector.from.x, connector.to.x) - 10, maxX = max(connector.from.x, connector.to.x) + 10
        let minY = min(connector.from.y, connector.to.y) - 10, maxY = max(connector.from.y, connector.to.y) + 10
        let frame = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        // Global points are y-up; the SwiftUI canvas is y-down.
        let view = ExplanationCardConnectorView(from: CGPoint(x: connector.from.x - minX, y: maxY - connector.from.y),
                                                to: CGPoint(x: connector.to.x - minX, y: maxY - connector.to.y))
        let panel = connectorPanel ?? makeConnectorPanel(view)
        connectorHost?.rootView = view
        panel.setFrame(frame, display: true)
        panel.level = windowLevel
        panel.orderFrontRegardless()
    }

    private func basePanel(_ rect: NSRect) -> ExplanationCardPanel {
        let panel = ExplanationCardPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        return panel
    }

    private func makeCardPanel() -> ExplanationCardPanel {
        let panel = basePanel(NSRect(x: 0, y: 0, width: 460, height: 300))
        panel.hasShadow = true
        panel.ignoresMouseEvents = true // Click-through: only the close panel takes input.
        let host = NSHostingView(rootView: ExplanationCardView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        cardPanel = panel
        return panel
    }

    private func makeClosePanel() -> ExplanationCardPanel {
        let panel = basePanel(NSRect(x: 0, y: 0, width: 28, height: 28))
        panel.hasShadow = false
        let button = ExplanationCardCloseButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.isBordered = false
        button.imagePosition = .imageOnly
        let symbol = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close explanation")?
            .withSymbolConfiguration(symbol)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Close (Esc)"
        button.setAccessibilityLabel("Close explanation")
        button.target = button
        button.action = #selector(ExplanationCardCloseButton.pressed)
        button.onPress = { [weak self] in self?.dismissByOwner() }
        panel.contentView = button
        closePanel = panel
        return panel
    }

    private func makeConnectorPanel(_ view: ExplanationCardConnectorView) -> ExplanationCardPanel {
        let panel = basePanel(NSRect(x: 0, y: 0, width: 20, height: 20))
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        connectorHost = host
        connectorPanel = panel
        return panel
    }

    private func closeWindows() {
        removeKeyMonitors()
        for panel in [cardPanel, closePanel, connectorPanel] {
            panel?.orderOut(nil); panel?.contentView = nil; panel?.close()
        }
        cardPanel = nil; closePanel = nil; connectorPanel = nil; connectorHost = nil
        model.scene = nil; model.caption = ""; model.visualSize = nil
        model.worldHeight = 0; model.captionHeight = 0; model.accessibilitySummary = ""
    }

    // MARK: Esc

    private func installKeyMonitors() {
        guard keyMonitors.isEmpty else { return }
        // A global key monitor needs the Accessibility permission the pointing hotkey already uses.
        if AccessibilityGate.trusted, let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.dismissByOwner() }
        }) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.dismissByOwner() } }
            return event
        }) {
            keyMonitors.append(local)
        }
    }

    private func removeKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    // MARK: Screens

    /// The turn display's visible frame (menu bar and a docked Dock excluded) plus bands to keep clear.
    static func screenGeometry(displayID: UInt32?, pointer: CGPoint?) -> (usable: ExplanationRect, reserved: [ExplanationRect])? {
        let screens = NSScreen.screens
        let screen = displayID.flatMap { id in screens.first { $0.displayID == id } }
            ?? pointer.flatMap { point in screens.first { $0.frame.contains(point) } } ?? NSScreen.main
        guard let screen else { return nil }
        let full = screen.frame, visible = screen.visibleFrame
        var reserved = [ExplanationRect(x: full.minX, y: full.maxY - 40, width: full.width, height: 40)] // menu bar
        if let defaults = UserDefaults(suiteName: "com.apple.dock"), defaults.bool(forKey: "autohide") {
            switch defaults.string(forKey: "orientation") ?? "bottom" {
            case "left": reserved.append(ExplanationRect(x: full.minX, y: full.minY, width: 96, height: full.height))
            case "right": reserved.append(ExplanationRect(x: full.maxX - 96, y: full.minY, width: 96, height: full.height))
            default: reserved.append(ExplanationRect(x: full.minX, y: full.minY, width: full.width, height: 96))
            }
        }
        return (ExplanationRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height), reserved)
    }
}
