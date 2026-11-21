import Foundation
import Testing
@testable import ZeusCore

@Suite("Media preview") struct MediaPreviewTests {
    @Test func thePreviewReflectsEachLook() {
        for look in MediaPlayerLook.allCases {
            var settings = MediaSettings.defaults
            settings.look = look
            let preview = make(settings)
            #expect(preview.look == look)
            #expect(preview.title == MediaPreviewSample.demo.title)
            #expect(preview.visible)
            switch look {
            case .art:
                #expect(preview.showsArt)
                #expect(!preview.glass)
                #expect(!preview.showsDetail)
            case .glassArt:
                #expect(preview.showsArt)
                #expect(preview.glass)
                #expect(!preview.showsDetail)
            case .glassCard:
                #expect(!preview.showsArt)
                #expect(preview.glass)
                #expect(!preview.showsDetail)
            case .detailed:
                #expect(preview.showsArt)
                #expect(preview.glass)
                #expect(preview.showsDetail)
                #expect(preview.album == MediaPreviewSample.demo.album)
            }
        }
        #expect(MediaPlayerLook.allCases.map(\.title) == ["Art", "Glass art", "Glass card", "Detailed"])
    }

    @Test func tintLikeBadgeAndWaveformFollowTheSettings() {
        var plain = MediaSettings.defaults
        plain.tintFromSong = false
        plain.waveform = false
        plain.explicitBadge = false
        let untinted = make(plain)
        #expect(untinted.palette == .neutral)
        #expect(untinted.waveform == nil)
        #expect(untinted.badge == nil)

        var tinted = plain
        tinted.tintFromSong = true
        tinted.likeFollowsSong = true
        tinted.explicitBadge = true
        tinted.explicitMatchesColour = true
        tinted.waveform = true
        let coloured = make(tinted)
        #expect(coloured.palette.accent.red > coloured.palette.accent.blue)
        #expect(coloured.like == coloured.palette.accent)
        #expect(coloured.badge == "Explicit")
        #expect(coloured.badgeColor == coloured.palette.accent)
        #expect(coloured.waveform?.bars.isEmpty == false)
        #expect(coloured.waveform?.animates == true)

        tinted.likeFollowsSong = false
        tinted.explicitMatchesColour = false
        let separate = make(tinted, reduceMotion: true)
        #expect(separate.like == MediaSongPalette.heart)
        #expect(separate.badgeColor == MediaSongPalette.neutralBadge)
        #expect(separate.waveform?.animates == false)
        #expect(separate.animationDuration == 0)
    }

    @Test func lyricsStayOffTheNetworkUntilTheSwitchIsOn() {
        let line = LyricLine(time: MediaPreviewSample.demo.lyricStart, text: MediaPreviewSample.demo.lyric)
        let words = LyricWordTiming.words(in: line, lineEnd: MediaPreviewSample.demo.lyricEnd)
        let off = MediaLyricPreview.highlight(
            enabled: false, wordByWord: true, phase: .ready, line: line,
            lineEnd: MediaPreviewSample.demo.lyricEnd, time: words[1].start
        )
        #expect(off == .off)
        let whole = MediaLyricPreview.highlight(
            enabled: true, wordByWord: false, phase: .ready, line: line,
            lineEnd: MediaPreviewSample.demo.lyricEnd, time: words[1].start
        )
        #expect(whole == .wholeLine(line.text))
        let word = MediaLyricPreview.highlight(
            enabled: true, wordByWord: true, phase: .ready, line: line,
            lineEnd: MediaPreviewSample.demo.lyricEnd, time: words[1].start + 0.01
        )
        #expect(word == .word(line: line.text, index: 1, count: words.count))
        #expect(MediaLyricPreview.highlight(enabled: true, wordByWord: true, phase: .loading, line: line, lineEnd: 1, time: 0) == .loading)
        #expect(MediaLyricPreview.highlight(enabled: true, wordByWord: true, phase: .empty, line: line, lineEnd: 1, time: 0) == .empty)
        let failed = MediaLyricPreview.highlight(enabled: true, wordByWord: true, phase: .unavailable, line: line, lineEnd: 1, time: 0)
        #expect(failed == .unavailable)
        #expect(MediaLyricPreview.remembersFailureAsMissing(failed) == false)
        #expect(MediaLyricPreview.remembersFailureAsMissing(.empty) == true)
    }

