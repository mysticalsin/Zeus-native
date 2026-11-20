import Foundation
import Testing
@testable import ZeusCore

@Suite("Song colour palette") struct MediaPaletteTests {
    @Test func anEmptyOrClearImageStaysNeutral() {
        #expect(MediaSongPalette.extract(rgba: []) == .neutral)
        #expect(MediaSongPalette.extract(rgba: [0, 0, 0, 0, 10, 20, 30, 0]) == .neutral)
        #expect(MediaSongPalette.extract(rgba: [1, 2, 3]) == .neutral)
    }

    @Test func aRedFieldTintsTheAccentRed() {
        let palette = MediaSongPalette.extract(rgba: solid(220, 24, 28))
        #expect(palette.accent.red > palette.accent.green)
        #expect(palette.accent.red > palette.accent.blue)
        #expect(palette.accent.red > 0.5)
        #expect(palette.cardLuminance < palette.accentLuminance)
    }

    @Test func aBlueFieldTintsTheAccentBlue() {
        let palette = MediaSongPalette.extract(rgba: solid(20, 40, 210))
        #expect(palette.accent.blue > palette.accent.red)
        #expect(palette.accent.blue > palette.accent.green)
    }

    @Test func nearBlackDoesNotBecomeTheAccent() {
        #expect(MediaSongPalette.extract(rgba: solid(4, 4, 5, count: 32)) == .neutral)
        #expect(MediaSongPalette.extract(rgba: solid(250, 250, 250, count: 8)) == .neutral)
    }

    @Test func twoColoursKeepASecondRole() {
        var pixels: [UInt8] = []
        pixels.append(contentsOf: solid(210, 30, 40, count: 20))
        pixels.append(contentsOf: solid(30, 50, 200, count: 20))
        let palette = MediaSongPalette.extract(rgba: pixels)
        #expect(palette.accent.red > palette.accent.blue)
        #expect(palette.support.blue > palette.support.red)
        #expect(palette.accent != palette.support)
    }

    @Test func theSamePixelsAlwaysReturnTheSamePalette() {
        let pixels = solid(180, 40, 90, count: 12) + solid(40, 160, 80, count: 7)
        #expect(MediaSongPalette.extract(rgba: pixels) == MediaSongPalette.extract(rgba: pixels))
    }

    @Test func likeFollowsTheAccentOnlyWhenAsked() {
        let palette = MediaSongPalette.extract(rgba: solid(200, 30, 40))
        #expect(palette.like(followsSong: true) == palette.accent)
        #expect(palette.like(followsSong: false) == MediaSongPalette.heart)
        #expect(palette.like(followsSong: false) != palette.accent)
    }

    @Test func theBadgeMatchesColourOnlyWhenAsked() {
        let palette = MediaSongPalette.extract(rgba: solid(30, 140, 80))
        #expect(palette.badge(matchColour: true) == palette.accent)
        #expect(palette.badge(matchColour: false) == MediaSongPalette.neutralBadge)
    }

    @Test func everyChannelStaysInsideTheUnitRange() {
        let steps: [UInt8] = [0, 32, 96, 160, 220, 255]
        for red in steps {
            for green in steps {
                for blue in steps {
                    let palette = MediaSongPalette.extract(rgba: solid(red, green, blue, count: 4))
                    #expect(palette.channelsInRange)
                    #expect(palette.like(followsSong: true).inRange)
                    #expect(palette.like(followsSong: false).inRange)
                    #expect(palette.badge(matchColour: true).inRange)
                    #expect(palette.badge(matchColour: false).inRange)
                }
            }
        }
        let mixed = MediaSongPalette.extract(rgba: solid(255, 0, 0, count: 5_000) + solid(0, 0, 255, count: 5_000))
        #expect(mixed.channelsInRange)
    }

    private func solid(_ red: UInt8, _ green: UInt8, _ blue: UInt8, count: Int = 16, alpha: UInt8 = 255) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count * 4)
        for _ in 0..<count { bytes.append(contentsOf: [red, green, blue, alpha]) }
        return bytes
    }
}

private extension MediaSongPalette {
    var accentLuminance: Double { accent.luminance }
    var cardLuminance: Double { card.luminance }
    var channelsInRange: Bool { accent.inRange && support.inRange && card.inRange && waveform.inRange }
}

private extension ArtworkColor.RGB {
    var inRange: Bool {
        [red, green, blue].allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite }
    }

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}
