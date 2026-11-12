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

    func makeNSView(context: Context) -> OwnedWindowControlProbeView {
        OwnedWindowControlProbeView(registry: registry, id: id, enabled: enabled)
    }

    func updateNSView(_ view: OwnedWindowControlProbeView, context: Context) {
        view.update(registry: registry, id: id, enabled: enabled)
    }

    static func dismantleNSView(_ view: OwnedWindowControlProbeView, coordinator: ()) { view.detach() }
}

@MainActor
final class OwnedWindowControlProbeView: NSView {
    private weak var registry: OwnedWindowControlRegistry?
    private var id: String
    private(set) var controlEnabled: Bool

    init(registry: OwnedWindowControlRegistry, id: String, enabled: Bool) {
        self.registry = registry
        self.id = id
        controlEnabled = enabled
        super.init(frame: .zero)
        setAccessibilityElement(false)
        registry.register(self, id: id)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    func update(registry: OwnedWindowControlRegistry, id: String, enabled: Bool) {
        self.registry?.unregister(self)
        self.registry = registry
        self.id = id
        controlEnabled = enabled
        registry.register(self, id: id)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { registry?.unregister(self) }
        else { registry?.register(self, id: id) }
    }

    func detach() { registry?.unregister(self); registry = nil }
}
