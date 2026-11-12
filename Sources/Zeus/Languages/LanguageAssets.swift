import Foundation
import Speech
import ZeusCore

/// Apple's SpeechAnalyzer language assets, as plain async calls. Nonisolated on purpose: the progress
/// observer below is a system callback and must not be written inside a main-actor type.
enum LanguageAssets {
    enum Failure: LocalizedError {
        case needsNewerMacOS, notSupported
        var errorDescription: String? {
            switch self {
            case .needsNewerMacOS: "Needs macOS 26 or later."
            case .notSupported: "Apple does not offer this language on this Mac."
            }
        }
    }

    static var isSupportedOS: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    static func probe(locale: String) async -> LanguageProbeResult {
        guard #available(macOS 26, *) else { return .unsupported }
        guard SpeechTranscriber.isAvailable, let transcriber = await transcriber(locale: locale) else { return .unsupported }
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .installed
        case .supported, .downloading: return .notInstalled
        default: return .unsupported
        }
    }

    /// Downloads and installs the locale's model. Returns when macOS reports it installed. Cancelling the
    /// calling task cancels the download.
    static func install(locale: String, progress report: @escaping @Sendable (Double) -> Void) async throws {
        guard #available(macOS 26, *) else { throw Failure.needsNewerMacOS }
        guard let transcriber = await transcriber(locale: locale) else { throw Failure.notSupported }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let progress = request.progress
            let observation = progress.observe(\.fractionCompleted) { value, _ in report(value.fractionCompleted) }
            defer { observation.invalidate() }
            try await withTaskCancellationHandler {
                try await request.downloadAndInstall()
            } onCancel: {
                progress.cancel()
            }
        }
        report(1)
        // Keep the model for this locale. A refusal (reservation limit) only means macOS may reclaim it later.
        _ = try? await AssetInventory.reserve(locale: transcriber.selectedLocales.first ?? Locale(identifier: locale))
    }

    /// Lets macOS free the locale's model.
    static func release(locale: String) async {
        guard #available(macOS 26, *) else { return }
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) ?? Locale(identifier: locale)
        _ = await AssetInventory.release(reservedLocale: resolved)
    }

    @available(macOS 26, *)
    private static func transcriber(locale: String) async -> SpeechTranscriber? {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { return nil }
        return SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    /// Low Power Mode changes, as a stream of the new value.
    static func lowPowerChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
                continuation.yield(ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        }
    }
}
