import Foundation

/// Language packs installed after the app, never inside it. The bundle carries no language data: each pack is a
/// list of components that macOS (or our own files) provide on request. See docs/LANGUAGE-PACKS.md.
public enum LanguagePackID: String, CaseIterable, Codable, Hashable, Sendable {
    case english = "en", french = "fr", spanish = "es", portuguese = "pt"

    public var title: String {
        switch self {
        case .english: "English"
        case .french: "French"
        case .spanish: "Spanish"
        case .portuguese: "Portuguese"
        }
    }

    /// The locale the pack installs speech assets for.
    public var locale: String {
        switch self {
        case .english: "en-US"
        case .french: "fr-FR"
        case .spanish: "es-ES"
        case .portuguese: "pt-BR"
        }
    }

    /// The four packs the owner asked for, ticked by default in onboarding.
    public static var defaults: Set<LanguagePackID> { Set(allCases) }
}

public enum LanguageComponentKind: Hashable, Sendable {
    /// Apple's on-device SpeechAnalyzer model for one locale (macOS 26 and later).
    case appleSpeechAnalyzerAsset
    /// Spoken replies use the macOS voice for the language: nothing to download.
    case systemVoice
}

public struct LanguageComponent: Hashable, Sendable {
    public let pack: LanguagePackID
    public let kind: LanguageComponentKind
    public let locale: String
    /// Download size when it is known. Apple does not publish asset sizes ahead of time, so these are nil.
    public let approximateBytes: Int64?

    public var needsDownload: Bool { kind != .systemVoice }
}

public enum LanguagePackCatalog {
    public static func components(of pack: LanguagePackID) -> [LanguageComponent] {
        [LanguageComponent(pack: pack, kind: .appleSpeechAnalyzerAsset, locale: pack.locale, approximateBytes: nil),
         LanguageComponent(pack: pack, kind: .systemVoice, locale: pack.locale, approximateBytes: nil)]
    }

    public static var all: [LanguageComponent] { LanguagePackID.allCases.flatMap(components(of:)) }
}

public enum LanguageComponentState: Equatable, Sendable {
    case notNeeded
    case notInstalled
    case queued
    case downloading(progress: Double)
    case installed
    case failed(reason: String)
    case unsupportedOnThisMac
}

public enum LanguagePackStatus: Equatable, Sendable {
    case installed
    case installing(progress: Double)
    case queued
    /// Waiting because Low Power Mode is on; "Install now" starts it.
    case deferredForLowPower
    case failed(reason: String)
    case unsupportedOnThisMac
    case notInstalled
}

/// What macOS reports for a component when the app launches.
public enum LanguageProbeResult: Equatable, Sendable {
    case installed, notInstalled, unsupported
}

/// Who asked. Onboarding and resume honour Low Power Mode; the owner tapping Install does not.
public enum LanguageInstallSource: Equatable, Sendable {
    case onboarding, resume, owner
}

public enum LanguagePackEvent: Equatable, Sendable {
    case launched(wanted: Set<LanguagePackID>, analyzerSupported: Bool, lowPower: Bool)
    case probed(LanguageComponent, LanguageProbeResult)
    case installRequested(Set<LanguagePackID>, source: LanguageInstallSource)
    case installNowTapped
    case lowPowerChanged(Bool)
    case progress(token: UInt64, fraction: Double)
    case succeeded(token: UInt64)
    case failed(token: UInt64, reason: String)
    case cancelRequested
    case removeRequested(LanguagePackID)
}

public enum LanguagePackEffect: Equatable, Sendable {
    case probe([LanguageComponent])
    case startInstall(token: UInt64, component: LanguageComponent)
    case cancelInstall(token: UInt64)
    case release(LanguageComponent)
    case persistWanted(Set<LanguagePackID>)
}

/// The whole installer as one value. `wanted` is the consent and the only thing persisted; downloading is
/// never persisted, so a quit mid-download resumes from the wanted set on the next launch.
public struct LanguagePackState: Equatable, Sendable {
    public struct Running: Equatable, Sendable {
        public let token: UInt64
        public let component: LanguageComponent
    }

    public internal(set) var wanted: Set<LanguagePackID>
    public internal(set) var components: [LanguageComponent: LanguageComponentState]
    public internal(set) var running: Running?
    public internal(set) var lowPower: Bool
    public internal(set) var lowPowerOverride: Bool
    public internal(set) var analyzerSupported: Bool
    var nextToken: UInt64

    public init(wanted: Set<LanguagePackID> = [], analyzerSupported: Bool = true, lowPower: Bool = false) {
        self.wanted = wanted
        self.analyzerSupported = analyzerSupported
        self.lowPower = lowPower
        lowPowerOverride = false
        running = nil
        nextToken = 1
        var map: [LanguageComponent: LanguageComponentState] = [:]
        for component in LanguagePackCatalog.all {
            map[component] = component.needsDownload ? (analyzerSupported ? .notInstalled : .unsupportedOnThisMac) : .notNeeded
        }
        components = map
    }

    /// True while Low Power Mode holds queued work back.
    public var blockedByLowPower: Bool { lowPower && !lowPowerOverride }

    public func state(of component: LanguageComponent) -> LanguageComponentState { components[component] ?? .notNeeded }

