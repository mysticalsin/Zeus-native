import Foundation

/// Whether this process is a test run. The updater refuses to replace the installed app when it is.
public enum UpdateTestGuard {
    public static func isRunningTests(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if environment["ZEUS_UPDATE_TESTS"] == "1" { return true }
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        let blob = arguments.joined(separator: " ")
        return blob.contains("xctest") || blob.contains(".xctest")
    }
}

/// A strict release version. Pre-release text and extra components are refused.
public enum UpdateVersions {
    public static func release(_ string: String) -> ZeusVersion? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        return ZeusVersion(
            major: numbers[0],
            minor: numbers.count > 1 ? numbers[1] : 0,
            patch: numbers.count > 2 ? numbers[2] : 0
        )
    }
}

/// Feed address and the EdDSA public key. Automatic checks are off until both are present.
public struct UpdateConfiguration: Equatable, Sendable {
    public static let automaticChecksKey = "about.autoUpdate"
    public static let feedURLKey = "about.updateFeedURL"
    public static let checkNowKey = "about.checkNow"
    public static let publicKeyInfoKey = "SUPublicEDKey"
    public static let bundledFeedInfoKey = "SUFeedURL"

    public var automaticChecks: Bool
    public var feedURL: String
    public var publicKey: String

    public init(automaticChecks: Bool = false, feedURL: String = "", publicKey: String = "") {
        self.automaticChecks = automaticChecks
        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    /// The feed and the public key come from the build. A settings value cannot replace either.
    public static func resolve(automaticChecks: Bool, info: [String: String]) -> UpdateConfiguration {
        UpdateConfiguration(
            automaticChecks: automaticChecks,
            feedURL: info[bundledFeedInfoKey] ?? "",
            publicKey: info[publicKeyInfoKey] ?? ""
        )
    }

    public static func resolve(automaticChecks: Bool, bundleInfo: [String: Any]) -> UpdateConfiguration {
        let info = bundleInfo.reduce(into: [String: String]()) { partial, pair in
            if let value = pair.value as? String { partial[pair.key] = value }
        }
        return resolve(automaticChecks: automaticChecks, info: info)
    }

    /// 32-byte EdDSA public key. A longer value, including a private key, is ignored.
    public var publicKeyBytes: Data? {
        let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed), data.count == 32 else { return nil }
        return data
    }

    public var secureFeedURL: URL? { UpdateFeedPolicy.feedURL(from: feedURL) }

    public var isConfigured: Bool { secureFeedURL != nil && publicKeyBytes != nil }
}

public struct UpdateContext: Equatable, Sendable {
    public var configuration: UpdateConfiguration
    public var currentVersion: ZeusVersion
    public var duringTests: Bool
    public var disposableCopy: Bool
    public var now: Date
    public var reduceMotion: Bool
    public var acceptsUpdates: Bool

    public init(
        configuration: UpdateConfiguration,
        currentVersion: ZeusVersion,
        duringTests: Bool,
        disposableCopy: Bool,
        now: Date,
        reduceMotion: Bool,
        acceptsUpdates: Bool = true
    ) {
        self.configuration = configuration
        self.currentVersion = currentVersion
        self.duringTests = duringTests
        self.disposableCopy = disposableCopy
        self.now = now
        self.reduceMotion = reduceMotion
        self.acceptsUpdates = acceptsUpdates
    }

    var canAct: Bool { configuration.isConfigured && acceptsUpdates }
}

public struct UpdateCandidate: Equatable, Sendable {
    public var version: ZeusVersion
    public var downloadURL: URL
    public var edSignature: String
    public var notes: [String]

    public init(version: ZeusVersion, downloadURL: URL, edSignature: String, notes: [String]) {
        self.version = version
        self.downloadURL = downloadURL
        self.edSignature = edSignature
        self.notes = notes
    }
}

public enum UpdateFailureReason: Equatable, Sendable, Error {
    case network
    case signature
    case downgrade
    case insecureFeed
    case unreadable
    case installRefused
    case installFailed
}

public enum UpdateSignatureVerdict: Equatable, Sendable {
    case valid
    case invalid
    case missing
}

public enum UpdateSessionState: Equatable, Sendable {
    case disabled
    case idle
    case checking
    case upToDate
    case available(UpdateCandidate)
    case downloading(UpdateCandidate)
    case verifying(UpdateCandidate)
    case readyToInstall(UpdateCandidate)
    case installing(UpdateCandidate)
    case failed(UpdateFailureReason)
}

public enum UpdateEvent: Equatable, Sendable {
    case setAutomaticChecks(Bool)
    case checkRequested
    case checkFailed(UpdateFailureReason)
    case checkOffer(UpdateCandidate)
    case checkUpToDate
    case downloadRequested
    case downloadFinished
    case downloadFailed(UpdateFailureReason)
    case verifyFinished(UpdateSignatureVerdict)
    case installRequested
    case installFinished(Bool)
}

