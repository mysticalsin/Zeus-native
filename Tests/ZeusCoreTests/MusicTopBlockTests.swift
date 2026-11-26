import Testing
@testable import ZeusCore

@Suite("Music page top block") struct MusicTopBlockTests {
    @Test(arguments: MusicTopBlock.allCases, MusicTopBlock.allCases)
    func pressed(from current: MusicTopBlock, to request: MusicTopBlock) {
        let next = current.pressed(request)
        if request == current {
            #expect(next == .track)
        } else {
            #expect(next == request)
        }
    }

    @Test func pressingTheShownBlockReturnsToTheTrack() {
        #expect(MusicTopBlock.track.pressed(.track) == .track)
        #expect(MusicTopBlock.lyrics.pressed(.lyrics) == .track)
    }

    @Test func pressingAnotherBlockShowsThatBlock() {
        #expect(MusicTopBlock.track.pressed(.lyrics) == .lyrics)
        #expect(MusicTopBlock.lyrics.pressed(.track) == .track)
    }

    @Test func theTwoBlocksAreTrackAndLyrics() {
        #expect(MusicTopBlock.allCases == [.track, .lyrics])
    }
}
