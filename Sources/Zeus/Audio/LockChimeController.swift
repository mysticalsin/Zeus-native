import AppKit
import AudioToolbox
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
    private var loadGeneration = 0
    private let log = Logger(subsystem: "app.zeus.mac", category: "chime")
    private static let fileLog = Logger(subsystem: "app.zeus.mac", category: "chime")

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
        loadGeneration &+= 1
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        player.stop()
        if engine.isRunning { engine.stop() }
        chosen.removeAll()
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
        // Open and fstat before remembering the path. A symlink is refused here.
        guard case .success = ChimeFileAccess.measureRegularFile(at: url.path) else {
            log.error("chosen chime file is not a regular audio file. Keeping the built-in chime.")
            return
        }
        let bookmark = (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]))
            ?? (try? url.bookmarkData())
        ChimeSettingsPersistence.saveBookmark(bookmark, event: event, defaults: .standard)
        SettingsStore.shared.set(ChimeSettingsKey.pathID(event), url.path)
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

    /// Reads and decodes off the main thread. Launch only remembers that work is in flight.
    private func installChosenFiles() {
        loadGeneration &+= 1
        let generation = loadGeneration
        let files = ChimeEvent.allCases.compactMap { event -> (ChimeEvent, ChimeFileReference)? in
            guard let file = settings.file(for: event) else { return nil }
            return (event, file)
        }
        guard !files.isEmpty else {
            chosen.removeAll()
            return
        }
        Task.detached { [weak self] in
            var loaded: [ChimeEvent: AVAudioPCMBuffer] = [:]
            for (event, file) in files {
                if let buffer = Self.decodeChosen(file, event: event) {
                    loaded[event] = buffer
                } else if let note = ChimeSoundResolver.resolve(event: event, path: file.path, readable: false).privateLog {
                    Self.fileLog.error("\(note, privacy: .private)")
                }
            }
            let box = ChimeBufferBox(loaded)
            await self?.storeChosen(box, generation: generation)
        }
    }

    private func storeChosen(_ box: ChimeBufferBox, generation: Int) {
        guard generation == loadGeneration else { return }
        for event in ChimeEvent.allCases {
            chosen[event] = box.buffers[event]
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

    /// Resolves the bookmark the file picker stored. A stale bookmark is written back before the file is opened.
    private nonisolated static func resolvedURL(_ file: ChimeFileReference, event: ChimeEvent) -> URL? {
        if let bookmark = file.bookmark {
            var stale = false
            if let scoped = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                storeRefreshedBookmark(scoped, stale: stale, event: event)
                return scoped
            }
            stale = false
            if let plain = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale) {
                storeRefreshedBookmark(plain, stale: stale, event: event)
                return plain
            }
        }
        let path = file.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private nonisolated static func storeRefreshedBookmark(_ url: URL, stale: Bool, event: ChimeEvent) {
        let fresh = (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]))
            ?? (try? url.bookmarkData())
        guard let replacement = ChimeBookmark.replacement(stale: stale, refreshed: fresh) else { return }
        ChimeSettingsPersistence.saveBookmark(replacement, event: event, defaults: .standard)
    }

    /// The bytes come from one `O_NOFOLLOW` descriptor. The decode buffer is sized only after the header is bounded.
    private nonisolated static func decodeChosen(_ file: ChimeFileReference, event: ChimeEvent) -> AVAudioPCMBuffer? {
        guard let url = resolvedURL(file, event: event) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard case .success(let data) = ChimeFileAccess.readRegularFile(at: url.path) else { return nil }
        return decode(data)
    }

    private nonisolated static func decode(_ data: Data) -> AVAudioPCMBuffer? {
        let memory = ChimeMemoryAudio(data)
        var fileID: AudioFileID?
        let opened = AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(memory).toOpaque(),
            chimeReadAudio, nil, chimeAudioSize, nil, 0, &fileID)
        guard opened == noErr, let fileID else { return nil }
        defer { AudioFileClose(fileID) }
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &formatSize, &format) == noErr else { return nil }
        let frames = ChimeAudioLimits.frameCount(
            headerFrames: headerFrameCount(fileID, format: format),
            sampleRate: format.mSampleRate,
            channels: Int(format.mChannelsPerFrame))
        guard let frames else { return nil }
        var extended: ExtAudioFileRef?
        guard ExtAudioFileWrapAudioFileID(fileID, false, &extended) == noErr, let extended else { return nil }
        defer { ExtAudioFileDispose(extended) }
        guard let client = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ChimeTone.sampleRate, channels: 1, interleaved: false) else { return nil }
        var clientDescription = client.streamDescription.pointee
        let propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard ExtAudioFileSetProperty(extended, kExtAudioFileProperty_ClientDataFormat, propertySize, &clientDescription) == noErr else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: client, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        var count = UInt32(frames)
        guard ExtAudioFileRead(extended, &count, buffer.mutableAudioBufferList) == noErr, count > 0 else { return nil }
        buffer.frameLength = count
        return buffer
    }

    private nonisolated static func headerFrameCount(_ file: AudioFileID, format: AudioStreamBasicDescription) -> Int64 {
        var packets: UInt64 = 0
        var size = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &size, &packets) == noErr else { return Int64.max }
        let perPacket = UInt64(max(format.mFramesPerPacket, 1))
        guard format.mFramesPerPacket > 0 else { return Int64.max }
        if packets > UInt64(Int64.max) / perPacket { return Int64.max }
        let frames = packets * perPacket
        return frames == 0 ? 0 : Int64(frames)
    }
}

/// Holds one chosen file's bytes for the AudioFile callbacks. The decode call is synchronous.
private final class ChimeMemoryAudio: @unchecked Sendable {
    let data: Data
    init(_ data: Data) { self.data = data }
}

/// Buffers produced off the main thread, handed back for playback.
private final class ChimeBufferBox: @unchecked Sendable {
    let buffers: [ChimeEvent: AVAudioPCMBuffer]
    init(_ buffers: [ChimeEvent: AVAudioPCMBuffer]) { self.buffers = buffers }
}

private func chimeReadAudio(_ client: UnsafeMutableRawPointer, _ position: Int64, _ request: UInt32, _ buffer: UnsafeMutableRawPointer, _ actual: UnsafeMutablePointer<UInt32>) -> OSStatus {
    let audio = Unmanaged<ChimeMemoryAudio>.fromOpaque(client).takeUnretainedValue()
    guard position >= 0, position <= Int64(audio.data.count) else { return kAudioFileUnspecifiedError }
    let start = Int(position)
    guard start <= audio.data.count else { return kAudioFileUnspecifiedError }
    let amount = min(Int(request), audio.data.count - start)
    if amount > 0 {
        let destination = UnsafeMutableRawBufferPointer(start: buffer, count: amount)
        _ = audio.data.copyBytes(to: destination, from: start..<(start + amount))
    }
    actual.pointee = UInt32(amount)
    return noErr
}

private func chimeAudioSize(_ client: UnsafeMutableRawPointer) -> Int64 {
    Int64(Unmanaged<ChimeMemoryAudio>.fromOpaque(client).takeUnretainedValue().data.count)
}
