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

/// Keeps the brains warm only while voice is in use (`BrainWarmPlan`). Nothing runs at launch or
/// wake. The talk key going down starts the first warm-up and a loose 2-minute timer (a free
/// metadata call for the cloud connection, a one-token ping for the local model); the timer
/// stops itself when the active window passes, so an idle app has no timer and no calls.
@MainActor
final class BrainWarmScheduler {
    static let shared = BrainWarmScheduler()

    private var enabled = false
    private var timer: Timer?
    private var lastActivity: Date?
    private var lastCloud: Date?
    private var lastLocal: Date?
    private var inFlight = false

    /// Hooks for tests.
    var now: () -> Date = { Date() }
    var warm: (Set<BrainWarmPlan.Target>) async -> Void = { targets in
        await BrainWarmActions.live.run(targets)
    }

    /// Allows warm-ups; starts nothing.
    func start() {
        guard !TopBarStyle.isSnapshot else { return }
        enabled = true
    }

    /// The talk key went down: warm now, and keep warm while the conversation goes on.
    func talkKeyDown() {
        noteActivity()
        Task { await tick() }
    }

    /// The person pressed the key, spoke or asked something.
    func noteActivity() {
        lastActivity = now()
        armTimer()
    }

    private func armTimer() {
        guard enabled, timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: BrainWarmPlan.checkEvery, repeats: true) { _ in
            Task { @MainActor in await BrainWarmScheduler.shared.tick() }
        }
        timer.tolerance = 30
        self.timer = timer
    }

    func tick() async {
        if BrainWarmPlan.isIdle(now: now(), lastActivity: lastActivity) {
            timer?.invalidate()
            timer = nil
            return
        }
        guard !inFlight else { return }
        let targets = BrainWarmPlan.due(now: now(), lastActivity: lastActivity, lastCloud: lastCloud, lastLocal: lastLocal)
        guard !targets.isEmpty else { return }
        inFlight = true
        defer { inFlight = false }
        let stamp = now()
        if targets.contains(.cloudConnection) { lastCloud = stamp }
        if targets.contains(.localModel) { lastLocal = stamp }
        await warm(targets)
    }
}