    public func status(of pack: LanguagePackID) -> LanguagePackStatus {
        let needed = LanguagePackCatalog.components(of: pack).filter(\.needsDownload)
        let states = needed.map { state(of: $0) }
        if states.isEmpty { return .installed }
        if states.contains(.unsupportedOnThisMac) { return .unsupportedOnThisMac }
        for case .failed(let reason) in states { return .failed(reason: reason) }
        if states.allSatisfy({ $0 == .installed }) { return .installed }
        if states.contains(where: { if case .downloading = $0 { return true } else { return false } }) {
            let total = states.reduce(0.0) { sum, state in
                switch state {
                case .installed: sum + 1
                case .downloading(let progress): sum + progress
                default: sum
                }
            }
            return .installing(progress: total / Double(states.count))
        }
        if states.contains(.queued) { return blockedByLowPower ? .deferredForLowPower : .queued }
        return .notInstalled
    }

    /// Sum of the sizes that are known; nil when none of them is.
    public func knownBytes(of packs: Set<LanguagePackID>) -> Int64? {
        let sizes = packs.flatMap(LanguagePackCatalog.components(of:)).compactMap(\.approximateBytes)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    public var isBusy: Bool {
        running != nil || components.values.contains(.queued)
    }

    public static func reduce(_ state: LanguagePackState, _ event: LanguagePackEvent) -> (LanguagePackState, [LanguagePackEffect]) {
        var next = state
        var effects: [LanguagePackEffect] = []
        switch event {
        case .launched(let wanted, let analyzerSupported, let lowPower):
            next = LanguagePackState(wanted: wanted, analyzerSupported: analyzerSupported, lowPower: lowPower)
            let toProbe = wanted.sorted(by: Self.packOrder).flatMap(LanguagePackCatalog.components(of:))
                .filter { $0.needsDownload && analyzerSupported }
            if !toProbe.isEmpty { effects.append(.probe(toProbe)) }

        case .probed(let component, let result):
            guard component.needsDownload, state.running?.component != component else { break }
            switch result {
            case .installed: next.components[component] = .installed
            case .unsupported: next.components[component] = .unsupportedOnThisMac
            case .notInstalled:
                next.components[component] = next.wanted.contains(component.pack) ? .queued : .notInstalled
            }

        case .installRequested(let packs, let source):
            let before = next.wanted
            next.wanted.formUnion(packs)
            if next.wanted != before { effects.append(.persistWanted(next.wanted)) }
            for pack in packs {
                for component in LanguagePackCatalog.components(of: pack) {
                    switch next.state(of: component) {
                    case .notInstalled, .failed: next.components[component] = .queued
                    default: break
                    }
                }
            }
            if source == .owner, next.lowPower { next.lowPowerOverride = true }

        case .installNowTapped:
            if next.lowPower { next.lowPowerOverride = true }

        case .lowPowerChanged(let on):
            next.lowPower = on
            if !on { next.lowPowerOverride = false }
            if on, !next.lowPowerOverride, let running = next.running {
                effects.append(.cancelInstall(token: running.token))
                next.components[running.component] = .queued
                next.running = nil
            }

        case .progress(let token, let fraction):
            guard let running = next.running, running.token == token else { break }
            next.components[running.component] = .downloading(progress: min(max(fraction, 0), 1))

        case .succeeded(let token):
            guard let running = next.running, running.token == token else { break }
            next.components[running.component] = .installed
            next.running = nil

        case .failed(let token, let reason):
            guard let running = next.running, running.token == token else { break }
            next.components[running.component] = .failed(reason: reason)
            next.running = nil

        case .cancelRequested:
            if let running = next.running { effects.append(.cancelInstall(token: running.token)) }
            next.running = nil
            var dropped: Set<LanguagePackID> = []
            for (component, value) in next.components {
                switch value {
                case .queued, .downloading, .failed:
                    next.components[component] = .notInstalled
                    dropped.insert(component.pack)
                default: break
                }
            }
            let before = next.wanted
            next.wanted.subtract(dropped)
            if next.wanted != before { effects.append(.persistWanted(next.wanted)) }

        case .removeRequested(let pack):
            if let running = next.running, running.component.pack == pack {
                effects.append(.cancelInstall(token: running.token))
                next.running = nil
            }
            for component in LanguagePackCatalog.components(of: pack) where component.needsDownload {
                switch next.state(of: component) {
                case .installed:
                    effects.append(.release(component))
                    next.components[component] = .notInstalled
                case .queued, .downloading, .failed:
                    next.components[component] = .notInstalled
                default: break
                }
            }
            if next.wanted.remove(pack) != nil { effects.append(.persistWanted(next.wanted)) }
        }
        effects += next.advance()
        return (next, effects)
    }

    /// Starts the next queued component when nothing runs and Low Power Mode does not hold it back.
    private mutating func advance() -> [LanguagePackEffect] {
        guard running == nil, !blockedByLowPower else { return [] }
        let order = LanguagePackID.allCases.sorted(by: Self.packOrder).flatMap(LanguagePackCatalog.components(of:))
        guard let component = order.first(where: { components[$0] == .queued }) else { return [] }
        let token = nextToken
        nextToken += 1
        running = Running(token: token, component: component)
        components[component] = .downloading(progress: 0)
        return [.startInstall(token: token, component: component)]
    }

    private static func packOrder(_ a: LanguagePackID, _ b: LanguagePackID) -> Bool {
        (LanguagePackID.allCases.firstIndex(of: a) ?? 0) < (LanguagePackID.allCases.firstIndex(of: b) ?? 0)
    }
}

/// The persisted consent, as the strings stored in UserDefaults.
public enum LanguagePackConsent {
    public static func encode(_ wanted: Set<LanguagePackID>) -> [String] {
        LanguagePackID.allCases.filter(wanted.contains).map(\.rawValue)
    }

    public static func decode(_ raw: [String]?) -> Set<LanguagePackID> {
        Set((raw ?? []).compactMap(LanguagePackID.init(rawValue:)))
    }
}
