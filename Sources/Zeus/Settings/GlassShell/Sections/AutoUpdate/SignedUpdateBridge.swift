import Foundation
#if canImport(Sparkle)
import Sparkle
#endif
import ZeusCore

/// Hands a verified update to the signed updater. Tests and a missing configuration never touch the installed app.
@MainActor
final class SignedUpdateBridge: NSObject {
    static let shared = SignedUpdateBridge()

    private var resume: ((UpdateEvent) -> Void)?
    private var accepted: UpdateCandidate?
    private var context = UpdateContext(
        configuration: UpdateConfiguration(),
        currentVersion: ZeusVersion(major: 0, minor: 0, patch: 0),
        duringTests: true,
        disposableCopy: false,
        now: Date(),
        reduceMotion: true,
        acceptsUpdates: false
    )

    func beginDownload(candidate: UpdateCandidate, context: UpdateContext, resume: @escaping (UpdateEvent) -> Void) {
        self.resume = resume
        self.accepted = candidate
        self.context = context
        let host = UpdateHosts.select(
            duringTests: context.duringTests || UpdateTestGuard.isRunningTests(),
            disposableCopyPath: nil,
            runningBundlePath: Bundle.main.bundleURL.path
        )
        guard context.canAct, case .runningApp = host else {
            finish(.downloadFailed(.installRefused))
            return
        }
        #if canImport(Sparkle)
        guard startUpdater() else {
            finish(.downloadFailed(.network))
            return
        }
        updater?.checkForUpdates()
        #else
        finish(.downloadFailed(.installRefused))
        #endif
    }

    func confirmInstall(resume: @escaping (UpdateEvent) -> Void) {
        self.resume = resume
        #if canImport(Sparkle)
        guard let reply = installReply, allowsReplacement else {
            installReply?(.dismiss)
            installReply = nil
            finish(.installFinished(false))
            return
        }
        installReply = nil
        reply(.install)
        #else
        finish(.installFinished(false))
        #endif
    }

    func relaunchIfAllowed(_ context: UpdateContext) {
        // The signed updater relaunches after a confirmed install. This gate is the only extra check.
        self.context = context
        _ = UpdateInstallGate.replacesInstalledApp(.replaceRunningApp, duringTests: context.duringTests || UpdateTestGuard.isRunningTests())
    }

    func cancel() {
        #if canImport(Sparkle)
        downloadCancellation?()
        downloadCancellation = nil
        installReply?(.dismiss)
        installReply = nil
        #endif
    }

    private func finish(_ event: UpdateEvent) {
        let callback = resume
        Task { @MainActor in callback?(event) }
    }

    fileprivate var allowsReplacement: Bool {
        let host = UpdateHosts.select(
            duringTests: context.duringTests || UpdateTestGuard.isRunningTests(),
            disposableCopyPath: nil,
            runningBundlePath: Bundle.main.bundleURL.path
        )
        return host == .runningApp && context.canAct
    }

    #if canImport(Sparkle)
    private var updater: SPUUpdater?
    private let userDriver = UpdatesUserDriver()
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var downloadCancellation: (() -> Void)?

    private func startUpdater() -> Bool {
        if updater != nil { return true }
        let bundle = Bundle.main
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: userDriver, delegate: self)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        do {
            try updater.start()
        } catch {
            return false
        }
        _ = updater.clearFeedURLFromUserDefaults()
        userDriver.bridge = self
        self.updater = updater
        return true
    }

    fileprivate func sparkleFoundUpdate(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }

    fileprivate func sparkleReadyToInstall(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        finish(.downloadFinished)
        finish(.verifyFinished(.valid))
    }

    fileprivate func sparkleFailed(_ error: Error) {
        let ns = error as NSError
        let signature = ns.domain == SUSparkleErrorDomain && (
            ns.code == Int(SUError.signatureError.rawValue)
            || ns.code == Int(SUError.validationError.rawValue)
            || ns.code == Int(SUError.insufficientSigningError.rawValue)
            || ns.code == Int(SUError.noPublicDSAFoundError.rawValue)
        )
        let downgrade = ns.domain == SUSparkleErrorDomain && ns.code == Int(SUError.downgradeError.rawValue)
        if signature {
            finish(.downloadFinished)
            finish(.verifyFinished(.invalid))
        } else if downgrade {
            finish(.downloadFailed(.downgrade))
        } else {
            finish(.downloadFailed(.network))
        }
    }

    fileprivate func sparkleCancelledDownload(_ cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
    }
    #endif
}

#if canImport(Sparkle)
extension SignedUpdateBridge: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        context.configuration.secureFeedURL?.absoluteString
    }

    func updaterShouldPromptForPermissionToCheckForUpdates(_ updater: SPUUpdater) -> Bool { false }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard accepts(item) else {
            throw NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "The update was refused.",
            ])
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        false
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        allowsReplacement
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        sparkleFailed(error)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        sparkleFailed(error)
    }

    private func accepts(_ item: SUAppcastItem) -> Bool {
        guard item.signingValidationStatus != .failed else { return false }
        guard let url = item.fileURL, UpdateFeedPolicy.isSecure(url) else { return false }
        guard let version = UpdateVersions.release(item.displayVersionString), version > context.currentVersion else { return false }
        guard let accepted, version == accepted.version else { return false }
        return enclosureSignature(item).isEmpty == false
    }

    private func enclosureSignature(_ item: SUAppcastItem) -> String {
        let properties = item.propertiesDictionary
        let enclosure = properties[SURSSElementEnclosure] as? [String: Any] ?? properties as? [String: Any] ?? [:]
        let value = enclosure[SUAppcastAttributeEDSignature] as? String ?? properties[SUAppcastAttributeEDSignature] as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class UpdatesUserDriver: NSObject, SPUUserDriver {
    weak var bridge: SignedUpdateBridge?

    func showUpdatePermissionRequest(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, automaticUpdateDownloading: NSNumber(value: false), sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        bridge?.sparkleCancelledDownload(cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        bridge?.sparkleFoundUpdate(reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        bridge?.sparkleFailed(error)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        bridge?.sparkleFailed(error)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        bridge?.sparkleCancelledDownload(cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReadyToInstallAndRelaunch(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
        bridge?.sparkleReadyToInstall(reply: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        guard applicationTerminated == false, bridge?.allowsReplacement == true else { return }
        retryTerminatingApplication()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {}

    func showUpdateInFocus() {}
}
#endif