public enum UpdateEffect: Equatable, Sendable {
    case fetchFeed
    case cancelNetwork
    case download(URL)
    case verify
    case discardStagedUpdate
    case install
    case relaunch
    case rollback
    case armAutomaticChecks
}

public struct UpdateStep: Equatable, Sendable {
    public var state: UpdateSessionState
    public var effects: [UpdateEffect]
    public var recordCheck: Bool

    public init(state: UpdateSessionState, effects: [UpdateEffect] = [], recordCheck: Bool = false) {
        self.state = state
        self.effects = effects
        self.recordCheck = recordCheck
    }
}

public enum UpdateCommands {
    /// Turning automatic checks on also asks for one check. An unconfigured updater does nothing.
    public static func events(forAutomaticChecks enabled: Bool, configured: Bool) -> [UpdateEvent] {
        guard configured else { return [] }
        if enabled { return [.setAutomaticChecks(true), .checkRequested] }
        return [.setAutomaticChecks(false)]
    }
}

public enum UpdateInstallDecision: Equatable, Sendable {
    case refuse
    case replaceDisposableCopy
    case replaceRunningApp
}

public enum UpdateInstallOutcome: Equatable, Sendable {
    case leftInPlace
    case rolledBack
    case replacedDisposableCopy
    case replacedRunningApp
}

public enum UpdateInstallGate {
    public static func decision(signatureValid: Bool, versionIsNewer: Bool, duringTests: Bool, disposableCopy: Bool) -> UpdateInstallDecision {
        guard signatureValid, versionIsNewer else { return .refuse }
        if duringTests { return disposableCopy ? .replaceDisposableCopy : .refuse }
        return .replaceRunningApp
    }

    /// The installed app is replaced only for a real launch, after a valid newer signature.
    public static func replacesInstalledApp(_ decision: UpdateInstallDecision, duringTests: Bool) -> Bool {
        decision == .replaceRunningApp && !duringTests
    }

    public static func outcome(decision: UpdateInstallDecision, succeeded: Bool, duringTests: Bool) -> UpdateInstallOutcome {
        if !succeeded { return decision == .refuse ? .leftInPlace : .rolledBack }
        switch decision {
        case .refuse: return .leftInPlace
        case .replaceDisposableCopy: return .replacedDisposableCopy
        case .replaceRunningApp: return duringTests ? .leftInPlace : .replacedRunningApp
        }
    }
}

public enum UpdateHostSelection: Equatable, Sendable {
    case refuse
    case runningApp
    case disposableCopy(String)
}

public enum UpdateHosts {
    /// Tests may touch a disposable copy only. The same path as the running app is refused.
    public static func select(duringTests: Bool, disposableCopyPath: String?, runningBundlePath: String) -> UpdateHostSelection {
        if duringTests {
            let path = disposableCopyPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty, path != runningBundlePath else { return .refuse }
            return .disposableCopy(path)
        }
        return .runningApp
    }
}

public enum UpdateClock {
    public static func checkedLine(_ date: Date?) -> String {
        guard let date else { return "Not checked yet." }
        return formatter().string(from: date)
    }

