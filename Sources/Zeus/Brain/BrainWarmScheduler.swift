import AppKit
import Foundation
import ZeusCore

/// One URL session for every HTTP brain, so the TLS and HTTP/2 connection a warm ping opens is the one
/// the next question reuses.
enum BrainHTTP {
    static let observer = BrainHTTPObserver()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: observer, delegateQueue: nil)
    }()
}

/// Logs whether the shared brain session reused its TLS connection (R24 speed).
final class BrainHTTPObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let tx = metrics.transactionMetrics.last else { return }
        let host = task.originalRequest?.url?.host ?? "?"
        let reused = tx.isReusedConnection
        let tlsMs: Int
        if let start = tx.secureConnectionStartDate, let end = tx.secureConnectionEndDate {
            tlsMs = max(0, Int(end.timeIntervalSince(start) * 1000))
        } else {
            tlsMs = 0
        }
        VoiceLog.log("brain", "http host=\(host) reused=\(reused) tls_ms=\(tlsMs)")
    }
}

/// The warm-up actions are explicit so a cloud connection refresh cannot start a local voice worker.
/// Selection and readiness are read only when a local warm-up is actually due.
@MainActor
struct BrainWarmActions {
    struct VoiceSelection: Sendable {
        let provider: VoiceTTSProvider
        let ready: Bool
        let paused: Bool
        let voice: String
        let speed: Double
    }

    var localModel: @MainActor @Sendable () async -> Void
    var cloudConnection: @MainActor @Sendable () async -> Void
    var voiceSelection: @MainActor @Sendable () -> VoiceSelection
    var renderVoice: @MainActor @Sendable (String, Double) async -> Void

    func run(_ targets: Set<BrainWarmPlan.Target>) async {
        guard !Task.isCancelled else { return }
        async let local: Void = targets.contains(.localModel) ? localModel() : ()
        async let cloud: Void = targets.contains(.cloudConnection) ? cloudConnection() : ()
        async let voice: Void = targets.contains(.localModel) ? warmSelectedVoice() : ()
        _ = await (local, cloud, voice)
    }

    func warmSelectedVoice() async {
        guard !Task.isCancelled else { return }
        let selection = voiceSelection()
        guard selection.provider == .kokoro, selection.ready, !selection.paused else { return }
        await renderVoice(selection.voice, selection.speed)
    }

    static var live: Self {
        Self(localModel: { await OpenAICompatProvider.ollama().prewarm() },
             cloudConnection: { await AnthropicAPIProvider().prewarm() },
             voiceSelection: {
                 let settings = VoiceSettings.shared
                 return VoiceSelection(provider: settings.ttsProvider, ready: settings.kokoroReady,
                                       paused: settings.isProviderPaused(.kokoro),
                                       voice: settings.kokoroVoice, speed: settings.kokoroSpeed)
             },
             renderVoice: { voice, speed in
                 await KokoroWorkerSession.shared.prewarm(voice: voice, speed: speed)
             })
    }
}

/// Keeps the brains warm only while Zeus is in use (`BrainWarmPlan`): a loose 2-minute check, a free
/// metadata call for the cloud connection, a one-token ping for the local model. Launch and wake
/// from sleep warm both model connections; voice warms only when Kokoro is selected and ready.
/// The loose check remains scheduled while idle, but an ordinary idle check makes no warm calls.
@MainActor
final class BrainWarmScheduler {
    static let shared = BrainWarmScheduler()

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastActivity: Date?
    private var lastCloud: Date?
    private var lastLocal: Date?
    private var inFlight = false

    /// Hooks for tests.
    var now: () -> Date = { Date() }
    var warm: (Set<BrainWarmPlan.Target>) async -> Void = { targets in
        await BrainWarmActions.live.run(targets)
    }

    func start() {
        guard timer == nil, !TopBarStyle.isSnapshot else { return }
        // The launch warm-up (VoiceTurnController) already ran; the first check is one interval away.
        lastActivity = now()
        lastCloud = lastActivity
        lastLocal = lastActivity
        let timer = Timer.scheduledTimer(withTimeInterval: BrainWarmPlan.checkEvery, repeats: true) { _ in
            Task { @MainActor in await BrainWarmScheduler.shared.tick() }
        }
        timer.tolerance = 30
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                BrainWarmScheduler.shared.noteActivity()
                await BrainWarmScheduler.shared.tick(forced: true)
            }
        }
    }

    /// Tony pressed the key, spoke or asked something.
    func noteActivity() { lastActivity = now() }

    func tick(forced: Bool = false) async {
        guard !inFlight else { return }
        let targets = BrainWarmPlan.due(now: now(), lastActivity: lastActivity, lastCloud: lastCloud, lastLocal: lastLocal, forced: forced)
        guard !targets.isEmpty else { return }
        inFlight = true
        defer { inFlight = false }
        let stamp = now()
        if targets.contains(.cloudConnection) { lastCloud = stamp }
        if targets.contains(.localModel) { lastLocal = stamp }
        await warm(targets)
    }
}
