import Foundation
import Testing
@testable import ZeusCore

/// Lock and wake chimes: one sound per physical close or open, original tones, and a file the
/// owner picked only when this Mac can read it. No audio device and no settings window.
@Suite struct ChimeTests {
    // MARK: Debounce

    @Test func oneChimePerCloseCluster() {
        var chimes = ChimeDebouncer()
        chimes.arm()
        let start = 40.0
        let commands = [
            chimes.receive(.willSleep, at: start),
            chimes.receive(.screensDidSleep, at: start + 0.04),
            chimes.receive(.sessionLocked, at: start + 0.2),
            chimes.receive(.willSleep, at: start + ChimeDebouncer.clusterWindow),
        ]
        #expect(commands == [.play(.close), .none, .none, .none])
        #expect(ChimeDebouncer.settled(commands) == .close)
    }

    @Test func oneChimePerOpenCluster() {
        var chimes = ChimeDebouncer()
        chimes.arm()
        let start = 80.0
        let commands = [
            chimes.receive(.didWake, at: start),
            chimes.receive(.screensDidWake, at: start + 0.05),
            chimes.receive(.sessionUnlocked, at: start + 0.3),
        ]
        #expect(commands == [.play(.open), .none, .none])
        #expect(ChimeDebouncer.settled(commands) == .open)
    }

    @Test func aLaterClusterPlaysAgainAndTheOppositeEventIsItsOwnChime() {
        var chimes = ChimeDebouncer()
        chimes.arm()
        let start = 10.0
        #expect(chimes.receive(.sessionLocked, at: start) == .play(.close))
        #expect(chimes.receive(.sessionUnlocked, at: start + 0.2) == .play(.open))
        let again = start + ChimeDebouncer.clusterWindow + 0.01
        #expect(chimes.receive(.willSleep, at: again) == .play(.close))
        #expect(chimes.receive(.screensDidSleep, at: again + 0.02) == .none)
    }

    // MARK: Launch

    @Test func noChimeOnLaunch() {
        var chimes = ChimeDebouncer()
        let burst: [ChimeSignal] = [.didWake, .screensDidWake, .sessionUnlocked, .willSleep, .sessionLocked]
        let beforeArm = burst.map { chimes.receive($0, at: 0.2) }
        #expect(beforeArm.allSatisfy { $0 == .none })
        chimes.arm()
        #expect(ChimeDebouncer.settled(beforeArm) == nil)
        #expect(chimes.receive(.didWake, at: 30) == .play(.open))
        #expect(chimes.receive(.screensDidWake, at: 30.1) == .none)
    }

    // MARK: Power off

    @Test func noChimeOnPowerOff() {
        var alone = ChimeDebouncer()
        alone.arm()
        let shutdown = [
            alone.receive(.willPowerOff, at: 5),
            alone.receive(.willSleep, at: 5.1),
            alone.receive(.screensDidSleep, at: 5.2),
            alone.receive(.sessionLocked, at: 5.3),
        ]
        #expect(shutdown.allSatisfy { $0 == .none })
        #expect(ChimeDebouncer.settled(shutdown) == nil)

        var cluster = ChimeDebouncer()
        cluster.arm()
        let together = [
            cluster.receive(.willSleep, at: 9),
            cluster.receive(.willPowerOff, at: 9.05),
            cluster.receive(.screensDidSleep, at: 9.1),
            cluster.receive(.didWake, at: 9.2),
        ]
        #expect(together == [.play(.close), .cancel, .none, .none])
        #expect(ChimeDebouncer.settled(together) == nil)
    }

    @Test func theCloseChimeIsRequestedOnTheFirstSleepOrLockSignal() {
        var sleep = ChimeDebouncer()
        sleep.arm()
        #expect(sleep.receive(.willSleep, at: 3) == .play(.close))

        var lock = ChimeDebouncer()
        lock.arm()
        #expect(lock.receive(.sessionLocked, at: 3) == .play(.close))
    }

    // MARK: Resolver

    @Test func resolverFallbackOrder() {
        let absent = ChimeSoundResolver.resolve(event: .close, path: nil, readable: true)
        #expect(absent.source == .synthesizedDefault)
        #expect(absent.fellBack == false)
        #expect(absent.privateLog == nil)

        let blank = ChimeSoundResolver.resolve(event: .open, path: "   ", readable: true)
        #expect(blank.source == .synthesizedDefault)
        #expect(blank.fellBack == false)

        let chosen = ChimeSoundResolver.resolve(event: .open, path: " /tmp/owned-open.wav ", readable: true)
        #expect(chosen.source == .customFile(path: "/tmp/owned-open.wav"))
        #expect(chosen.fellBack == false)
        #expect(chosen.privateLog == nil)

        let missing = ChimeSoundResolver.resolve(event: .close, path: "/tmp/missing-close.wav", readable: false)
        #expect(missing.source == .synthesizedDefault)
        #expect(missing.fellBack == true)
        #expect(missing.privateLog?.contains("/tmp/missing-close.wav") != true)
        #expect(missing.privateLog?.isEmpty == false)

        let openCustom = ChimeSoundResolver.resolve(event: .open, path: "/tmp/owned-open.wav", readable: true)
        let closeDefault = ChimeSoundResolver.resolve(event: .close, path: "/tmp/missing-close.wav", readable: false)
        #expect(openCustom.source == .customFile(path: "/tmp/owned-open.wav"))
        #expect(closeDefault.source == .synthesizedDefault)
    }