    @Test func theLeftButtonFollowsTheChoiceAndTheSource() {
        let full = SourceCapabilities.playPause.union(.previous).union(.lyrics)
        let previous = MediaLeftButtonRules.plan(choice: .previous, capabilities: full, lyricsOn: false)
        #expect(previous.shown && previous.enabled)
        #expect(previous.accessibilityLabel == "Previous")
        let missing = MediaLeftButtonRules.plan(choice: .previous, capabilities: .playPause, lyricsOn: true)
        #expect(!missing.shown)
        let like = MediaLeftButtonRules.plan(choice: .like, capabilities: [], lyricsOn: false)
        #expect(like.shown && like.enabled)
        #expect(like.accessibilityLabel == "Like")
        let lyricsOff = MediaLeftButtonRules.plan(choice: .lyrics, capabilities: full, lyricsOn: false)
        #expect(lyricsOff.shown && !lyricsOff.enabled)
        let lyricsOn = MediaLeftButtonRules.plan(choice: .lyrics, capabilities: full, lyricsOn: true)
        #expect(lyricsOn.shown && lyricsOn.enabled)
        let noLyrics = MediaLeftButtonRules.plan(choice: .lyrics, capabilities: .playPause, lyricsOn: true)
        #expect(!noLyrics.shown)
    }

    @Test func loadingEmptyAndErrorAreDistinct() {
        let loading = make(.defaults, phase: .loading)
        let empty = make(.defaults, phase: .empty)
        let failed = make(.defaults, phase: .failed("The player could not be read"))
        #expect(loading.statusTitle == "Loading the player")
        #expect(empty.statusTitle == "Nothing playing")
        #expect(failed.statusTitle == "The player could not be read")
        #expect(loading.accessibilityLabel.contains("Loading the player"))
        #expect(empty.accessibilityLabel.contains("Nothing playing"))
        #expect(failed.accessibilityLabel.contains("The player could not be read"))
        #expect(Set([loading.statusTitle, empty.statusTitle, failed.statusTitle]).count == 3)
    }

    @Test func hidingRemovesTheCardWithoutChangingTheLook() {
        var settings = MediaSettings.defaults
        settings.look = .detailed
        settings.hideOnPause = .instantly
        var machine = MediaHideMachine(policy: .instantly, state: .hidden)
        let hidden = make(settings, hide: machine)
        #expect(!hidden.visible)
        #expect(hidden.statusTitle == "Hidden while paused")
        #expect(hidden.look == .detailed)
        #expect(hidden.canResume)
        _ = machine.send(.beganPlaying, reduceMotion: true)
        let shown = make(settings, hide: machine)
        #expect(shown.visible)
        #expect(shown.title == MediaPreviewSample.demo.title)
    }

    @Test func solidFallbackRemovesGlass() {
        var settings = MediaSettings.defaults
        settings.look = .glassArt
        let flags = [false, true]
        for motion in flags {
            for transparency in flags {
                for contrast in flags {
                    let access = GlassSettingsAccess(reduceMotion: motion, reduceTransparency: transparency, increaseContrast: contrast)
                    let preview = MediaPreviewBuilder.make(settings: settings, phase: .ready(.demo), hide: MediaHideMachine(), access: access, lyricsPhase: .ready)
                    let solid = transparency || contrast
                    #expect(preview.solidFallback == solid)
                    #expect(preview.glass == !solid)
                    #expect(preview.animationDuration == (motion ? 0 : GlassSettingsMaterialRules.resolve(access).animationDuration))
                }
            }
        }
    }

    @Test func aSilentWaveformIsAnEmptyState() {
        let silent = MediaWaveform.make(levels: [], enabled: true, reduceMotion: false)
        #expect(silent?.isSilent == true)
        let noisy = MediaWaveform.make(levels: [-1, 0.4, .nan, 2], enabled: true, reduceMotion: false)
        #expect(noisy?.bars == [0, 0.4, 0, 1])
        #expect(noisy?.isSilent == false)
        #expect(MediaWaveform.make(levels: [1], enabled: false, reduceMotion: false) == nil)
    }

    private func make(
        _ settings: MediaSettings,
        phase: MediaPreviewPhase = .ready(.demo),
        hide: MediaHideMachine = MediaHideMachine(),
        reduceMotion: Bool = false
    ) -> MediaPreview {
        let access = GlassSettingsAccess(reduceMotion: reduceMotion, reduceTransparency: false, increaseContrast: false)
        return MediaPreviewBuilder.make(settings: settings, phase: phase, hide: hide, access: access, lyricsPhase: .ready)
    }
}
