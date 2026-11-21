import AppKit
import AVFoundation
import Intents
import os
import UniformTypeIdentifiers
import ZeusCore

/// Plays one short chime when the Mac locks or sleeps, and one when it wakes.
///
/// The samples are ready before the notice arrives. `willSleep` and the lock notice run this
/// handler on the posting thread, which is the main thread, so the chime starts before sleep
/// continues. The handler only starts audio that is already in memory. It does not read a file,
/// and it does not change the system output volume: the player gain is the chime slider, and
/// macOS still applies the menu-bar volume.
@MainActor
final class LockChimeController {
    static let shared = LockChimeController()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var graphReady = false
    private var started = false
    private var debouncer = ChimeDebouncer()
    private var settings = ChimeSettingsSnapshot(enabled: true, volume: ChimeSettingsSnapshot.defaultVolume, close: nil, open: nil)
    private var builtIn: [ChimeEvent: AVAudioPCMBuffer] = [:]
    private var chosen: [ChimeEvent: AVAudioPCMBuffer] = [:]
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private let log = Logger(subsystem: "app.zeus.mac", category: "chime")

    private init() {}

    func start() {
        guard !TopBarStyle.isSnapshot, !started else { return }
        started = true
        storeBuiltIn()
        _ = prepareEngine()
        settings = ChimeSettingsPersistence.load(defaults: .standard)
        installChosenFiles()
        debouncer.arm()
        let workspace = NSWorkspace.shared.notificationCenter
        watch(workspace, NSWorkspace.willSleepNotification, .willSleep)
        watch(workspace, NSWorkspace.didWakeNotification, .didWake)
        watch(workspace, NSWorkspace.screensDidSleepNotification, .screensDidSleep)
        watch(workspace, NSWorkspace.screensDidWakeNotification, .screensDidWake)
        watch(workspace, NSWorkspace.willPowerOffNotification, .willPowerOff)
        let distributed = DistributedNotificationCenter.default()
        watch(distributed, Notification.Name("com.apple.screenIsLocked"), .sessionLocked)
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked"), .sessionUnlocked)
    }

    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        player.stop()
        if engine.isRunning { engine.stop() }
        started = false
    }

    /// Settings changed. A new file is read here, not while the Mac is going to sleep.
    func reload() {
        let next = ChimeSettingsPersistence.load(defaults: .standard)
        let sameFiles = next.close == settings.close && next.open == settings.open
        settings = next
        if !sameFiles { installChosenFiles() }
    }

    func preview(_ event: ChimeEvent) {
        guard !TopBarStyle.isSnapshot else { return }
        if builtIn.isEmpty { storeBuiltIn() }
        if !started {
            settings = ChimeSettingsPersistence.load(defaults: .standard)
            installChosenFiles()
        }
        startPlayback(event, obeySettings: false)
    }

    func chooseFile(for event: ChimeEvent) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Choose sound"
        panel.message = "Zeus reads this file when it plays. The file stays where it is."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let readable = FileManager.default.isReadableFile(atPath: url.path)
        let stored = ChimeSettingsImport.storedPath(path: url.path, readable: readable)
        guard !stored.isEmpty else {
            log.error("chosen chime file is unreadable. Keeping the built-in chime.")
            return
        }
        let bookmark = (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]))
            ?? (try? url.bookmarkData())
        ChimeSettingsPersistence.saveBookmark(bookmark, event: event, defaults: .standard)
        SettingsStore.shared.set(ChimeSettingsKey.pathID(event), stored)
        reload()
    }

    func useDefault(for event: ChimeEvent) {
        ChimeSettingsPersistence.removeBookmark(event, defaults: .standard)
        SettingsStore.shared.set(ChimeSettingsKey.pathID(event), "")
        reload()
    }

    // MARK: Notices

    /// `queue: nil` runs the block before the poster returns, so a close chime starts inside willSleep.
    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ signal: ChimeSignal) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(signal) }
        }
        tokens.append((center, token))
    }

    private func handle(_ signal: ChimeSignal) {
        switch debouncer.receive(signal, at: ProcessInfo.processInfo.systemUptime) {
        case .play(let event): startPlayback(event, obeySettings: true)
        case .cancel: player.stop()
        case .none: break
        }
    }

    // MARK: Audio

    private func startPlayback(_ event: ChimeEvent, obeySettings: Bool) {
        if obeySettings, !ChimePlaybackGate.allows(enabled: settings.enabled, focusActive: Self.focusIsActive) { return }
        guard let buffer = chosen[event] ?? builtIn[event], prepareEngine() else { return }
        player.volume = Float(min(max(settings.volume, 0), 1))
        if !engine.isRunning {
            do { try engine.start() } catch {
                log.error("chime engine did not start")
                return
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    /// Focus status, only when Zeus may already read it. This does not ask for permission.
    private static var focusIsActive: Bool {
        guard INFocusStatusCenter.default.authorizationStatus == .authorized else { return false }
        return INFocusStatusCenter.default.focusStatus.isFocused == true
    }

    private func storeBuiltIn() {
        for event in ChimeEvent.allCases {
            builtIn[event] = buffer(samples: ChimeTone.samples(for: event))
        }
    }

    private func installChosenFiles() {
        for event in ChimeEvent.allCases {
            guard let file = settings.file(for: event) else {
                chosen[event] = nil
                continue
            }
            if let buffer = decode(file) {
                chosen[event] = buffer
            } else {
                chosen[event] = nil
                if let note = ChimeSoundResolver.resolve(event: event, path: file.path, readable: false).privateLog {
                    log.error("\(note, privacy: .private)")
                }
            }
        }
    }

    private static var playbackFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: ChimeTone.sampleRate, channels: 1)
    }

    @discardableResult
    private func prepareEngine() -> Bool {
        guard let format = Self.playbackFormat else { return false }
        if !graphReady {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()
            graphReady = true
        }
        return true
    }

    private func buffer(samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = Self.playbackFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices { channel[index] = samples[index] }
        return buffer
    }

    private func resolvedURL(_ file: ChimeFileReference) -> URL? {
        if let bookmark = file.bookmark {
            var stale = false
            if let scoped = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                return scoped
            }
            if let plain = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale) {
                return plain
            }
        }
        let path = file.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// At most two seconds, and only from a small file, so choosing a sound cannot stall the Mac.
    private func decode(_ file: ChimeFileReference) -> AVAudioPCMBuffer? {
        guard let url = resolvedURL(file) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard bytes > 0, bytes <= 2_000_000 else { return nil }
        guard let audio = try? AVAudioFile(forReading: url), let target = Self.playbackFormat else { return nil }
        let sourceFrames = AVAudioFrameCount(min(Double(audio.length), audio.processingFormat.sampleRate * 2))
        guard sourceFrames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: sourceFrames) else { return nil }
        do { try audio.read(into: source) } catch { return nil }
        guard source.frameLength > 0 else { return nil }
        if audio.processingFormat.sampleRate == target.sampleRate,
           audio.processingFormat.channelCount == target.channelCount,
           audio.processingFormat.commonFormat == target.commonFormat {
            return source
        }
        guard let converter = AVAudioConverter(from: audio.processingFormat, to: target) else { return nil }
        let ratio = target.sampleRate / audio.processingFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let feed = ChimeFileFeed(source)
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if feed.sent {
                outStatus.pointee = .noDataNow
                return nil
            }
            feed.sent = true
            outStatus.pointee = .haveData
            return feed.buffer
        }
        guard error == nil, status != .error, converted.frameLength > 0 else { return nil }
        return converted
    }
}

/// One buffer handed to AVAudioConverter. The convert call is synchronous; the class only satisfies Sendable.
private final class ChimeFileFeed: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var sent = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
