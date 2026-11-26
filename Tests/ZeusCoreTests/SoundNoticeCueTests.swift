import Foundation
import Testing
@testable import ZeusCore

@Suite("Sound notice cue")
struct SoundNoticeCueTests {
    private let moved = "Sound moved to Kitchen"
    private let refused = "Could not switch to Office"

    @Test func theCueStaysForThreeAndAHalfSeconds() {
        #expect(SoundNoticeCue.duration == 3.5)
    }

    @Test func theNotchDrawsTheSpeakerSymbol() {
        #expect(SoundNoticeCue.symbol == "speaker.wave.2.fill")
    }

    @Test func anOwnersSwitchStillShowsWhenEverydayCuesAreOff() {
        #expect(SoundNoticeCue.shows(everydayCuesOn: false))
        #expect(SoundNoticeCue.shows(everydayCuesOn: true))
        #expect(SoundNoticeCue.essential)
    }

    @Test func aDeviceNameNeverBecomesASystemBanner() {
        for line in [moved, refused, "x"] {
            #expect(SoundNoticeCue.systemNotificationAllowed(line: line) == false)
            let banner = SoundNoticeCue.banner(line: line)
            #expect(banner == nil)
            #expect(banner?.contains("Kitchen") != true)
            #expect(banner?.contains("Office") != true)
        }
    }

    @Test func thePrintedFormOmitsTheLineAndTheDeviceName() {
        for line in [moved, refused] {
            let cue = SoundNoticeCue.notice(line: line)
            let printed = String(describing: cue)
            let reflected = String(reflecting: cue)
            #expect(printed == SoundNoticeCue.recordName)
            #expect(reflected == SoundNoticeCue.recordName)
            #expect(printed.contains("Kitchen") == false)
            #expect(printed.contains("Office") == false)
            #expect(printed.contains("Sound moved") == false)
            #expect(printed.contains("Could not switch") == false)
            #expect(reflected.contains("Kitchen") == false)
            #expect(reflected.contains("Office") == false)
            #expect(printed.contains("(") == false)
        }
    }

    @Test func theNotchStillShowsTheComposedLine() {
        #expect(SoundNoticeCue.detail(line: moved) == moved)
        #expect(SoundNoticeCue.detail(line: refused) == refused)
    }

    @Test func theRecordNameIsTheCaseAndCarriesNoDash() {
        let name = SoundNoticeCue.recordName
        #expect(name == "soundNotice")
        #expect(SoundNoticeCue.symbol.contains("\u{2014}") == false)
        #expect(SoundNoticeCue.symbol.contains("\u{2013}") == false)
        #expect(name.contains("\u{2014}") == false)
        #expect(name.contains("\u{2013}") == false)
    }
}