    public static func date(from line: String) -> Date? {
        formatter().date(from: line)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

/// Explicit update states. Download, verify, and install cannot be skipped, and each step is checked again.
public enum UpdateSession {
    public static func initial(_ context: UpdateContext) -> UpdateSessionState {
        guard context.canAct, context.configuration.automaticChecks else { return .disabled }
        return .idle
    }

    public static func reduce(_ state: UpdateSessionState, _ event: UpdateEvent, _ context: UpdateContext) -> UpdateStep {
        switch event {
        case .setAutomaticChecks(let enabled):
            return setAutomatic(state, enabled: enabled, context: context)
        case .checkRequested:
            return requestCheck(state, context: context)
        case .checkFailed(let reason):
            guard case .checking = state else { return UpdateStep(state: state) }
            return UpdateStep(state: .failed(reason), recordCheck: true)
        case .checkOffer(let candidate):
            guard case .checking = state else { return UpdateStep(state: state) }
            return classify(candidate, context)
        case .checkUpToDate:
            guard case .checking = state else { return UpdateStep(state: state) }
            return UpdateStep(state: .upToDate, recordCheck: true)
        case .downloadRequested:
            guard case .available(let candidate) = state else { return UpdateStep(state: state) }
            return beginDownload(candidate, context)
        case .downloadFinished:
            guard case .downloading(let candidate) = state else { return UpdateStep(state: state) }
            return UpdateStep(state: .verifying(candidate), effects: [.verify])
        case .downloadFailed(let reason):
            guard case .downloading = state else { return UpdateStep(state: state) }
            return UpdateStep(state: .failed(reason), effects: [.discardStagedUpdate])
        case .verifyFinished(let verdict):
            guard case .verifying(let candidate) = state else { return UpdateStep(state: state) }
            return finishVerify(candidate, verdict: verdict, context: context)
        case .installRequested:
            guard case .readyToInstall(let candidate) = state else { return UpdateStep(state: state) }
            return requestInstall(candidate, context)
        case .installFinished(let succeeded):
            guard case .installing(let candidate) = state else { return UpdateStep(state: state) }
            return finishInstall(candidate, succeeded: succeeded, context: context)
        }
    }

    private static func setAutomatic(_ state: UpdateSessionState, enabled: Bool, context: UpdateContext) -> UpdateStep {
        guard context.canAct else { return UpdateStep(state: state) }
        if enabled {
            switch state {
            case .disabled:
                return UpdateStep(state: .idle, effects: [.armAutomaticChecks])
            case .checking, .downloading, .verifying, .installing:
                return UpdateStep(state: state)
            default:
                return UpdateStep(state: state, effects: [.armAutomaticChecks])
            }
        }
        switch state {
        case .installing:
            return UpdateStep(state: state)
        case .checking:
            return UpdateStep(state: .disabled, effects: [.cancelNetwork])
        case .downloading, .verifying:
            return UpdateStep(state: .disabled, effects: [.cancelNetwork, .discardStagedUpdate])
        case .readyToInstall, .available:
            return UpdateStep(state: .disabled, effects: [.discardStagedUpdate])
        default:
            return UpdateStep(state: .disabled)
        }
    }

    private static func requestCheck(_ state: UpdateSessionState, context: UpdateContext) -> UpdateStep {
        guard context.canAct else { return UpdateStep(state: state) }
        switch state {
        case .installing:
            return UpdateStep(state: state)
        case .checking, .downloading, .verifying:
            return UpdateStep(state: .checking, effects: [.cancelNetwork, .fetchFeed])
        case .readyToInstall, .available:
            return UpdateStep(state: .checking, effects: [.discardStagedUpdate, .fetchFeed])
        default:
            return UpdateStep(state: .checking, effects: [.fetchFeed])
        }
    }

    private static func classify(_ candidate: UpdateCandidate, _ context: UpdateContext) -> UpdateStep {
        guard UpdateFeedPolicy.isSecure(candidate.downloadURL) else {
            return UpdateStep(state: .failed(.insecureFeed), recordCheck: true)
        }
        if candidate.version < context.currentVersion {
            return UpdateStep(state: .failed(.downgrade), recordCheck: true)
        }
        if candidate.version == context.currentVersion {
            return UpdateStep(state: .upToDate, recordCheck: true)
        }
        let signature = candidate.edSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signature.isEmpty else {
            return UpdateStep(state: .failed(.signature), recordCheck: true)
        }
        var accepted = candidate
        accepted.edSignature = signature
        return UpdateStep(state: .available(accepted), recordCheck: true)
    }

    private static func beginDownload(_ candidate: UpdateCandidate, _ context: UpdateContext) -> UpdateStep {
        guard UpdateFeedPolicy.isSecure(candidate.downloadURL) else {
            return UpdateStep(state: .failed(.insecureFeed))
        }
        guard candidate.version > context.currentVersion else {
            return UpdateStep(state: .failed(.downgrade))
        }
        guard !candidate.edSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return UpdateStep(state: .failed(.signature))
        }
        return UpdateStep(state: .downloading(candidate), effects: [.download(candidate.downloadURL)])
    }

    private static func finishVerify(_ candidate: UpdateCandidate, verdict: UpdateSignatureVerdict, context: UpdateContext) -> UpdateStep {
        guard verdict == .valid,
              UpdateFeedPolicy.isSecure(candidate.downloadURL),
              candidate.version > context.currentVersion,
              !candidate.edSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return UpdateStep(state: .failed(.signature), effects: [.discardStagedUpdate])
        }
        return UpdateStep(state: .readyToInstall(candidate))
    }

    private static func requestInstall(_ candidate: UpdateCandidate, _ context: UpdateContext) -> UpdateStep {
        let newer = candidate.version > context.currentVersion
        let signed = UpdateFeedPolicy.isSecure(candidate.downloadURL)
            && !candidate.edSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && newer
        let decision = UpdateInstallGate.decision(
            signatureValid: signed,
            versionIsNewer: newer,
            duringTests: context.duringTests,
            disposableCopy: context.disposableCopy
        )
        switch decision {
        case .refuse:
            return UpdateStep(state: .failed(.installRefused))
        case .replaceDisposableCopy, .replaceRunningApp:
            return UpdateStep(state: .installing(candidate), effects: [.install])
        }
    }

    private static func finishInstall(_ candidate: UpdateCandidate, succeeded: Bool, context: UpdateContext) -> UpdateStep {
        guard succeeded else { return UpdateStep(state: .failed(.installFailed), effects: [.rollback]) }
        let newer = candidate.version > context.currentVersion
        let decision = UpdateInstallGate.decision(
            signatureValid: true,
            versionIsNewer: newer,
            duringTests: context.duringTests,
            disposableCopy: context.disposableCopy
        )
        if decision == .replaceRunningApp && !context.duringTests {
            return UpdateStep(state: .idle, effects: [.relaunch])
        }
        return UpdateStep(state: .idle)
    }
}
