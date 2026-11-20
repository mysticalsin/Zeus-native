import Foundation

public enum AccessoryConfirmation: Equatable, Sendable {
    case idle
    case enableSpeakers
}

public enum AccessoryControlRole: String, Equatable, Sendable {
    case toggle
    case choice
    case button
    case status
}

public struct AccessoryControl: Equatable, Sendable, Identifiable {
    public var id: String
    public var role: AccessoryControlRole
    public var accessibilityLabel: String
    public var accessibilityHint: String
    public var keyboardReachable: Bool

    public init(id: String, role: AccessoryControlRole, accessibilityLabel: String, accessibilityHint: String, keyboardReachable: Bool) {
        self.id = id
        self.role = role
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.keyboardReachable = keyboardReachable
    }
}

public enum AccessorySectionSurface {
    public static func controls(_ model: AccessorySectionModel) -> [AccessoryControl] {
        var rows = [
            control("earbuds", .toggle, AccessoryCopy.earbuds),
            control("style", .choice, AccessoryCopy.style),
            control("speakers", .toggle, AccessoryCopy.speakers),
        ]
        if model.confirmation == .enableSpeakers {
            rows.append(AccessoryControl(id: "speakers.confirm", role: .button, accessibilityLabel: AccessoryCopy.confirm, accessibilityHint: AccessoryCopy.enableConfirmation, keyboardReachable: true))
            rows.append(AccessoryControl(id: "speakers.cancel", role: .button, accessibilityLabel: AccessoryCopy.cancel, accessibilityHint: AccessoryCopy.enableConfirmation, keyboardReachable: true))
        }
        if model.preferences.speakerNames, model.speakers.phase == .off, model.confirmation == .idle {
            rows.append(AccessoryControl(id: "speakers.look", role: .button, accessibilityLabel: "Look for speakers", accessibilityHint: AccessoryCopy.enableConfirmation, keyboardReachable: true))
        }
        if model.speakers.phase.isUnavailable {
            rows.append(AccessoryControl(id: "speakers.settings", role: .button, accessibilityLabel: "Local network settings", accessibilityHint: model.speakers.phase.status, keyboardReachable: true))
        }
        if model.speakers.phase.isError {
            rows.append(AccessoryControl(id: "speakers.retry", role: .button, accessibilityLabel: "Try again", accessibilityHint: model.speakers.phase.status, keyboardReachable: true))
        }
        if case .names(let speakers) = model.speakers.phase {
            for speaker in speakers {
                rows.append(AccessoryControl(id: "speaker.\(speaker.id)", role: .status, accessibilityLabel: speaker.name, accessibilityHint: "Nearby speaker.", keyboardReachable: true))
            }
        }
        let preview = model.preview
        rows.append(AccessoryControl(
            id: "preview",
            role: .status,
            accessibilityLabel: preview.visible ? preview.accessibilityLabel : AccessoryCopy.previewOff,
            accessibilityHint: AccessoryCopy.previewOff,
            keyboardReachable: true
        ))
        return rows
    }

    private static func control(_ id: String, _ role: AccessoryControlRole, _ copy: AccessoryControlCopy) -> AccessoryControl {
        AccessoryControl(id: id, role: role, accessibilityLabel: copy.accessibilityLabel, accessibilityHint: copy.accessibilityHint, keyboardReachable: true)
    }
}

public enum AccessorySectionEvent: Equatable, Sendable {
    case setEarbudsOverlay(Bool)
    case setOverlayStyle(AccessoryOverlayStyle)
    case askToEnableSpeakers
    case cancelSpeakerEnable
    case confirmSpeakerEnable
    case disableSpeakers
    case permissionAllowed
    case permissionDenied
    case permissionRestricted
    case speakersFound([NearbySpeaker])
    case searchFailed
    case earbudsConnected(AccessoryConnectInput)
    case earbudsDisconnected
    case overlayAppearFinished
    case overlayDismiss
    case overlayDismissFinished
    case reduceMotion(Bool)
    case restore(overlay: String?, style: String?, speakers: String?)
    case importPreferences(AccessoryPreferences)
}

public enum AccessorySectionEffect: Equatable, Sendable {
    case requestPermission
    case startSearch
    case stopSearch
    case persist(AccessoryPreferences)
    case overlay([AccessoryOverlayEffect])
}

