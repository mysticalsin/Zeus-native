import Foundation
import Testing
@testable import ZeusCore

@Suite("Idle top bar")
struct TopBarIdleBlackTests {
    @Test func idleBlackIsExactlyZero() {
        let color = TopBarIdleBlack.sRGB
        #expect(color == TopBarSRGB(red: 0, green: 0, blue: 0, alpha: 1))
        #expect(color.red == 0)
        #expect(color.green == 0)
        #expect(color.blue == 0)
        #expect(color.alpha == 1)
        let frame = TopBarIdleChrome.resolve(.init())
        #expect(frame.state == .idle)
        #expect(frame.treatment == .pitchBlack)
        #expect(frame.background == color)
        #expect(frame.allowsMaterial == false)
        #expect(frame.allowsBlur == false)
        #expect(frame.allowsVibrancy == false)
        #expect(frame.allowsGradient == false)
        #expect(frame.allowsTint == false)
        #expect(frame.allowsTranslucency == false)
        #expect(frame.allowsShadow == false)
    }

    @Test func idleShowsOnlyTheZeusCharacter() {
        let frame = TopBarIdleChrome.resolve(.init(character: .zeus))
        #expect(frame.state == .idle)
        #expect(frame.content == .characterOnly(.zeus))
    }

    @Test func idleShowsOnlyTheJarvisCharacter() {
        let frame = TopBarIdleChrome.resolve(.init(character: .jarvis))
        #expect(frame.state == .idle)
        #expect(frame.content == .characterOnly(.jarvis))
    }

    @Test func orbPersonaIsJarvisAndClassicIsZeus() {
        #expect(TopBarCharacterChoice.resolved(mascotKind: .classic) == .zeus)
        #expect(TopBarCharacterChoice.resolved(mascotKind: .orb) == .jarvis)
    }

    @Test func hoverRestoresTheExistingVisuals() {
        let idle = TopBarIdleChrome.resolve(.init())
        let hover = TopBarIdleChrome.resolve(.init(pointerOverBar: true))
        #expect(hover.state == .hover)
        #expect(hover.treatment == .existing)
        #expect(hover.background == nil)
        #expect(hover.allowsMaterial == true)
        #expect(hover.allowsBlur == true)
        #expect(hover.allowsVibrancy == true)
        #expect(hover.allowsGradient == true)
        #expect(hover.allowsTint == true)
        #expect(hover.allowsTranslucency == true)
        #expect(hover.allowsShadow == true)
        #expect(hover.content == .existing(attention: []))
        #expect(hover.content != idle.content)
        #expect(hover.transition == .existingOpenClose(reduceMotion: false))
    }

    @Test func approvalRecordingAndMusicStayVisible() {
        let frame = TopBarIdleChrome.resolve(.init(approval: true, recording: true, music: true))
        #expect(frame.state == .active)
        #expect(frame.treatment == .existing)
        #expect(frame.content == .existing(attention: [.approval, .recording, .music]))
    }

    @Test func expandedPeekAndCalibrationKeepTheExistingBody() {
        let expanded = TopBarIdleChrome.resolve(.init(pointerOverBar: true, expanded: true))
        #expect(expanded.state == .active)
        #expect(expanded.treatment == .existing)
        #expect(expanded.background == nil)
        let peek = TopBarIdleChrome.resolve(.init(pointerOverBar: true, peek: true))
        #expect(peek.state == .active)
        #expect(peek.treatment == .existing)
        let calibrating = TopBarIdleChrome.resolve(.init(calibrating: true))
        #expect(calibrating.state == .active)
        #expect(calibrating.treatment == .existing)
        #expect(calibrating.content == .existing(attention: []))
    }

    @Test func reduceMotionUsesTheSameTransition() {
        let idle = TopBarIdleChrome.resolve(.init(reduceMotion: true))
        let hover = TopBarIdleChrome.resolve(.init(pointerOverBar: true, reduceMotion: true))
        #expect(idle.transition == .existingOpenClose(reduceMotion: true))
        #expect(hover.transition == .existingOpenClose(reduceMotion: true))
        #expect(idle.state == .idle)
        #expect(hover.state == .hover)
    }

    @Test func eachLiveAttentionMarkStays() {
        let cases: [(TopBarChromeFacts, TopBarChromeMark)] = [
            (.init(approval: true), .approval),
            (.init(recording: true), .recording),
            (.init(music: true), .music),
            (.init(dictation: true), .dictation),
            (.init(cue: true), .cue),
            (.init(focusTimer: true), .focusTimer),
            (.init(recordingFeedback: true), .recordingFeedback),
            (.init(alerts: true), .alerts),
            (.init(lights: true), .lights),
            (.init(avatarActivity: true), .avatarActivity),
        ]
        for (facts, mark) in cases {
            let frame = TopBarIdleChrome.resolve(facts)
            #expect(frame.state == .active)
            #expect(frame.treatment == .existing)
            #expect(frame.content == .existing(attention: [mark]))
        }
    }
}
