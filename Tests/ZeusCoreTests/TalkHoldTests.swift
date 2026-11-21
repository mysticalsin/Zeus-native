import Foundation
import Testing
@testable import ZeusCore

@Suite("Control+Option talk hold")
struct TalkHoldTests {
    @Test func holdPlaysTheStartCueOnceAndReleasePlaysTheEndCueOnce() {
        var session = TalkRehearsal(fileIsReadable: { _ in true })
        session.flags(.controlOption, at: 0)
        #expect(session.preloaded)
        #expect(session.plays.isEmpty)
        session.advance(at: TalkHold.debounce)
        session.flags([], at: 0.8)
        #expect(session.plays == [
            TalkCuePlay(kind: .start, source: .file(TalkCueFiles.startPath)),
            TalkCuePlay(kind: .end, source: .file(TalkCueFiles.endPath)),
        ])
    }

    @Test func aSecondFlagsEventWhileHeldDoesNotReplayTheStartCue() {
        var session = TalkRehearsal()
        session.flags(.controlOption, at: 0)
        session.advance(at: 0.15)
        session.flags(.controlOption, at: 0.4)
        session.flags([], at: 0.9)
        #expect(session.plays.map(\.kind) == [.start, .end])
    }

    @Test func optionAloneDoesNothing() {
        var session = TalkRehearsal()
        session.flags(.option, at: 0)
        session.advance(at: 1)
        session.flags([], at: 1.2)
        #expect(session.plays.isEmpty)
        #expect(!session.preloaded)
    }

    @Test func anExtraModifierDoesNotStartTheHold() {
        var session = TalkRehearsal()
        session.flags([.control, .option, .command], at: 0)
        session.advance(at: 0.2)
        #expect(session.plays.isEmpty)
    }

    @Test func aTooShortHoldPlaysNeitherCue() {
        var session = TalkRehearsal()
        session.flags(.controlOption, at: 0)
        session.flags([], at: 0.14)
        session.advance(at: 0.15)
        #expect(session.plays.isEmpty)
        #expect(session.hold.phase == .idle)
    }

    @Test func aCancelBeforeBeginPlaysNeitherCue() {
        var session = TalkRehearsal()
        session.flags(.controlOption, at: 0)
        session.cancel()
        session.advance(at: 0.15)
        #expect(session.plays.isEmpty)
    }

    @Test func aCancelDoesNotStartAgainUntilTheChordIsReleased() {
        var session = TalkRehearsal()
        session.flags(.controlOption, at: 0)
        session.advance(at: 0.15)
        session.cancel()
        session.flags(.controlOption, at: 0.3)
        session.advance(at: 0.5)
        #expect(session.plays.map(\.kind) == [.start, .end])
        session.flags([], at: 0.6)
        session.flags(.controlOption, at: 0.7)
        session.advance(at: 0.85)
        #expect(session.plays.map(\.kind) == [.start, .end, .start])
    }

    @Test func aCancelAfterBeginPlaysTheEndCueOnce() {
        var session = TalkRehearsal()
        session.flags(.controlOption, at: 0)
        session.advance(at: 0.15)
        session.cancel()
        #expect(session.plays.map(\.kind) == [.start, .end])
        #expect(session.hold.phase == .idle)
    }

    @Test func releasingEitherModifierEndsTheHold() {
        var session = TalkRehearsal()
        session.flags(.controlOption, at: 0)
        session.advance(at: 0.15)
        session.flags(.control, at: 0.4)
        #expect(session.plays.map(\.kind) == [.start, .end])
    }

    @Test func aMissingFileFallsBackToTheNeutralSystemSound() {
        var session = TalkRehearsal(fileIsReadable: { _ in false })
        session.flags(.controlOption, at: 0)
        session.advance(at: TalkHold.debounce)
        session.flags([], at: 1)
        let fallback = TalkCueSource.system(TalkCueFiles.fallbackSystemSound)
        #expect(session.plays == [
            TalkCuePlay(kind: .start, source: fallback),
            TalkCuePlay(kind: .end, source: fallback),
        ])
    }

    @Test func reduceMotionDoesNotSilenceTheCues() {
        #expect(TalkRehearsal.playsAudio(reduceMotion: true))
        #expect(TalkRehearsal.playsAudio(reduceMotion: false))
        var session = TalkRehearsal(fileIsReadable: { _ in true })
        session.flags(.controlOption, at: 0, reduceMotion: true)
        session.advance(at: 0.15, reduceMotion: true)
        session.flags([], at: 0.4, reduceMotion: true)
        #expect(session.plays.map(\.kind) == [.start, .end])
    }

    @Test func theApprovedFilesLiveInOneRuntimeConstant() {
        #expect(TalkCueFiles.startPath == "/Applications/superwhisper.app/Contents/Resources/StartClassic.m4a")
        #expect(TalkCueFiles.endPath == "/Applications/superwhisper.app/Contents/Resources/StopClassic.m4a")
        #expect(TalkCueFiles.path(.start) == TalkCueFiles.startPath)
        #expect(TalkCueFiles.path(.end) == TalkCueFiles.endPath)
        #expect(TalkCueFiles.startPath.hasPrefix("/"))
        #expect(TalkCueFiles.endPath.hasPrefix("/"))
    }

    @Test func superwhisperAudioIsNotInTheRepoOrResources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let forbiddenNames: Set<String> = ["StartClassic.m4a", "StopClassic.m4a"]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            Issue.record("Could not walk \(root.path)")
            return
        }
        var hits: [String] = []
        while let url = walker.nextObject() as? URL {
            let path = url.path
            if path.contains("/.git/") || path.contains("/.build/") { continue }
            let name = url.lastPathComponent
            if forbiddenNames.contains(name) { hits.append(path) }
            if name.lowercased().hasSuffix(".m4a"), path.lowercased().contains("superwhisper") {
                hits.append(path)
            }
        }
        #expect(hits.isEmpty)
    }
}
