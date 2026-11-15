import AppKit
import Observation
import os
import ZeusCore

/// The rows the model reads and writes. `SettingsStore` is the real one; tests pass a fake that counts.
@MainActor
protocol DrawnNotchStore: AnyObject {
    func string(_ id: String) -> String
    func write(_ id: String, _ value: String)
}

/// A drawn notch row is written by the person at this Mac (the card or calibration), so it carries that origin.
extension SettingsStore: DrawnNotchStore {
    func write(_ id: String, _ value: String) { set(id, value, origin: .person) }
}

/// The drawn notch on displays without a hardware notch: the saved shape, the calibration draft, and the
/// answer to "what does the closed notch look like on this display". Observed, so a change moves the notch
/// without rebuilding a window. The pure rules live in ZeusCore; this carries out their two effects and sends
/// the losses that take the shape or its card away.
///
/// Snapshots and tests never call `start()`, and snapshots pin the footprint so they never read a store.
@MainActor
@Observable
final class DrawnNotchModel: DrawnNotchControlling {
    static let shared = DrawnNotchModel(store: SettingsStore.shared)

    /// The stored rows. The sizes are whole points, written as plain numbers.
    enum Row {
        static let style = "notch.shapeWithoutNotch"
        static let width = "notch.drawnWidth"
        static let height = "notch.drawnHeight"
        static let offset = "notch.drawnOffset"
    }

    private(set) var state: DrawnNotchCalibration.State = .idle
    private(set) var availability: DrawnNotchAvailability = .noDisplay

    private let store: any DrawnNotchStore
    private let appCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zeus", category: "drawn-notch")

    init(store: any DrawnNotchStore,
         appCenter: NotificationCenter = .default,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
         announce: @escaping @MainActor (String) -> Void = DrawnNotchModel.postAnnouncement) {
        self.store = store
        self.appCenter = appCenter
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.announce = announce
    }

    // MARK: What is stored

    /// Anything but the exact word "Notch" is the pill.
    var style: NotchlessStyle { NotchlessStyle(label: store.string(Row.style)) }

    /// The saved shape: each row read as a number, a missing or hostile one taking its default, then snapped and
    /// clamped.
    var saved: DrawnNotchShape {
        func number(_ id: String) -> Double { Double(store.string(id)) ?? .nan }
        return DrawnNotchLimits.sanitized(DrawnNotchShape(width: number(Row.width), height: number(Row.height),
                                                          offset: number(Row.offset)))
    }

    /// The draft while calibrating, else the saved shape.
    var shown: DrawnNotchShape { DrawnNotchCalibration.shown(state, saved: saved) }

    /// Calibration is running and the shape it adjusts is the one on screen. A pill chosen behind its back
    /// leaves nothing to calibrate, so the pointer opens the notch again.
    var isCalibrating: Bool { DrawnNotchCalibration.showsGuide(state) && style == .drawn }

    /// The closed shape on one display: the hardware notch where there is one, else the pill or the shown shape
    /// fitted to that display.
    func footprint(for facts: NotchDisplayFacts) -> NotchFootprint {
        // A hardware notch answers before any row is read: the view asks many times a frame.
        if let size = NotchFootprintRules.hardwareSize(facts) { return .hardware(size) }
        return NotchFootprintRules.resolve(facts, style: style, shape: shown)
    }

    func setStyle(_ style: NotchlessStyle) {
        store.write(Row.style, style == .drawn ? "Notch" : "Pill")
        if style == .pill { send(.surfaceGone(.pillChosen)) }
    }

    // MARK: Calibration

    func send(_ event: DrawnNotchCalibration.Event) {
        if case .surfaceGone(let loss) = event, DrawnNotchCalibration.showsGuide(state) {
            Self.log.info("calibration ended without saving: \(loss.rawValue, privacy: .public)")
        }
        let (next, effects) = DrawnNotchCalibration.reduce(state, event)
        if next != state { state = next }
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: DrawnNotchCalibration.Effect) {
        switch effect {
        case .persist(let shape):
            store.write(Row.width, String(Int(shape.width)))
            store.write(Row.height, String(Int(shape.height)))
            store.write(Row.offset, String(Int(shape.offset)))
        case .announce(let text):
            announce(text)
        }
    }

    // MARK: Displays and the system

    /// Told by the notch controller after every rebuild. With no display left that shows the notch without a
    /// notch there is nothing to calibrate.
    func displaysChanged(targetsWithoutNotch: Int, connectedWithoutNotch: Int) {
        availability = DrawnNotchAvailability.resolve(targetsWithoutNotch: targetsWithoutNotch,
                                                      connectedWithoutNotch: connectedWithoutNotch)
        if targetsWithoutNotch <= 0 { send(.surfaceGone(.noDisplay)) }
    }

    /// Registers the four notices that take the shape away. Tests and snapshots do not call it.
    func start() {
        guard observers.isEmpty else { return }
        watch(distributedCenter, Notification.Name("com.apple.screenIsLocked"), .locked)
        watch(workspaceCenter, NSWorkspace.willSleepNotification, .sleeping)
        watch(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned)
        watch(appCenter, NSApplication.didHideNotification, .appHidden)
    }

    func stop() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers = []
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ loss: DrawnNotchCalibration.SurfaceLoss) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.surfaceGone(loss)) }
        }
        observers.append((center, token))
    }

    /// A polite VoiceOver announcement, as the notch makes for an approval.
    static func postAnnouncement(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }
}
