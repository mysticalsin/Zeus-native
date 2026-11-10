import AVFoundation
import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Explanation native audio adapters without sound")
struct ExplanationAudioTests {
    private func request(_ text: String = "A synthetic beat.") -> ExplanationSpeechRequest {
        .init(event: .init(sessionID: UUID(), turnID: UUID(), sceneID: UUID(), sequence: 0,
                          baseRevision: 0, revision: 1, beatID: "beat", speech: .init(chunkID: "chunk", text: text), cues: []))
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-audio-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private static func pcm(frames: UInt32 = 240, rate: Double = 24_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frames))!
        buffer.frameLength = frames
        if frames > 0 { buffer.floatChannelData![0].initialize(repeating: 0, count: Int(frames)) }
        return buffer
    }

    @MainActor
    private final class Writer: ExplanationSpeechWriting {
        var callbacks: [@Sendable (AVAudioBuffer) -> Void] = []
        var immediate = true
        var stops = 0
        var errorAfterPCM = false
        var requestedVoices: [String?] = []
        var installedVoiceIDs: Set<String>?
        var systemDefaultID: String?
        var resolvedVoices: [String] = []
        var onWrite: (() -> Void)?
        private var releases: [Task<Void, Never>] = []
        func write(text: String, voiceIdentifier: String?, language: String,
                   receive: @escaping @Sendable (AVAudioBuffer) -> Void) throws {
            requestedVoices.append(voiceIdentifier)
            if let installedVoiceIDs {
                resolvedVoices.append(try ExplanationSystemVoices.resolve(requested: voiceIdentifier,
                    installedIDs: installedVoiceIDs, systemDefaultID: systemDefaultID))
            }
            onWrite?()
            callbacks.append(receive)
            if immediate {
                receive(ExplanationAudioTests.pcm())
                receive(ExplanationAudioTests.pcm(frames: 0))
            } else {
                // A failed assertion cannot leave a synthetic callback/continuation alive
                // until the production 60-second synthesis deadline.
                releases.append(Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    receive(ExplanationAudioTests.pcm(frames: 0))
                })
            }
            if errorAfterPCM { throw ExplanationAudioError.invalidPCM }
        }
        func stop() { stops += 1; releases.forEach { $0.cancel() }; releases.removeAll() }
        isolated deinit { releases.forEach { $0.cancel() } }
    }

    @MainActor
    private final class Media: ExplanationMediaPlaying {
        let duration = 0.01
        private var position = 0.0
        var reads = 0
        var currentTime: Double {
            get { reads += 1; return position }
            set { position = newValue }
        }
        var rate: Float = 1
        var isPlaying = false
        var onFinish: ((Bool) -> Void)?
        var stops = 0
        func play() -> Bool { isPlaying = true; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false; stops += 1 }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(predicate(), "Expected synthetic adapter phase did not arrive")
    }

    @Test func selectedInstalledVoiceIsSnapshottedAndChangesApplyToNextRender() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Writer()
        writer.installedVoiceIDs = ["synthetic-a", "synthetic-b"]
        writer.systemDefaultID = "synthetic-a"
        var selected: String? = "synthetic-a"
        var reads = 0
        let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root, selectedVoice: {
            reads += 1
            return selected
        })
        writer.onWrite = { selected = "synthetic-b" } // Cannot change the already-started request.
        do {
            let first = try await output.render(request("First voice"))
            #expect(first.chunk.duration == 0.01 && reads == 1)
            #expect(writer.requestedVoices == ["synthetic-a"] && writer.resolvedVoices == ["synthetic-a"])
        }
        writer.onWrite = nil
        do {
            let second = try await output.render(request("Next voice"))
            #expect(second.chunk.duration == 0.01 && reads == 2)
            #expect(writer.requestedVoices == ["synthetic-a", "synthetic-b"])
            #expect(writer.resolvedVoices == ["synthetic-a", "synthetic-b"])
        }
        selected = "" // Picker's System default value is normalized before the writer.
        do {
            let last = try await output.render(request("System default"))
            #expect(last.chunk.duration == 0.01 && reads == 3)
            #expect(writer.requestedVoices == ["synthetic-a", "synthetic-b", nil])
            #expect(writer.resolvedVoices == ["synthetic-a", "synthetic-b", "synthetic-a"])
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func missingSelectedVoiceFailsWithoutDefaultSubstitutionOrRetainedPCM() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Writer()
        writer.installedVoiceIDs = ["synthetic-installed"]
        writer.systemDefaultID = "synthetic-installed"
        var selected: String? = "synthetic-removed"
        let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root, selectedVoice: { selected })
        await #expect(throws: ExplanationAudioError.voiceNotInstalled) { try await output.render(request()) }
        #expect(writer.requestedVoices == ["synthetic-removed"] && writer.resolvedVoices.isEmpty)
        #expect(writer.callbacks.isEmpty && writer.stops == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        selected = nil // Only this explicit user choice authorizes the installed default.
        do {
            let recovered = try await output.render(request("Explicit default"))
            #expect(recovered.chunk.duration == 0.01 && writer.resolvedVoices == ["synthetic-installed"])
        }
        #expect(throws: ExplanationAudioError.voiceNotInstalled) {
            try ExplanationSystemVoices.resolve(requested: nil, installedIDs: [], systemDefaultID: "not-installed")
        }
    }

    @Test func syntheticPCMHasMeasuredDurationAndPrivateOwnedLifetime() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // No default synthesizer, installed voice, or device is constructed by this fixture.
        let output = SystemExplanationSpeechOutput(writer: Writer(), temporaryRoot: root)
        var prepared: ExplanationPreparedAudio? = try await output.render(request())
        #expect(prepared?.chunk.duration == 0.01)
        #expect(prepared?.chunk.sampleRate == 24_000)
        #expect(prepared?.chunk.alignment == [])
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let directory = try #require(directories.first)
        let permission = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(permission?.intValue == 0o700)
        prepared = nil
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func cancellationDropsLateBuffersAndReleasesFileBeforeNextRender() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Writer(); writer.immediate = false
        let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root)
        let task = Task { try await output.render(request()) }
        defer { task.cancel() }
        try await wait { !writer.callbacks.isEmpty }
        let old = try #require(writer.callbacks.first)
        old(Self.pcm())
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled render returned audio") } catch is CancellationError {} catch { Issue.record("Wrong error") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        old(Self.pcm()); old(Self.pcm(frames: 0))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        writer.immediate = true
        let next = try await output.render(request("Replacement"))
        #expect(next.chunk.duration == 0.01)
        #expect(writer.stops == 2)
    }

    @Test func synchronousCompletionThenWriterErrorDoesNotResumeTwice() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Writer(); writer.errorAfterPCM = true
        let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root)
        let result = try await output.render(request())
        #expect(result.chunk.duration == 0.01)
    }

    @Test func twoBeatQueueRejectsThirdAndCancellationReleasesBothSlots() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Writer(); writer.immediate = false
        let queue = ExplanationSpeechRenderQueue(provider: SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root))
        let first = Task { try await queue.render(request("First")) }
        let second = Task { try await queue.render(request("Second")) }
        defer { first.cancel(); second.cancel(); queue.cancelAll() }
        try await wait { queue.admittedCount == 2 && writer.callbacks.count == 1 }
        #expect(writer.callbacks.count == 1)
        await #expect(throws: ExplanationAudioError.busy) { try await queue.render(request("Third")) }
        queue.cancelAll()
        _ = await first.result; _ = await second.result
        #expect(writer.callbacks.count == 1)
        writer.immediate = true
        #expect(try await queue.render(request("After cancellation")).chunk.duration == 0.01)
    }

    @Test func PCMFormatChangesAndDurationBudgetFailClosed() async throws {
        for durationOverflow in [false, true] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let writer = Writer(); writer.immediate = false
            let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root)
            let task = Task { try await output.render(request()) }
            defer { task.cancel() }
            try await wait { !writer.callbacks.isEmpty }
            let callback = try #require(writer.callbacks.first)
            if durationOverflow {
                let oneSecond = Self.pcm(frames: 24_000)
                for _ in 0..<91 { callback(oneSecond) }
            } else { callback(Self.pcm()); callback(Self.pcm(rate: 48_000)) }
            do { _ = try await task.value; Issue.record("Invalid PCM accepted") }
            catch let error as ExplanationAudioError { #expect(error == (durationOverflow ? .resourceLimit : .invalidPCM)) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    @Test func cancellingQueuedBeatReturnsWithoutWaitingForActiveSynthesis() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Writer(); writer.immediate = false
        let queue = ExplanationSpeechRenderQueue(provider: SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root))
        let first = Task { try await queue.render(request("First")) }
        try await wait { !writer.callbacks.isEmpty }
        let second = Task { try await queue.render(request("Queued")) }
        defer { first.cancel(); second.cancel(); queue.cancelAll() }
        try await wait { queue.admittedCount == 2 }
        second.cancel()
        do { _ = try await second.value; Issue.record("Queued cancellation returned audio") } catch is CancellationError {}
        #expect(writer.callbacks.count == 1 && writer.stops == 0)
        queue.cancelAll(); _ = await first.result
    }

    @Test func playerUsesMediaClockAndRejectsStaleCompletionAfterSeek() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = SystemExplanationSpeechOutput(writer: Writer(), temporaryRoot: root)
        let prepared = try await output.render(request())
        var media: [Media] = [], observations: [ExplanationPlaybackObservation] = []
        let player = ExplanationAudioPlayer(factory: { _ in let item = Media(); media.append(item); return item })
        player.onObservation = { observations.append($0) }
        try player.register(prepared)
        let old = ExplanationPlaybackTicket(audio: prepared.chunk)
        player.execute(.play(ticket: old, audio: prepared.chunk, position: 0, rate: 1))
        #expect(observations.isEmpty) // Commands cannot reenter coordinator scene effects.
        try await wait { observations.count == 1 }
        media[0].currentTime = 0.004
        player.observeClock(); try await wait { observations.last?.position == 0.004 }
        #expect(observations.last?.position == 0.004)
        player.execute(.pause(ticketID: old.id)); try await wait { observations.last?.state == .paused }
        #expect(observations.last?.state == .paused)
        let staleFinish = media[0].onFinish
        let replacement = ExplanationPlaybackTicket(audio: prepared.chunk)
        player.execute(.play(ticket: replacement, audio: prepared.chunk, position: 0.006, rate: 1.5))
        try await wait { observations.last?.ticketID == replacement.id }
        let count = observations.count
        staleFinish?(true)
        #expect(observations.count == count)
        #expect(media[0].stops == 1)
        #expect(media[1].currentTime == 0.006 && media[1].rate == 1.5)
        media[1].onFinish?(true); try await wait { observations.last?.state == .finished }
        #expect(observations.last == .init(ticketID: replacement.id, position: 0.01, state: .finished))
        player.stopAll()
    }

    @Test func registryRejectsForgedMetadataAndMoreThanTwoArtifacts() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = SystemExplanationSpeechOutput(writer: Writer(), temporaryRoot: root)
        let first = try await output.render(request()), second = try await output.render(request()), third = try await output.render(request())
        var factories = 0, observations: [ExplanationPlaybackObservation] = []
        let player = ExplanationAudioPlayer(factory: { _ in factories += 1; return Media() })
        player.onObservation = { observations.append($0) }
        try player.register(first); try player.register(second)
        #expect(throws: ExplanationAudioError.busy) { try player.register(third) }
        var forged = first.chunk; forged.turnID = UUID()
        player.execute(.play(ticket: .init(audio: forged), audio: forged, position: 0, rate: 1))
        try await wait { observations.count == 1 }
        #expect(factories == 0)
        if case .some(.failed(_)) = observations.last?.state {} else { Issue.record("Forged identity did not fail") }
        #expect(!ExplanationFluidLegacyCandidate.isAvailable)
        player.stopAll()
    }

    @Test func nonfinitePCMIsRejectedBeforeNativePlaybackForPlanarAndInterleavedBuffers() async throws {
        for interleaved in [false, true] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let writer = Writer(); writer.immediate = false
            let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root)
            let work = Task { try await output.render(request()) }
            defer { work.cancel() }
            try await wait { !writer.callbacks.isEmpty }
            let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000,
                                                  channels: 2, interleaved: interleaved))
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240))
            pcm.frameLength = 240
            if interleaved {
                pcm.floatChannelData![0].initialize(repeating: 0, count: 480)
                pcm.floatChannelData![0][479] = .nan
            } else {
                for channel in 0..<2 { pcm.floatChannelData![channel].initialize(repeating: 0, count: 240) }
                pcm.floatChannelData![1][239] = .infinity
            }
            writer.callbacks[0](pcm)
            await #expect(throws: ExplanationAudioError.invalidPCM) { try await work.value }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    @Test func missingDisplayTicksUseActualMediaClockAfterFiftyMillisecondWatchdog() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try await SystemExplanationSpeechOutput(writer: Writer(), temporaryRoot: root).render(request())
        let media = Media()
        var now = ContinuousClock.now, observations: [ExplanationPlaybackObservation] = []
        let player = ExplanationAudioPlayer(factory: { _ in media }, monotonicNow: { now })
        defer { player.stopAll() }
        player.onObservation = { observations.append($0) }
        player.externalDisplayClockActive = true
        try player.register(prepared)
        let ticket = ExplanationPlaybackTicket(audio: prepared.chunk)
        player.execute(.play(ticket: ticket, audio: prepared.chunk, position: 0, rate: 1))
        try await wait { observations.count == 1 }
        media.currentTime = 0.002
        player.observeDisplayClock()
        try await wait { observations.last?.position == 0.002 }
        let count = observations.count
        now = now.advanced(by: .milliseconds(49)); media.currentTime = 0.006
        let priorReads = media.reads
        player.sampleFallbackClock()
        #expect(media.reads == priorReads && observations.count == count)
        now = now.advanced(by: .milliseconds(1))
        player.sampleFallbackClock()
        #expect(media.reads == priorReads + 1)
        try await wait { observations.last?.position == 0.006 }
        #expect(observations.last?.ticketID == ticket.id)
        player.execute(.pause(ticketID: ticket.id))
        try await wait { observations.last?.state == .paused }
        let pausedCount = observations.count
        let pausedReads = media.reads
        now = now.advanced(by: .seconds(1)); player.sampleFallbackClock()
        #expect(media.reads == pausedReads && observations.count == pausedCount)
    }

    @Test func shortClipCompletionCannotOvertakePlayingAndClockSamplesStayBounded() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try await SystemExplanationSpeechOutput(writer: Writer(), temporaryRoot: root).render(request())
        let media = Media()
        var observations: [ExplanationPlaybackObservation] = []
        let player = ExplanationAudioPlayer(factory: { _ in media })
        defer { player.stopAll() }
        player.onObservation = { observations.append($0) }
        try player.register(prepared)
        let ticket = ExplanationPlaybackTicket(audio: prepared.chunk)
        player.execute(.play(ticket: ticket, audio: prepared.chunk, position: 0, rate: 1))
        for index in 0..<1000 {
            media.currentTime = Double(index) / 100_000
            player.observeClock()
        }
        #expect(player.pendingObservationCount == 1)
        media.onFinish?(true) // No actor suspension between play, samples, and completion.
        #expect(player.pendingObservationCount == 2 && observations.isEmpty)
        try await wait { observations.count == 2 }
        #expect(observations.map(\.state) == [.playing, .finished])
        #expect(observations.map(\.position) == [0.00999, 0.01])
    }

    @Test func replacementPurgesQueuedOldObservationsAndControlOverflowFailsVisibly() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try await SystemExplanationSpeechOutput(writer: Writer(), temporaryRoot: root).render(request())
        var observations: [ExplanationPlaybackObservation] = []
        let player = ExplanationAudioPlayer(factory: { _ in Media() })
        defer { player.stopAll() }
        player.onObservation = { observations.append($0) }
        try player.register(prepared)
        let first = ExplanationPlaybackTicket(audio: prepared.chunk), replacement = ExplanationPlaybackTicket(audio: prepared.chunk)
        player.execute(.play(ticket: first, audio: prepared.chunk, position: 0, rate: 1))
        player.execute(.play(ticket: replacement, audio: prepared.chunk, position: 0, rate: 1))
        #expect(player.pendingObservationCount == 1)
        try await wait { observations.count == 1 }
        #expect(observations[0].ticketID == replacement.id)
        for _ in 0..<20 { player.execute(.pause(ticketID: replacement.id)) }
        #expect(player.pendingObservationCount == 1)
        try await wait { observations.count == 2 }
        if case .failed = observations[1].state {} else { Issue.record("Control overflow did not fail playback") }
    }
}