    // MARK: Tones

    @Test func openIsAShortSoftRiseAndCloseIsAShortSoftFall() {
        let open = ChimeTone.samples(for: .open)
        let close = ChimeTone.samples(for: .close)
        assertShortAndSoft(open)
        assertShortAndSoft(close)
        #expect(open != close)

        let openLow = dominantFrequency(slice(open, from: 0.15, to: 0.35), sampleRate: ChimeTone.sampleRate)
        let openHigh = dominantFrequency(slice(open, from: 0.70, to: 0.90), sampleRate: ChimeTone.sampleRate)
        #expect(openHigh > openLow * 1.15)

        let closeHigh = dominantFrequency(slice(close, from: 0.15, to: 0.35), sampleRate: ChimeTone.sampleRate)
        let closeLow = dominantFrequency(slice(close, from: 0.70, to: 0.90), sampleRate: ChimeTone.sampleRate)
        #expect(closeHigh > closeLow * 1.15)
    }

    // MARK: Settings

    @Test func settingsPersistence() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let bookmark = Data([7, 8, 9, 10])
        let saved = ChimeSettingsSnapshot(
            enabled: false,
            volume: 0.35,
            close: nil,
            open: ChimeFileReference(path: "/tmp/owned-open.aiff", bookmark: bookmark))
        ChimeSettingsPersistence.save(saved, defaults: defaults)
        #expect(ChimeSettingsPersistence.load(defaults: defaults) == saved)

