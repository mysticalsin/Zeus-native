import Foundation

/// How a Focus name is read. The public filter comes first. The store, the local network, and a link run only after their own switches are on.
public struct FocusNameMachine: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case publicFilter
        case storeFile
        case localNetwork
        case sharedLink
    }

    public enum Refusal: Equatable, Sendable {
        case focusStatus
        case fullDisk
        case localNetwork
        case sharedLink
        case malformed
    }

    public enum Phase: Equatable, Sendable {
        case off
        case checking
        case allowed(Source)
        case unavailable(Refusal)
    }

    public enum Event: Equatable, Sendable {
        case setRead(Bool)
        case setStoreFile(Bool)
        case setLocalNetwork(Bool)
        case setSharedLink(Bool)
        case permission(FocusPermission, FocusPermissionAnswer)
        case publicSample(isFocused: Bool?, attachedName: String?)
        case storeSample(FocusStoreParser.Read)
        case networkNames([String])
        case link(FocusLink)
    }

    public enum Effect: Equatable, Sendable {
        case request(FocusPermission)
        case readPublic
        case readStore
        case browseLocalNetwork
        case cancel
    }

    public private(set) var phase: Phase = .off
    public private(set) var read = false
    public private(set) var storeFile = false
    public private(set) var localNetwork = false
    public private(set) var sharedLink = false
    public private(set) var activity: FocusActivity = .unknown
    public private(set) var displayName: String?
    public private(set) var storeStatus: FocusRowStatus = .off
    public private(set) var networkStatus: FocusRowStatus = .off
    public private(set) var linkStatus: FocusRowStatus = .off
    public private(set) var focusStatus: FocusPermissionAnswer = .notDetermined
    public private(set) var fullDisk: FocusPermissionAnswer = .notDetermined
    public private(set) var localNetworkPermission: FocusPermissionAnswer = .notDetermined

    public init() {}

    public static let fullDiskDenied = "Unavailable. Full Disk Access was not allowed."
    public static let localNetworkDenied = "Unavailable. Local network was not allowed."
    public static let linkRefused = "Unavailable. That link was refused."
    public static let storeUnreadable = "Unavailable. The Focus store could not be read."

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .setRead(let on):
            read = on
            guard on else {
                displayName = nil
                activity = .unknown
                phase = .off
                storeStatus = .off
                networkStatus = .off
                linkStatus = .off
                return [.cancel]
            }
            return beganReading()
        case .setStoreFile(let on):
            storeFile = on
            guard on else {
                storeStatus = .off
                return []
            }
            guard read, focusStatus != .notDetermined else { return [] }
            return storeAccess()
        case .setLocalNetwork(let on):
            localNetwork = on
            guard on else {
                networkStatus = .off
                return []
            }
            guard read else { return [] }
            return networkAccess()
        case .setSharedLink(let on):
            sharedLink = on
            if !on { linkStatus = .off }
            return []
        case .permission(let kind, let answer):
            switch kind {
            case .focusStatus: focusStatus = answer
            case .fullDisk: fullDisk = answer
            case .localNetwork: localNetworkPermission = answer
            }
            guard read else { return [] }
            switch kind {
            case .focusStatus:
                switch answer {
                case .allowed:
                    phase = phase == .off ? .checking : phase
                    if case .unavailable = phase { phase = .checking }
                    return [.readPublic]
                case .denied:
                    return focusDenied()
                case .notDetermined:
                    phase = .checking
                    return [.request(.focusStatus)]
                }
            case .fullDisk:
                guard storeFile else { return [] }
                return storeAccess()
            case .localNetwork:
                guard localNetwork else { return [] }
                return networkAccess()
            }
        case .publicSample(let focused, let attached):
            guard read, focusStatus == .allowed else { return [] }
            let cleaned = attached.flatMap(FocusNameText.cleanName)
            guard let focused else {
                activity = .unknown
                displayName = nil
                phase = .checking
                return []
            }
            if !focused {
                activity = .off
                displayName = nil
                phase = .allowed(.publicFilter)
                return []
            }
            activity = .on(name: cleaned)
            displayName = cleaned
            phase = .allowed(.publicFilter)
            return cleaned == nil ? storeReadIfNeeded() : []
        case .storeSample(let sample):
            guard read, storeFile, fullDisk == .allowed else { return [] }
            switch sample {
            case .off:
                storeStatus = .allowed
                return []
            case .unreadable:
                storeStatus = .unavailable(Self.storeUnreadable)
                return []
            case .on(let name, _):
                storeStatus = .allowed
                guard !(focusStatus == .allowed && activity == .off) else { return [] }
                guard let cleaned = name.flatMap(FocusNameText.cleanName) else { return [] }
                guard displayName == nil || focusStatus == .denied else { return [] }
                displayName = cleaned
                activity = .on(name: cleaned)
                phase = .allowed(.storeFile)
                return []
            }
        case .networkNames(let names):
            guard read, localNetwork, localNetworkPermission == .allowed else { return [] }
            networkStatus = .allowed
            guard displayName == nil, activity != .off else { return [] }
            guard let cleaned = names.compactMap(FocusNameText.cleanName).first else { return [] }
            displayName = cleaned
            activity = .on(name: cleaned)
            phase = .allowed(.localNetwork)
            return []
        case .link(let link):
            guard read, sharedLink else { return [] }
            switch FocusLinkRule.decide(link) {
            case .refused:
                linkStatus = .unavailable(Self.linkRefused)
                return []
            case .accepted(let label):
                linkStatus = .allowed
                guard !(focusStatus == .allowed && activity == .off) else { return [] }
                guard let label, displayName == nil || focusStatus == .denied else { return [] }
                displayName = label
                activity = .on(name: label)
                phase = .allowed(.sharedLink)
                return []
            }
        }
    }

    private mutating func beganReading() -> [Effect] {
        switch focusStatus {
        case .notDetermined:
            phase = .checking
            return [.request(.focusStatus)]
        case .allowed:
            phase = .checking
            return [.readPublic]
        case .denied:
            return focusDenied()
        }
    }

    private mutating func focusDenied() -> [Effect] {
        displayName = nil
        activity = .unknown
        guard storeFile else {
            phase = .unavailable(.focusStatus)
            return []
        }
        switch fullDisk {
        case .notDetermined:
            phase = .checking
            storeStatus = .checking
            return [.request(.fullDisk)]
        case .allowed:
            phase = .checking
            storeStatus = .allowed
            return [.readStore]
        case .denied:
            storeStatus = .unavailable(Self.fullDiskDenied)
            phase = .unavailable(.fullDisk)
            return []
        }
    }

    private mutating func storeAccess() -> [Effect] {
        switch fullDisk {
        case .notDetermined:
            storeStatus = .checking
            return [.request(.fullDisk)]
        case .allowed:
            storeStatus = .allowed
            return storeReadIfNeeded()
        case .denied:
            storeStatus = .unavailable(Self.fullDiskDenied)
            if focusStatus == .denied { phase = .unavailable(.fullDisk) }
            return []
        }
    }

    private mutating func storeReadIfNeeded() -> [Effect] {
        guard storeFile else { return [] }
        switch fullDisk {
        case .allowed where displayName == nil && (activity.isOn || focusStatus == .denied):
            return [.readStore]
        case .notDetermined where focusStatus != .notDetermined:
            storeStatus = .checking
            return [.request(.fullDisk)]
        case .denied:
            storeStatus = .unavailable(Self.fullDiskDenied)
            return []
        default:
            return []
        }
    }

    private mutating func networkAccess() -> [Effect] {
        switch localNetworkPermission {
        case .allowed:
            networkStatus = .allowed
            return [.browseLocalNetwork]
        case .notDetermined:
            networkStatus = .checking
            return [.request(.localNetwork)]
        case .denied:
            networkStatus = .unavailable(Self.localNetworkDenied)
            return []
        }
    }
}
