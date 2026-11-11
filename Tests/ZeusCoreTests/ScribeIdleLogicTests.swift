import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe idle and live page logic")
struct ScribeIdleLogicTests {
    private let now = Date(timeIntervalSince1970: 1_794_398_400)

    private func meeting(_ id: String, startsIn seconds: TimeInterval, lasts: TimeInterval? = 1_800,
                         link: String? = nil) -> ScribeUpNextMeeting {
        let start = now.addingTimeInterval(seconds)
        let slot = ScribeCalendarSlot(id: id, title: id, start: start, end: lasts.map { start.addingTimeInterval($0) })
        return ScribeUpNextMeeting(slot: slot, app: ScribeUpNext.callApp(link: link.flatMap { URL(string: $0) }))
    }

    private func segment(_ speaker: ScribeSpeaker, _ text: String, _ start: TimeInterval = 0) -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(id: "\(start)-\(text)", session: ScribeSessionID(), speaker: speaker,
                                start: start, end: start + 1, text: text, isFinal: true)
    }

    // MARK: Up next

    @Test func startsInReadsLikeAPerson() {
        func text(_ seconds: TimeInterval) -> String { ScribeUpNext.startsIn(now.addingTimeInterval(seconds), now: now) }
        #expect(text(30) == "starting now")
        #expect(text(-30) == "starting now")
        #expect(text(4 * 60) == "in 4 min")
        #expect(text(4 * 60 + 5) == "in 5 min")
        #expect(text(59 * 60) == "in 59 min")
        #expect(text(3_600) == "in 1 h")
        #expect(text(75 * 60) == "in 1 h 15 min")
        #expect(text(-3 * 60) == "started 3 min ago")
        #expect(text(-90 * 60) == "started 1 h ago")
    }

    @Test func pickTakesTheEarliestMeetingThatHasNotEnded() {
        let over = meeting("over", startsIn: -3_600, lasts: 1_800)
        let running = meeting("running", startsIn: -600, lasts: 1_800)
        let later = meeting("later", startsIn: 3_600)
        let soon = meeting("soon", startsIn: 600)
        #expect(ScribeUpNext.pick([later, over, soon, running], now: now)?.slot.id == "running")
        #expect(ScribeUpNext.pick([later, over, soon], now: now)?.slot.id == "soon")
        #expect(ScribeUpNext.pick([over], now: now) == nil)
        #expect(ScribeUpNext.pick([], now: now) == nil)
    }

    @Test func aMeetingWithoutAnEndStaysForAShortGrace() {
        let fresh = meeting("fresh", startsIn: -300, lasts: nil)
        let stale = meeting("stale", startsIn: -1_200, lasts: nil)
        #expect(ScribeUpNext.pick([fresh], now: now) != nil)
        #expect(ScribeUpNext.pick([stale], now: now) == nil)
    }

    @Test func equalStartsBreakTiesById() {
        let b = meeting("b", startsIn: 600)
        let a = meeting("a", startsIn: 600)
        #expect(ScribeUpNext.pick([b, a], now: now)?.slot.id == "a")
    }

    @Test func callAppComesFromTheLinkHost() {
        #expect(ScribeUpNext.callApp(link: URL(string: "https://teams.microsoft.com/l/meetup-join/abc")) == .teams)
        #expect(ScribeUpNext.callApp(link: URL(string: "https://acme.zoom.us/j/123")) == .zoom)
        #expect(ScribeUpNext.callApp(link: URL(string: "https://meet.google.com/abc-defg")) == .meet)
        #expect(ScribeUpNext.callApp(link: URL(string: "https://whereby.com/room")) == .other("whereby.com"))
        #expect(ScribeUpNext.callApp(link: nil) == nil)
        #expect(ScribeUpNext.appName(.teams) == "Teams")
        #expect(ScribeUpNext.appName(.zoom) == "Zoom")
        #expect(ScribeUpNext.appName(nil) == nil)
    }

    // MARK: Source chips

    @Test func chipsReportEachSourceHonestly() {
        let ready = ScribeSourceChips.chips(microphone: .authorized, captureAvailable: true, namesTrusted: true)
        #expect(ready.map(\.kind) == [.microphone, .callAudio, .names])
        #expect(ready.allSatisfy { $0.status == .on })

        let denied = ScribeSourceChips.chips(microphone: .denied, captureAvailable: true, namesTrusted: false)
        #expect(denied[0].status == .needsPermission)
        #expect(denied[1].status == .on)
        #expect(denied[2].status == .needsPermission)

        let unavailable = ScribeSourceChips.chips(microphone: .notDetermined, captureAvailable: false, namesTrusted: true)
        #expect(unavailable[0].status == .on)
        #expect(unavailable[1].status == .off)
    }

    @Test func microphoneStateFollowsTheAuthorizationRawValue() {
        #expect(CapturePermissions.microphoneState(authorizationRaw: 3) == .authorized)
        #expect(CapturePermissions.microphoneState(authorizationRaw: 0) == .notDetermined)
        #expect(CapturePermissions.microphoneState(authorizationRaw: 2) == .denied)
        #expect(CapturePermissions.microphoneState(authorizationRaw: 1) == .denied)
    }

    @Test func chipTextIsPlainWords() {
        #expect(ScribeSourceKind.allCases.map(\.title) == ["Microphone", "Call audio", "Names"])
        #expect([ScribeSourceStatus.on, .off, .needsPermission].map(\.label) == ["On", "Off", "Needs permission"])
        let chips = ScribeSourceChips.chips(microphone: .denied, captureAvailable: false, namesTrusted: false)
        for chip in chips { #expect(!chip.detail.contains("\u{2014}")) }
    }

    // MARK: Now speaking

    @Test func aKnownNameIsShownAndNeverASpeakerNumber() {
        let named = ScribeNowSpeaking.resolve(.participant("Marie Dubois"))
        #expect(named.name == "Marie Dubois")
        #expect(named.initials == "MD")
        #expect(!named.isNaming)
        #expect(named.spoken == "Marie Dubois is speaking")
        #expect(ScribeNowSpeaking.resolve(.you).name == "You")
    }

    @Test func placeholdersShowNamingNotSpeakerNumbers() {
        for speaker: ScribeSpeaker in [.unknown, .participant("Speaker"), .participant("Speaker 3"), .participant(" ")] {
            let resolved = ScribeNowSpeaking.resolve(speaker)
            #expect(resolved.isNaming)
            #expect(resolved.name == "Naming\u{2026}")
            #expect(resolved.initials == "\u{2026}")
        }
        #expect(!ScribeNowSpeaking.isPlaceholder(.participant("Speaker Lee")))
        #expect(!ScribeNowSpeaking.isPlaceholder(.participant("Marie")))
    }

    @Test func currentSpeakerIsTheNewestLineWithRealWords() {
        let segments = [
            segment(.participant("Marie Dubois"), "Hello there", 0),
            segment(.you, "Hi", 2),
            segment(.participant("Speaker 2"), "\u{2026}", 4),
        ]
        #expect(ScribeNowSpeaking.current(in: segments)?.name == "You")
        #expect(ScribeNowSpeaking.current(in: []) == nil)
        #expect(ScribeNowSpeaking.current(in: [segment(.you, "  ")]) == nil)
    }

    // MARK: Breathing wave

    @Test func waveStaysInRangeAndMovesSlowly() {
        for index in 0..<32 {
            for step in 0..<60 {
                let value = ScribeBreathingWave.level(index: index, count: 32, t: Double(step) * 0.25)
                #expect(value >= 0 && value <= 1)
            }
        }
        // The middle is taller than the edge, and a breath later it is back.
        let middle = ScribeBreathingWave.level(index: 16, count: 33, t: 1.5)
        let edge = ScribeBreathingWave.level(index: 0, count: 33, t: 1.5)
        #expect(middle > edge)
        let a = ScribeBreathingWave.level(index: 10, count: 33, t: 0)
        let b = ScribeBreathingWave.level(index: 10, count: 33, t: 0.1)
        #expect(abs(a - b) < 0.05)
    }

    @Test func waveHandlesBadInput() {
        #expect(ScribeBreathingWave.level(index: 0, count: 1, t: 0) == 0.15)
        #expect(ScribeBreathingWave.level(index: 5, count: 3, t: 0) == 0.15)
        #expect(ScribeBreathingWave.level(index: 1, count: 3, t: .nan) == 0.15)
    }
}
