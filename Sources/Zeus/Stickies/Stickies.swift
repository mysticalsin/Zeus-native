import AppKit
import Observation
import SwiftUI
import ZeusCore

extension StickyNote.Tint {
    var color: Color {
        switch self {
        case .bolt: Theme.bolt
        case .sky: Theme.sky
        case .leaf: Theme.leaf
        case .ember: Theme.ember
        case .violet: TopBarStyle.violet
        case .cloud: Theme.cloudSecondary
        }
    }
}

/// One sticky's live state.
@MainActor
@Observable
final class StickyState {
    var note: StickyNote
    var editing: Bool
    var expanded = false
    /// The last save failed (disk full, folder not writable): the header says so.
    var saveFailed = false

    init(note: StickyNote, editing: Bool) {
        self.note = note
        self.editing = editing
    }
}

/// Owns every sticky: restores them at launch, saves on change, one panel per note.
@MainActor
final class StickiesController {
    static let shared = StickiesController()

    private let store: StickyStore
    private var states: [UUID: StickyState] = [:]
    private var panels: [UUID: StickyPanel] = [:]
    private var pendingSave: DispatchWorkItem?

    init(store: StickyStore = .standard) {
        self.store = store
        // Typing saves after a short pause; quitting inside that pause must not lose the last words.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Writes any change still waiting for its pause (called when the app quits).
    func flush() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        save()
    }

    /// Asks before deleting a note that has text; an empty one goes at once.
    private func confirmDelete(_ id: UUID) {
        guard let state = states[id] else { return }
        if state.note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return delete(id) }
        let alert = NSAlert()
        alert.messageText = "Delete this sticky?"
        alert.informativeText = "\"\(state.note.title)\" will be removed. This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { delete(id) }
    }

    func restore() {
        for note in store.load() { open(StickyState(note: note, editing: false)) }
    }

    /// A new sticky, near the middle of the screen, ready to type in.
    @discardableResult
    func new(text: String = "", tint: StickyNote.Tint = .bolt) -> UUID {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        let offset = Double(states.count % 6) * 24
        let frame = CGRect(x: visible.midX - 130 + offset, y: visible.midY - 110 - offset, width: 260, height: 220)
        let state = StickyState(note: StickyNote(text: text, tint: tint, placement: .floating(frame)), editing: text.isEmpty)
        open(state)
        save()
        panels[state.note.id]?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return state.note.id
    }

    func delete(_ id: UUID) {
        panels[id]?.orderOut(nil)
        panels[id] = nil
        states[id] = nil
        save()
    }

    func changed(_ id: UUID) {
        states[id]?.note.updated = Date()
        scheduleSave()
    }

    /// Floating ↔ edge shelf.
    func toggleEdge(_ id: UUID) {
        guard let state = states[id], let panel = panels[id] else { return }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if state.note.isOnEdge {
            let frame = CGRect(x: visible.midX - 130, y: visible.midY - 110, width: 260, height: 220)
            state.note.placement = .floating(frame)
            panel.setFrame(frame, display: true, animate: true)
        } else {
            let edge: StickyNote.Edge = panel.frame.midX < visible.midX ? .left : .right
            state.note.placement = .edge(edge, top: EdgeShelf.top(for: panel.frame, visible: visible))
            state.expanded = false
            place(state, animate: true)
        }
        panel.isMovable = !state.note.isOnEdge
        changed(id)
    }

    // MARK: Panels

    private func open(_ state: StickyState) {
        let id = state.note.id
        states[id] = state
        let panel = StickyPanel(contentRect: CGRect(x: 0, y: 0, width: 260, height: 220),
                                styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 180, height: 120)
        panel.setAccessibilityTitle("Sticky note: \(state.note.title)")
        panel.contentView = NSHostingView(rootView: StickyView(state: state, actions: StickyActions(
            changed: { [weak self] in self?.changed(id) },
            toggleEdge: { [weak self] in self?.toggleEdge(id) },
            delete: { [weak self] in self?.confirmDelete(id) },
            new: { [weak self] in self?.new() },
            saveToBrain: { BrainCaptureWindow.shared.show(title: state.note.title, body: state.note.text, source: "sticky") }
        )))
        panel.onHover = { [weak self] inside in self?.hovered(id, inside: inside) }
        panel.onMoved = { [weak self] in self?.moved(id) }
        panels[id] = panel
        place(state, animate: false)
        panel.isMovable = !state.note.isOnEdge
        panel.orderFrontRegardless()
    }

    private func place(_ state: StickyState, animate: Bool) {
        guard let panel = panels[state.note.id] else { return }
        switch state.note.placement {
        case .floating(let frame):
            panel.setFrame(frame, display: true, animate: animate)
        case .edge(let edge, let top):
            let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let size = CGSize(width: max(panel.frame.width, 180), height: max(panel.frame.height, 120))
            panel.setFrame(EdgeShelf.frame(edge: edge, top: top, expanded: state.expanded, visible: visible, size: size),
                           display: true, animate: animate)
        }
    }

    /// Edge cards slide out while the pointer is over them (tracking area, no timer).
    private func hovered(_ id: UUID, inside: Bool) {
        guard let state = states[id], state.note.isOnEdge, state.expanded != inside else { return }
        state.expanded = inside
        place(state, animate: true)
    }

    /// Dropping a floating card near a screen edge tucks it into the edge shelf.
    private func moved(_ id: UUID) {
        guard let state = states[id], let panel = panels[id], !state.note.isOnEdge else { return }
        let visible = panel.screen?.visibleFrame ?? .zero
        if let edge = EdgeShelf.snapEdge(for: panel.frame, visible: visible) {
            state.note.placement = .edge(edge, top: EdgeShelf.top(for: panel.frame, visible: visible))
            state.expanded = true
            panel.isMovable = false
        } else {
            state.note.placement = .floating(panel.frame)
        }
        changed(id)
    }

    // MARK: Saving

    /// Typing saves half a second after the last key (a one-shot, only while editing).
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { StickiesController.shared.save() } }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        pendingSave = nil
        let notes = states.values.map(\.note).sorted { $0.created < $1.created }
        let failed: Bool
        do {
            try store.save(notes)
            failed = false
        } catch {
            failed = true
        }
        for state in states.values where state.saveFailed != failed { state.saveFailed = failed }
    }
}

