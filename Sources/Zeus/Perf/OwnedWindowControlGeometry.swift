import AppKit
import SwiftUI

/// Opt-in geometry observation for an owned native fixture. No action, binding or controller enters
/// this registry. With the default nil environment the production control gains only its AX ID.
@MainActor
final class OwnedWindowControlRegistry {
    private struct Entry {
        weak var probe: OwnedWindowControlProbeView?
        let id: String
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    fileprivate func register(_ probe: OwnedWindowControlProbeView, id: String) {
        entries[ObjectIdentifier(probe)] = Entry(probe: probe, id: id)
    }

    fileprivate func unregister(_ probe: OwnedWindowControlProbeView) {
        entries.removeValue(forKey: ObjectIdentifier(probe))
    }

    func probes(for id: String, in window: NSWindow) -> [OwnedWindowControlProbeView] {
        entries = entries.filter { $0.value.probe != nil }
        return entries.values.compactMap { entry in
            guard entry.id == id, let probe = entry.probe, probe.window === window else { return nil }
            return probe
        }
    }
}

private struct OwnedWindowControlRegistryKey: EnvironmentKey {
    static let defaultValue: OwnedWindowControlRegistry? = nil
}

extension EnvironmentValues {
    var ownedWindowControlRegistry: OwnedWindowControlRegistry? {
        get { self[OwnedWindowControlRegistryKey.self] }
        set { self[OwnedWindowControlRegistryKey.self] = newValue }
    }
}

extension View {
    func ownedJourneyControl(_ id: String) -> some View {
        modifier(OwnedWindowControlGeometry(id: id))
    }
}

extension View {
    /// Records the exact string this view's body rendered, for the owned host to read back. Outside the host
    /// there is no registry in the environment, so nothing is added.
    func ownedJourneyText(_ id: String, _ text: String) -> some View {
        modifier(OwnedWindowTextGeometry(id: id, text: text))
    }
}

private struct OwnedWindowTextGeometry: ViewModifier {
    let id: String
    let text: String
    @Environment(\.ownedWindowControlRegistry) private var registry

    func body(content: Content) -> some View {
        content.background {
            if let registry { OwnedWindowControlProbe(registry: registry, id: id, enabled: true, text: text) }
        }
    }
}

private struct OwnedWindowControlGeometry: ViewModifier {
    let id: String
    @Environment(\.ownedWindowControlRegistry) private var registry
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content.accessibilityIdentifier(id)
            .background {
                if let registry { OwnedWindowControlProbe(registry: registry, id: id, enabled: enabled) }
            }
    }
}

private struct OwnedWindowControlProbe: NSViewRepresentable {
    let registry: OwnedWindowControlRegistry
    let id: String
    let enabled: Bool
    var text: String?

    func makeNSView(context: Context) -> OwnedWindowControlProbeView {
        OwnedWindowControlProbeView(registry: registry, id: id, enabled: enabled, text: text)
    }

    func updateNSView(_ view: OwnedWindowControlProbeView, context: Context) {
        view.update(registry: registry, id: id, enabled: enabled, text: text)
    }

    static func dismantleNSView(_ view: OwnedWindowControlProbeView, coordinator: ()) { view.detach() }
}

@MainActor
final class OwnedWindowControlProbeView: NSView {
    private weak var registry: OwnedWindowControlRegistry?
    private var id: String
    private(set) var controlEnabled: Bool
    /// The string a text probe's view rendered; nil for a control probe.
    private(set) var renderedText: String?

    init(registry: OwnedWindowControlRegistry, id: String, enabled: Bool, text: String? = nil) {
        self.registry = registry
        self.id = id
        controlEnabled = enabled
        renderedText = text
        super.init(frame: .zero)
        setAccessibilityElement(false)
        registry.register(self, id: id)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    func update(registry: OwnedWindowControlRegistry, id: String, enabled: Bool, text: String? = nil) {
        self.registry?.unregister(self)
        self.registry = registry
        self.id = id
        controlEnabled = enabled
        renderedText = text
        registry.register(self, id: id)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { registry?.unregister(self) }
        else { registry?.register(self, id: id) }
    }

    func detach() { registry?.unregister(self); registry = nil }
}