        let (freshDefaults, freshName) = makeSuite()
        defer { freshDefaults.removePersistentDomain(forName: freshName) }
        let fresh = ChimeSettingsPersistence.load(defaults: freshDefaults)
        #expect(fresh.enabled == true)
        #expect(fresh.volume == ChimeSettingsSnapshot.defaultVolume)
        #expect(fresh.close == nil)
        #expect(fresh.open == nil)
    }

    @Test func importDoesNotEnableACustomPathItCannotAccess() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zeus-chime-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appendingPathComponent("open.caf")
        let original = Data([1, 2, 3, 4, 5])
        try original.write(to: owned)
        let missing = root.appendingPathComponent("missing.caf").path

        let imported = ChimeSettingsSnapshot(
            enabled: true,
            volume: 0.5,
            close: ChimeFileReference(path: missing, bookmark: Data([9, 9, 9])),
            open: ChimeFileReference(path: " \(owned.path) ", bookmark: Data([4])))
        let result = ChimeSettingsImport.applying(imported: imported) { path in
            FileManager.default.isReadableFile(atPath: path)
        }

        #expect(result.enabled == true)
        #expect(result.volume == 0.5)
        #expect(result.close == nil)
        #expect(result.open == nil)
        #expect(FileManager.default.fileExists(atPath: missing) == false)
        #expect(try Data(contentsOf: owned) == original)

        let refused = ChimeSettingsImport.applying(imported: imported) { _ in false }
        #expect(refused.close == nil)
        #expect(refused.open == nil)
        #expect(ChimeSettingsImport.storedPath(path: missing, readable: false) == "")
        #expect(ChimeSettingsImport.storedPath(path: "  ", readable: true) == "")
    }

    /// An imported settings file must not choose a chime file, even when the path exists and can be read.
    @Test func importRejectsAReadableChimePath() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zeus-chime-reject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let close = root.appendingPathComponent("close.wav")
        let open = root.appendingPathComponent("open.wav")
        try Data([1, 1, 1, 1]).write(to: close)
        try Data([2, 2, 2, 2]).write(to: open)
        let imported = ChimeSettingsSnapshot(
            enabled: false,
            volume: 0.2,
            close: ChimeFileReference(path: close.path, bookmark: Data([3])),
            open: ChimeFileReference(path: open.path, bookmark: Data([4])))
        let result = ChimeSettingsImport.applying(imported: imported) { path in
            FileManager.default.isReadableFile(atPath: path)
        }
        #expect(result.enabled == false)
        #expect(result.volume == 0.2)
        #expect(result.close == nil)
        #expect(result.open == nil)
        #expect(try Data(contentsOf: close) == Data([1, 1, 1, 1]))
        #expect(try Data(contentsOf: open) == Data([2, 2, 2, 2]))
    }

    @Test func exportLeavesChimePathsOut() {
        #expect(ChimeSettingsExport.includes(id: ChimeSettingsKey.closePath) == false)
        #expect(ChimeSettingsExport.includes(id: ChimeSettingsKey.openPath) == false)
        #expect(ChimeSettingsExport.includes(id: ChimeSettingsKey.enabled) == true)
        #expect(ChimeSettingsExport.includes(id: ChimeSettingsKey.volume) == true)
        #expect(ChimeSettingsExport.includes(id: "sound.on") == true)
    }

    @Test func aStaleBookmarkIsReplacedAndAFreshOneIsKept() {
        let fresh = Data([1, 2, 3])
        #expect(ChimeBookmark.replacement(stale: true, refreshed: fresh) == fresh)
        #expect(ChimeBookmark.replacement(stale: false, refreshed: fresh) == nil)
        #expect(ChimeBookmark.replacement(stale: true, refreshed: nil) == nil)
        #expect(ChimeBookmark.replacement(stale: true, refreshed: Data()) == nil)
    }

    @Test func decodeAllocationIsBoundedByRateChannelsAndDuration() {
        #expect(ChimeAudioLimits.frameCount(headerFrames: 44_100, sampleRate: 44_100, channels: 1) == 44_100)
        #expect(ChimeAudioLimits.frameCount(headerFrames: 10_000_000, sampleRate: 44_100, channels: 1) == 88_200)
        #expect(ChimeAudioLimits.frameCount(headerFrames: 1_000, sampleRate: 1_000_000_000, channels: 1) == nil)
        #expect(ChimeAudioLimits.frameCount(headerFrames: 1_000, sampleRate: 44_100, channels: 64) == nil)
        #expect(ChimeAudioLimits.frameCount(headerFrames: 0, sampleRate: 44_100, channels: 1) == nil)
        #expect(ChimeAudioLimits.frameCount(headerFrames: 100, sampleRate: .nan, channels: 1) == nil)
        #expect(ChimeAudioLimits.frameCount(headerFrames: 96_000, sampleRate: 96_000, channels: 2) == 96_000)
    }

    @Test func aChosenFileMustBeARegularFileOpenedWithoutFollowingALink() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zeus-chime-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tone.wav")
        let bytes = Data([9, 8, 7, 6, 5])
        try bytes.write(to: file)
        #expect(try ChimeFileAccess.readRegularFile(at: file.path).get() == bytes)
        #expect(try ChimeFileAccess.measureRegularFile(at: file.path).get() == bytes.count)

        let link = root.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(ChimeFileAccess.readRegularFile(at: link.path).isRefused)
        #expect(ChimeFileAccess.measureRegularFile(at: link.path).isRefused)
        #expect(ChimeFileAccess.readRegularFile(at: root.path).isRefused)

        let bulky = root.appendingPathComponent("bulky.wav")
        try Data(repeating: 1, count: 32).write(to: bulky)
        #expect(ChimeFileAccess.readRegularFile(at: bulky.path, maxBytes: 8) == .failure(.tooLarge))
        #expect(try Data(contentsOf: bulky).count == 32)
    }

    @Test func playbackStaysOffWhenDisabledOrFocusIsActive() {
        #expect(ChimePlaybackGate.allows(enabled: true, focusActive: false) == true)
        #expect(ChimePlaybackGate.allows(enabled: false, focusActive: false) == false)
        #expect(ChimePlaybackGate.allows(enabled: true, focusActive: true) == false)
    }

    // MARK: Helpers

    private func makeSuite() -> (UserDefaults, String) {
        let name = NSTemporaryDirectory() + "zeus.chime.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func assertShortAndSoft(_ samples: [Float]) {
        let seconds = Double(samples.count) / ChimeTone.sampleRate
        #expect(seconds > 0.25)
        #expect(seconds < ChimeTone.maximumDuration)
        #expect(samples.allSatisfy { $0.isFinite })
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.12)
        #expect(peak <= 0.45)
        #expect(abs(samples[0]) < 0.001)
        #expect(abs(samples[samples.count - 1]) < 0.001)
        let fade = Int(0.004 * ChimeTone.sampleRate)
        #expect((samples.prefix(fade).map { abs($0) }.max() ?? 1) < 0.05)
        #expect((samples.suffix(fade).map { abs($0) }.max() ?? 1) < 0.05)
    }

    private func slice(_ samples: [Float], from: Double, to: Double) -> [Float] {
        let start = min(samples.count - 1, max(0, Int(Double(samples.count) * from)))
        let end = min(samples.count, max(start + 1, Int(Double(samples.count) * to)))
        return Array(samples[start..<end])
    }

    /// Period of the strongest lag between 150 Hz and 1000 Hz.
    private func dominantFrequency(_ samples: [Float], sampleRate: Double) -> Double {
        let minLag = max(1, Int(sampleRate / 1000))
        let maxLag = min(samples.count / 2, Int(sampleRate / 150))
        var bestLag = minLag
        var best = -Float.greatestFiniteMagnitude
        guard maxLag > minLag else { return 0 }
        for lag in minLag...maxLag {
            var sum: Float = 0
            let limit = samples.count - lag
            for index in 0..<limit {
                sum += samples[index] * samples[index + lag]
            }
            if sum > best {
                best = sum
                bestLag = lag
            }
        }
        return sampleRate / Double(bestLag)
    }
}

private extension Result where Failure == ChimeFileAccess.Problem {
    var isRefused: Bool {
        if case .failure = self { return true }
        return false
    }
}