final class StickyPanel: NSPanel {
    var onHover: (Bool) -> Void = { _ in }
    var onMoved: () -> Void = {}
    private var tracking: NSTrackingArea?

    override var canBecomeKey: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateTracking()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onMoved()
    }

    private func updateTracking() {
        guard let view = contentView else { return }
        if let tracking { view.removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: view.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        view.addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

struct StickyActions {
    let changed: () -> Void
    let toggleEdge: () -> Void
    let delete: () -> Void
    let new: () -> Void
    let saveToBrain: () -> Void
}

/// The note card: a tinted header with controls, then the text (edit or Markdown preview).
struct StickyView: View {
    let state: StickyState
    let actions: StickyActions

    var body: some View {
        let tint = state.note.tint.color
        HStack(spacing: 0) {
            if case .edge(.right, _) = state.note.placement { edgeStrip(tint) }
            VStack(alignment: .leading, spacing: 0) {
                header(tint)
                Group {
                    if state.editing {
                        TextEditor(text: Binding(get: { state.note.text }, set: { state.note.text = $0; actions.changed() }))
                            .font(TopBarStyle.label(13))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(Theme.cloudPrimary)
                            .accessibilityLabel("Note text")
                    } else {
                        PageScroll(.vertical) {
                            MarkdownBlocksView(text: state.note.text.isEmpty ? "_Empty note. Press ⌘E to write._" : state.note.text, size: 12.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityLabel("Note")
                        .accessibilityValue(state.note.text)
                    }
                }
                .padding(10)
            }
            if case .edge(.left, _) = state.note.placement { edgeStrip(tint) }
        }
        .background(Theme.storm.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(tint.opacity(0.45)))
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sticky note, \(state.note.tint.title): \(state.note.title)")
    }

    private func header(_ tint: Color) -> some View {
        HStack(spacing: 2) {
            if TopBarStyle.isSnapshot {
                Circle().fill(tint).frame(width: 10, height: 10) // ImageRenderer can't draw menus
            } else {
                colourMenu(tint)
            }
            Spacer(minLength: 4)
            if state.saveFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ember)
                    .help("This note couldn't be saved. Check that the disk has room.")
                    .accessibilityLabel("Not saved. Check that the disk has room.")
            }
            GlyphButton(symbol: state.editing ? "eye" : "pencil", size: 10, tint: Theme.cloudSecondary,
                        label: state.editing ? "Preview (⌘E)" : "Edit (⌘E)") { state.editing.toggle() }
                .keyboardShortcut("e", modifiers: .command)
            GlyphButton(symbol: "brain.head.profile", size: 10, tint: Theme.cloudSecondary, label: "Save to brain", action: actions.saveToBrain)
            GlyphButton(symbol: state.note.isOnEdge ? "rectangle.portrait.on.rectangle.portrait" : "sidebar.right", size: 10,
                        tint: Theme.cloudSecondary, label: state.note.isOnEdge ? "Float (⇧⌘E)" : "Tuck into screen edge (⇧⌘E)",
                        action: actions.toggleEdge)
                .keyboardShortcut("e", modifiers: [.command, .shift])
            GlyphButton(symbol: "plus", size: 10, tint: Theme.cloudSecondary, label: "New sticky (⌘N)", action: actions.new)
                .keyboardShortcut("n", modifiers: .command)
            GlyphButton(symbol: "trash", size: 10, tint: Theme.cloudQuiet, label: "Delete sticky", action: actions.delete)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(tint.opacity(0.14))
    }

    /// Colours, also on ⌘1…⌘6.
    private func colourMenu(_ tint: Color) -> some View {
        Menu {
            ForEach(Array(StickyNote.Tint.allCases.enumerated()), id: \.element) { index, color in
                Button(color.title) { state.note.tint = color; actions.changed() }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        } label: {
            Circle().fill(tint).frame(width: 10, height: 10)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Colour, \(state.note.tint.title)")
    }

    private func edgeStrip(_ tint: Color) -> some View {
        Rectangle().fill(tint.opacity(0.85)).frame(width: EdgeShelf.tabWidth)
            .overlay(Image(systemName: "note.text").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.storm))
            .accessibilityLabel("Sticky tab, \(state.note.title). Hover to open.")
    }
}
