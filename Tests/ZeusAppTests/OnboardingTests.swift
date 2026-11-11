import AVFoundation
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The welcome guide: step order, the films each step plays, the choreographed transition, the living
/// mascot's pose per step and the earcons. Films are read from the source tree (the test bundle does
/// not carry the app's resources).
@Suite("Welcome guide")
@MainActor
struct OnboardingTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Zeus")
    private static func filmURL(_ film: OnboardingFilm) -> URL {
        sources.appendingPathComponent("Onboarding/Media/Films/\(film.rawValue).mp4")
    }

    // MARK: Steps and films

    @Test func stepOrderIsTheNineStepFlow() {
        #expect(OnboardingStep.allCases == [.welcome, .murmure, .agents, .control, .reach, .day, .theme, .halo, .languages, .sounds])
        #expect((7...10).contains(OnboardingStep.allCases.count))
        #expect(OnboardingStep.allCases.map(\.rawValue) == Array(0..<OnboardingStep.allCases.count))
    }

    @Test func eachStepPlaysItsFilms() {
        #expect(OnboardingStep.welcome.films == [.intro])
        #expect(OnboardingStep.murmure.films == [.murmure])
        #expect(OnboardingStep.agents.films == [.running])
        #expect(OnboardingStep.control.films == [.approve, .previews])
        #expect(OnboardingStep.reach.films == [.shortcuts, .everywhere])
        for step in [OnboardingStep.day, .theme, .halo, .languages, .sounds] { #expect(step.films.isEmpty) }
    }

    @Test func everyFilmBelongsToExactlyOneStep() {
        let used = OnboardingStep.allCases.flatMap(\.films)
        #expect(Set(used) == Set(OnboardingFilm.allCases))
        #expect(used.count == OnboardingFilm.allCases.count)
    }

    @Test func filmsShipWithTheirDurationInRange() async throws {
        let expected: [OnboardingFilm: ClosedRange<Double>] = [
            .intro: 18...22, .murmure: 24...26, .running: 6.5...7.5, .approve: 4...6,
            .previews: 9...11, .shortcuts: 6...8, .everywhere: 8...9,
        ]
        #expect(Set(expected.keys) == Set(OnboardingFilm.allCases))
        for film in OnboardingFilm.allCases {
            let url = Self.filmURL(film)
            let bytes = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, "\(film.rawValue) is missing")
            #expect(bytes < 4_200_000, "\(film.rawValue) is \(bytes) bytes")
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            #expect(expected[film]?.contains(seconds) == true, "\(film.rawValue) runs \(seconds) s")
            #expect(abs(seconds - film.duration) < 0.2, "\(film.rawValue) runs \(seconds) s, expected \(film.duration)")
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let size = try await track.load(.naturalSize)
            #expect(size == film.size, "\(film.rawValue) is \(size)")
            let rate = try await track.load(.nominalFrameRate)
            #expect(abs(Double(rate) - film.fps) < 0.5)
        }
    }

    @Test func filmURLsPointAtTheBundledFolder() {
        for film in OnboardingFilm.allCases {
            #expect(film.url?.lastPathComponent == "\(film.rawValue).mp4" || film.url == nil)
        }
        #expect(Set(OnboardingFilm.allCases.map(\.rawValue)).count == OnboardingFilm.allCases.count)
    }

    // MARK: Transition

    @Test func choreographedMoveTakesAboutHalfASecond() {
        #expect((0.45...0.6).contains(OnboardingTransition.duration))
        #expect((0.45...0.6).contains(OnboardingTransition.sweepDuration))
        #expect(OnboardingTransition.style(reduceMotion: false) == .choreographed)
        #expect(OnboardingTransition.usesSweep(reduceMotion: false))
        #expect(OnboardingTransition.sweepAnimation(reduceMotion: false) != nil)
        #expect(OnboardingTransition.animation(reduceMotion: false) != OnboardingTransition.animation(reduceMotion: true))
    }

    @Test func reduceMotionFallsBackToACrossfade() {
        #expect(OnboardingTransition.style(reduceMotion: true) == .crossfade)
        #expect(!OnboardingTransition.usesSweep(reduceMotion: true))
        #expect(OnboardingTransition.sweepAnimation(reduceMotion: true) == nil)
        #expect(OnboardingTransition.animation(reduceMotion: true) == .linear(duration: OnboardingTransition.crossfadeDuration))
        #expect(OnboardingTransition.crossfadeDuration < 0.2)
        #expect(OnboardingTransition.watermarkShift(step: 5, reduceMotion: true) == 0)
    }

    @Test func watermarkDriftsAgainstTheDirectionOfTravel() {
        #expect(OnboardingTransition.watermarkShift(step: 0, reduceMotion: false) == 0)
        let shifts = OnboardingStep.allCases.map { OnboardingTransition.watermarkShift(step: $0.rawValue, reduceMotion: false) }
        #expect(zip(shifts, shifts.dropFirst()).allSatisfy { $0 > $1 })
        #expect(abs(shifts.last ?? 0) < 160) // subtle
    }

    @Test func sweepBandIsDarkAtRestAndLitMidway() {
        #expect(SweepBand(progress: 0, direction: 1).animatableData == 0)
        var band = SweepBand(progress: 0.2, direction: 1)
        band.animatableData = 0.7
        #expect(band.progress == 0.7)
    }

    @Test func goingForwardPlaysTheAdvanceCueOnceAndBackPlaysNone() async throws {
        TopBarStyle.isSnapshot = true // keep the saved step out of the user's defaults
        defer { TopBarStyle.isSnapshot = false }
        let flow = OnboardingFlow()
        flow.step = .welcome
        var cues: [OnboardingSound] = []
        flow.playSound = { cues.append($0) }
        flow.next()
        #expect(cues == [.advance])
        #expect(flow.direction == 1)
        try await Task.sleep(for: .milliseconds(80))
        #expect(flow.step == .murmure)
        flow.back()
        #expect(cues == [.advance])
        #expect(flow.direction == -1)
        try await Task.sleep(for: .milliseconds(80))
        #expect(flow.step == .welcome)
        flow.go(.welcome) // no move, no cue
        #expect(cues == [.advance])
        flow.finish()
        #expect(cues == [.advance, .finish])
    }

    @Test func theLastStepHasNothingToAdvanceTo() {
        TopBarStyle.isSnapshot = true
        defer { TopBarStyle.isSnapshot = false }
        let flow = OnboardingFlow()
        flow.step = .sounds
        var cues: [OnboardingSound] = []
        flow.playSound = { cues.append($0) }
        flow.next()
        #expect(cues.isEmpty)
        #expect(flow.step == .sounds)
    }

    // MARK: Mascot

    @Test func mascotPosePerStep() {
        #expect(OnboardingStep.welcome.mascotPose() == .welcome)
        #expect(OnboardingStep.welcome.mascotPose(wake: .asleep) == .sleepingClean)
        #expect(OnboardingStep.welcome.mascotPose(wake: .waking) == .waking)
        #expect(OnboardingStep.murmure.mascotPose() == .listening)
        #expect(OnboardingStep.agents.mascotPose() == .working)
        #expect(OnboardingStep.sounds.mascotPose() == .celebrate)
        // The wake-up only applies to the welcome step.
        for step in OnboardingStep.allCases where step != .welcome {
            #expect(step.mascotPose(wake: .asleep) == step.mascotPose())
        }
    }

    @Test func wakeRunsAsleepThenWakingThenAwake() {
        #expect(OnboardingStep.Wake.asleep < .waking && OnboardingStep.Wake.waking < .awake)
    }

    @Test func everyStepPoseHasASpriteClip() {
        let store = MascotAtlasStore(directory: Self.sources.appendingPathComponent("Avatar/Anim"))
        for step in OnboardingStep.allCases {
            for wake in [OnboardingStep.Wake.asleep, .waking, .awake] {
                let pose = step.mascotPose(wake: wake)
                #expect(store.clip(pose.clipID) != nil, "\(pose.rawValue) has no clip")
            }
        }
    }

    @Test func brandMarkSharesHeadingLeadingEdge() {
        #expect(OB.leadingEdge == OB.contentX)
        #expect(OB.leadingEdge == OnboardingChromeLayout.leadingEdge)
    }

    @Test func mascotRestsBigOnWelcomeAndTheLastStepAndSmallElsewhere() {
        for step in OnboardingStep.allCases {
            let slot = OnboardingLayout.mascotSlot(for: step)
            #expect(slot.isHero == (step == .welcome || step == .sounds))
            #expect(slot.isHero == (slot.side > 100))
            #expect(slot.center.x > 0 && slot.center.x < OB.size.width && slot.center.y < OB.footerButtonTop)
        }
        #expect(OnboardingStep.welcome.mascotIsHero)
    }

    @Test func theOldStillPosesAreGone() throws {
        let folder = Self.sources.appendingPathComponent("Onboarding/Media/Mascot")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: Sound

    @Test func earcons() {
        #expect(OnboardingSound.advance.slot == .todo)
        #expect(OnboardingSound.finish.slot == .done)
        for cue in OnboardingSound.allCases {
            #expect(ZeusSound.url(slot: cue.slot, style: cue == .finish ? "Success" : nil) != nil || ZeusResources.bundle == nil)
        }
        #expect(OnboardingSound.enabled == (ExtraPreferences.shared.soundsOn && !MeetingState.active))
    }
}
