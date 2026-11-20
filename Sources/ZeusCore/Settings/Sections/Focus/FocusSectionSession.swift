import Foundation

/// One Focus section. The switches, the name gate, the overlay, the filter, the lock screen, and the home widget stay in step.
public struct FocusSectionSession: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case setTransition(Bool)
        case setOverlaysAllowed(Bool)
        case setLockScreen(Bool)
        case setReadName(Bool)
        case setStoreFile(Bool)
        case setLocalNetwork(Bool)
        case setSharedLink(Bool)
        case setHomeWidget(String?)
        case permission(FocusPermission, FocusPermissionAnswer)
        case publicSample(isFocused: Bool?, attachedName: String?)
        case storeSample(FocusStoreParser.Read)
        case networkNames([String])
        case link(FocusLink)
        case timer(FocusTimerSnapshot)
        case tick(Double)
        case dismissOverlay
        case reduceMotion(Bool)
        case imported([String: Bool], homeWidget: String?)
    }

    public enum Effect: Equatable, Sendable {
        case request(FocusPermission)
        case readPublic
        case readStore
        case browseLocalNetwork
        case cancelReads
        case showOverlay(label: String, animation: Double)
        case hideOverlay
    }

    public private(set) var settings = FocusSectionSettings.closed
    public private(set) var name = FocusNameMachine()
    public private(set) var transition = FocusTransitionMachine()
    public private(set) var focusPermission: FocusPermissionAnswer = .notDetermined
    public private(set) var fullDisk: FocusPermissionAnswer = .notDetermined
    public private(set) var localNetworkPermission: FocusPermissionAnswer = .notDetermined
    public private(set) var activity: FocusActivity = .unknown
    public private(set) var timer = FocusTimerSnapshot.ready
    public private(set) var reduceMotion = false
    public private(set) var now: Double = 0
    private var defaults: FocusDefaultsBox?

    public init() {}

    /// Restores the switches last saved under `opt.<id>`. A missing key stays off.
    public init(defaults: UserDefaults) {
        self.defaults = FocusDefaultsBox(defaults)
        let loaded = FocusSettingsPersistence.load(defaults)
        if loaded.transitionOverlay { _ = handle(.setTransition(true)) }
        if loaded.overlaysAllowed { _ = handle(.setOverlaysAllowed(true)) }
        if loaded.lockScreen { _ = handle(.setLockScreen(true)) }
        if loaded.readName { _ = handle(.setReadName(true)) }
        if loaded.storeFile { _ = handle(.setStoreFile(true)) }
        if loaded.localNetwork { _ = handle(.setLocalNetwork(true)) }
        if loaded.sharedLink { _ = handle(.setSharedLink(true)) }
        if loaded.homeWidget != settings.homeWidget { _ = handle(.setHomeWidget(loaded.homeWidget)) }
    }

    public static func == (lhs: FocusSectionSession, rhs: FocusSectionSession) -> Bool {
        lhs.settings == rhs.settings
            && lhs.name == rhs.name
            && lhs.transition == rhs.transition
            && lhs.focusPermission == rhs.focusPermission
            && lhs.fullDisk == rhs.fullDisk
            && lhs.localNetworkPermission == rhs.localNetworkPermission
            && lhs.activity == rhs.activity
            && lhs.timer == rhs.timer
            && lhs.reduceMotion == rhs.reduceMotion
            && lhs.now == rhs.now
    }

    private var needsStatus: Bool {
        settings.transitionOverlay || settings.overlaysAllowed || settings.lockScreen || settings.readName
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .setTransition(let on):
            let wasNeeded = needsStatus
            settings.transitionOverlay = on
            remember(FocusSettingKey.transitionOverlay, on)
            var effects: [Effect] = []
            if on {
                effects += map(transition.handle(.setEnabled(true)))
                if focusPermission == .denied {
                    effects += map(transition.handle(.permissionDenied))
                } else if activity != .unknown {
                    effects += map(transition.handle(.activity(activity)))
                }
            } else {
                effects += map(transition.handle(.setEnabled(false)))
            }
            return dedupe(effects + accessEffects(wasNeeded: wasNeeded))
        case .setOverlaysAllowed(let on):
            let wasNeeded = needsStatus
            settings.overlaysAllowed = on
            remember(FocusSettingKey.overlaysAllowed, on)
            return accessEffects(wasNeeded: wasNeeded)
        case .setLockScreen(let on):
            let wasNeeded = needsStatus
            settings.lockScreen = on
            remember(FocusSettingKey.lockScreen, on)
            return accessEffects(wasNeeded: wasNeeded)
        case .setReadName(let on):
            let wasNeeded = needsStatus
            settings.readName = on
            remember(FocusSettingKey.readName, on)
            return dedupe(map(name.handle(.setRead(on))) + accessEffects(wasNeeded: wasNeeded))
        case .setStoreFile(let on):
            settings.storeFile = on
            remember(FocusSettingKey.storeFile, on)
            return map(name.handle(.setStoreFile(on)))
        case .setLocalNetwork(let on):
            settings.localNetwork = on
            remember(FocusSettingKey.localNetwork, on)
            return map(name.handle(.setLocalNetwork(on)))
        case .setSharedLink(let on):
            settings.sharedLink = on
            remember(FocusSettingKey.sharedLink, on)
            return map(name.handle(.setSharedLink(on)))
        case .setHomeWidget(let stored):
            settings.homeWidget = stored
            if let defaults {
                FocusSettingsPersistence.write(stored ?? "Focus", id: FocusSettingKey.homeWidget, to: defaults.defaults)
            }
            return []
        case .permission(let kind, let answer):
            switch kind {
            case .focusStatus: focusPermission = answer
            case .fullDisk: fullDisk = answer
            case .localNetwork: localNetworkPermission = answer
            }
            var effects = map(name.handle(.permission(kind, answer)))
            guard kind == .focusStatus else { return effects }
            switch answer {
            case .denied:
                activity = .unknown
                if settings.transitionOverlay {
                    effects += map(transition.handle(.permissionDenied))
                }
            case .allowed:
                if settings.transitionOverlay {
                    effects += map(transition.handle(.permissionAllowed))
                }
                if needsStatus && !effects.contains(.readPublic) {
                    effects.append(.readPublic)
                }
            case .notDetermined:
                break
            }
            return dedupe(effects)
        case .publicSample(let focused, let attached):
            guard needsStatus, focusPermission == .allowed else { return [] }
            var effects = map(name.handle(.publicSample(isFocused: focused, attachedName: attached)))
            let next = settings.readName ? name.activity : Self.plain(focused)
            effects += follow(next)
            return dedupe(effects)
        case .storeSample(let sample):
            let effects = map(name.handle(.storeSample(sample)))
            guard settings.readName else { return effects }
            return dedupe(effects + follow(name.activity))
        case .networkNames(let names):
            let effects = map(name.handle(.networkNames(names)))
            guard settings.readName else { return effects }
            return dedupe(effects + follow(name.activity))
        case .link(let link):
            let effects = map(name.handle(.link(link)))
            guard settings.readName else { return effects }
            return dedupe(effects + follow(name.activity))
        case .timer(let snapshot):
            timer = snapshot
            return []
        case .tick(let time):
            now = time
            return map(transition.handle(.tick(time)))
        case .dismissOverlay:
            return map(transition.handle(.dismiss))
        case .reduceMotion(let on):
            reduceMotion = on
            return map(transition.handle(.reduceMotion(on)))
        case .imported(let bools, let homeWidget):
            settings = FocusSectionSettings.imported(bools: bools, homeWidget: homeWidget)
            name = FocusNameMachine()
            transition = FocusTransitionMachine()
            activity = .unknown
            _ = name.handle(.permission(.focusStatus, focusPermission))
            _ = name.handle(.permission(.fullDisk, fullDisk))
            _ = name.handle(.permission(.localNetwork, localNetworkPermission))
            _ = name.handle(.setStoreFile(settings.storeFile))
            _ = name.handle(.setLocalNetwork(settings.localNetwork))
            _ = name.handle(.setSharedLink(settings.sharedLink))
            remember(FocusSettingKey.transitionOverlay, settings.transitionOverlay)
            remember(FocusSettingKey.overlaysAllowed, settings.overlaysAllowed)
            remember(FocusSettingKey.lockScreen, settings.lockScreen)
            remember(FocusSettingKey.readName, settings.readName)
            remember(FocusSettingKey.storeFile, settings.storeFile)
            remember(FocusSettingKey.localNetwork, settings.localNetwork)
            remember(FocusSettingKey.sharedLink, settings.sharedLink)
            if let defaults {
                FocusSettingsPersistence.write(settings.homeWidget ?? "Focus", id: FocusSettingKey.homeWidget, to: defaults.defaults)
            }
            return [.hideOverlay, .cancelReads]
        }
    }

    public func overlayDecision(_ kind: FocusOverlayKind) -> FocusOverlayDecision {
        FocusOverlayFilter.decide(
            kind: kind, focus: activity, filterEnabled: settings.overlaysAllowed, transitionArmed: settings.transitionOverlay
        )
    }

    public func lockScreen() -> FocusLockScreenState {
        FocusLockScreenPolicy.present(enabled: settings.lockScreen, activity: activity, permission: focusPermission)
    }

    public func home() -> FocusHomeWidgetState {
        FocusHomeWidgetPolicy.present(stored: settings.homeWidget, timer: timer, name: name, reduceMotion: reduceMotion)
    }

    public func content() -> FocusSectionContent {
        let status = sectionStatus()
        let line = previewLine(status)
        let showing = transition.state.isShowing
        let preview = FocusPreview(
            title: "Preview", line: line, accessibilityLabel: "Preview, \(line)",
            animates: showing && !reduceMotion,
            animationDuration: FocusTransitionMachine.animationDuration(reduceMotion: reduceMotion)
        )
        return FocusSectionContent(
            title: "Focus", placement: FocusSectionMetrics.placement, placementOrder: FocusSectionMetrics.placementOrder,
            rowHeight: FocusSectionMetrics.rowHeight, panelPadding: FocusSectionMetrics.panelPadding,
            cardGap: FocusSectionMetrics.cardGap, controls: controls(), status: status, preview: preview,
            filterSummary: filterSummary()
        )
    }

    private func remember(_ id: String, _ on: Bool) {
        guard let defaults else { return }
        FocusSettingsPersistence.write(on ? "true" : "false", id: id, to: defaults.defaults)
    }

    private func accessEffects(wasNeeded: Bool) -> [Effect] {
        if needsStatus && !wasNeeded {
            switch focusPermission {
            case .notDetermined: return [.request(.focusStatus)]
            case .allowed: return [.readPublic]
            case .denied: return []
            }
        }
        if !needsStatus && wasNeeded { return [.cancelReads] }
        return []
    }

    private mutating func follow(_ next: FocusActivity) -> [Effect] {
        let previous = activity
        activity = next
        guard settings.transitionOverlay, previous != next else { return [] }
        return map(transition.handle(.activity(next)))
    }

    private func sectionStatus() -> FocusSectionStatus {
        if needsStatus {
            switch focusPermission {
            case .notDetermined:
                return .loading
            case .denied:
                if settings.readName && settings.storeFile && fullDisk == .allowed {
                    if name.displayName != nil || name.activity != .unknown { return .ready }
                    if case .unavailable = name.phase { return .unavailable("Unavailable") }
                    return .loading
                }
                return .unavailable("Unavailable")
            case .allowed:
                return activity == .unknown ? .loading : .ready
            }
        }
        return home().occupancy == .empty ? .empty : .ready
    }

    private func previewLine(_ status: FocusSectionStatus) -> String {
        if let label = transition.state.overlayLabel { return label }
        switch status {
        case .loading:
            return "Checking"
        case .unavailable:
            return "Unavailable"
        case .empty:
            return "Nothing is on"
        case .ready:
            if case .showing(let label) = lockScreen() { return label }
            if home().occupancy == .running { return home().subtitle }
            if case .on(let label) = activity { return label ?? "Focus on" }
            if case .off = activity, needsStatus { return "No Focus is on" }
            return "Nothing is on"
        }
    }

    private func filterSummary() -> String {
        switch activity {
        case .unknown:
            return "Unavailable"
        case .off:
            return "Not in a Focus"
        case .on:
            let allowed = FocusOverlayKind.allCases.filter { overlayDecision($0) == .allowed }.count
            return allowed == 0 ? "Blocked" : "\(allowed) allowed"
        }
    }

    private func controls() -> [FocusControlSpec] {
        let widget = HomeSlots([nil, settings.homeWidget, nil, nil])[2].title
        return [
            control(FocusSettingKey.transitionOverlay, "Overlay when a Focus turns on or off",
                    "Shows a short overlay when a Focus turns on or off. Off until you turn it on.", settings.transitionOverlay),
            control(FocusSettingKey.overlaysAllowed, "Overlays allowed during a Focus",
                    "While a Focus is on, only the overlays in the filter may appear. Off blocks every overlay.", settings.overlaysAllowed),
            control(FocusSettingKey.lockScreen, "Show the Focus on the lock screen",
                    "Shows that a Focus is on at the lock screen. The name stays hidden. Off until you turn it on.", settings.lockScreen),
            control(FocusSettingKey.readName, "Read the Focus name",
                    "Uses the public filter. Off reads nothing.", settings.readName),
            control(FocusSettingKey.storeFile, "Read the Focus store",
                    "A second path, only if you turn it on. It needs Full Disk Access. Off reads nothing.", settings.storeFile),
            control(FocusSettingKey.localNetwork, "Find a name on the local network",
                    "Off does not browse.", settings.localNetwork),
            control(FocusSettingKey.sharedLink, "Accept a name from a link",
                    "A plain link on shared Wi-Fi is refused. Off until you turn it on.", settings.sharedLink),
            FocusControlSpec(
                id: FocusSettingKey.homeWidget, title: "Focus widget on the home view",
                helper: "Home slot 2. Today it shows the Focus timer. A name appears only when reading is allowed.",
                accessibilityLabel: "Focus widget on the home view, \(widget)", accessibilityValue: widget,
                keyboardReachable: true, isOn: false
            ),
        ]
    }

    private func control(_ id: String, _ title: String, _ helper: String, _ isOn: Bool) -> FocusControlSpec {
        let value = isOn ? "On" : "Off"
        return FocusControlSpec(
            id: id, title: title, helper: helper, accessibilityLabel: "\(title), \(value)",
            accessibilityValue: value, keyboardReachable: true, isOn: isOn
        )
    }

    private static func plain(_ focused: Bool?) -> FocusActivity {
        guard let focused else { return .unknown }
        return focused ? .on(name: nil) : .off
    }

    private func map(_ effects: [FocusNameMachine.Effect]) -> [Effect] {
        effects.map { effect in
            switch effect {
            case .request(let permission): return .request(permission)
            case .readPublic: return .readPublic
            case .readStore: return .readStore
            case .browseLocalNetwork: return .browseLocalNetwork
            case .cancel: return .cancelReads
            }
        }
    }

    private func map(_ effects: [FocusTransitionMachine.Effect]) -> [Effect] {
        effects.map { effect in
            switch effect {
            case .show(let label, let animation): return .showOverlay(label: label, animation: animation)
            case .hide: return .hideOverlay
            }
        }
    }

    private func dedupe(_ effects: [Effect]) -> [Effect] {
        var kept: [Effect] = []
        for effect in effects where !kept.contains(effect) {
            kept.append(effect)
        }
        return kept
    }
}

private final class FocusDefaultsBox: @unchecked Sendable {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults) { self.defaults = defaults }
}

private extension FocusTransitionMachine.State {
    var isShowing: Bool {
        if case .showing = self { return true }
        return false
    }

    var overlayLabel: String? {
        if case .showing(_, let label, _) = self { return label }
        return nil
    }
}