public struct AccessorySectionModel: Equatable, Sendable {
    public private(set) var preferences: AccessoryPreferences
    public private(set) var overlay: AccessoryConnectOverlayMachine
    public private(set) var speakers: NearbySpeakerMachine
    public private(set) var confirmation: AccessoryConfirmation
    public private(set) var reduceMotion: Bool

    public init() {
        preferences = .failClosed
        overlay = AccessoryConnectOverlayMachine()
        speakers = NearbySpeakerMachine()
        confirmation = .idle
        reduceMotion = false
    }

    public var preview: AccessoryPreviewTile {
        AccessoryPreviewTile.make(preferences: preferences, live: overlay.latched, reduceMotion: reduceMotion)
    }

    public var speakerStatus: String {
        if preferences.speakerNames, speakers.phase == .off {
            return "On, and not searching until you look."
        }
        return speakers.phase.status
    }

    public mutating func handle(_ event: AccessorySectionEvent) -> [AccessorySectionEffect] {
        switch event {
        case .setEarbudsOverlay(let value):
            guard value != preferences.earbudsOverlay else { return [] }
            preferences.earbudsOverlay = value
            return [.persist(preferences)] + pushGate()
        case .setOverlayStyle(let style):
            guard style != preferences.overlayStyle else { return [] }
            preferences.overlayStyle = style
            return [.persist(preferences)] + pushGate()
        case .askToEnableSpeakers:
            switch speakers.phase {
            case .off, .unavailable, .error:
                confirmation = .enableSpeakers
            default:
                break
            }
            return []
        case .cancelSpeakerEnable:
            confirmation = .idle
            return []
        case .confirmSpeakerEnable:
            guard confirmation == .enableSpeakers else { return [] }
            confirmation = .idle
            let asked = lift(speakers.handle(.userEnabled))
            guard !preferences.speakerNames else { return asked }
            preferences.speakerNames = true
            return [.persist(preferences)] + asked
        case .disableSpeakers:
            confirmation = .idle
            let stopped = lift(speakers.handle(.userDisabled))
            guard preferences.speakerNames else { return stopped }
            preferences.speakerNames = false
            return stopped + [.persist(preferences)] + pushGate()
        case .permissionAllowed:
            return lift(speakers.handle(.permissionAllowed))
        case .permissionDenied:
            return lift(speakers.handle(.permissionDenied))
        case .permissionRestricted:
            return lift(speakers.handle(.permissionRestricted))
        case .speakersFound(let names):
            return lift(speakers.handle(.found(names)))
        case .searchFailed:
            return lift(speakers.handle(.searchFailed))
        case .earbudsConnected(let input):
            return lift(overlay.handle(.connected(input)))
        case .earbudsDisconnected:
            return lift(overlay.handle(.disconnected))
        case .overlayAppearFinished:
            return lift(overlay.handle(.appearFinished))
        case .overlayDismiss:
            return lift(overlay.handle(.dismiss))
        case .overlayDismissFinished:
            return lift(overlay.handle(.dismissFinished))
        case .reduceMotion(let value):
            reduceMotion = value
            return pushGate()
        case .restore(let overlayValue, let style, let speakersValue):
            preferences = AccessoryPreferences.restored(overlay: overlayValue, style: style, speakers: speakersValue)
            return pushGate()
        case .importPreferences(let imported):
            let next = preferences.applyingImport(imported)
            guard next != preferences else { return [] }
            var effects: [AccessorySectionEffect] = []
            if preferences.speakerNames, !next.speakerNames {
                effects += lift(speakers.handle(.userDisabled))
            }
            preferences = next
            confirmation = .idle
            effects += pushGate()
            effects.append(.persist(preferences))
            return effects
        }
    }

    private mutating func pushGate() -> [AccessorySectionEffect] {
        lift(overlay.handle(.gate(AccessoryOverlayGate(
            connectEnabled: preferences.earbudsOverlay,
            style: preferences.overlayStyle,
            reduceMotion: reduceMotion
        ))))
    }

    private func lift(_ effects: [AccessoryOverlayEffect]) -> [AccessorySectionEffect] {
        effects.isEmpty ? [] : [.overlay(effects)]
    }

    private func lift(_ effects: [NearbySpeakerEffect]) -> [AccessorySectionEffect] {
        effects.map { effect in
            switch effect {
            case .requestPermission: .requestPermission
            case .startSearch: .startSearch
            case .stopSearch: .stopSearch
            }
        }
    }
}
