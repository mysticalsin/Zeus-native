import Foundation
import Testing
@testable import ZeusCore

private let optIn1 = Date(timeIntervalSince1970: 1_000)
private let optIn2 = Date(timeIntervalSince1970: 2_000)

@Suite("Scribe automatic start opt-in")
struct ScribeAutoStartOptInTests {
    private func fresh() throws -> (UserDefaults, () -> Void) {
        // A suite name that contains a slash is not private when these tests run together, and
        // removePersistentDomain synchronizes every domain in the process. A bundle id keeps
        // this test's keys to itself; cleanup removes those keys and does not synchronize.
        let name = "app.zeus.tests.ScribeAutoStartOptIn.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let keys = [
            ScribeAutoStartOptIn.key, ScribeAutoStartOptIn.legacyKey, ScribeAutoStartOptIn.firstRecordingKey,
            FeatureSettings.key(ScribeAutoStartMode.settingID),
        ]
        return (defaults, { for key in keys { defaults.removeObject(forKey: key) } })
    }

    // MARK: The stamp follows the choice

    @Test func choosingStartAutomaticallyWritesTheStampAtTheClick() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == nil)
        ScribeAutoStartOptIn.record(mode: .automatic, now: optIn1, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == optIn1)
        #expect(defaults.object(forKey: "scribe.autoStart.optInAt") is Double)
    }

    @Test func choosingAnotherModeWithdrawsTheOptIn() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        for other in [ScribeAutoStartMode.ask, .off] {
            ScribeAutoStartOptIn.record(mode: .automatic, now: optIn1, defaults: defaults)
            #expect(ScribeAutoStartOptIn.date(defaults: defaults) != nil)
            ScribeAutoStartOptIn.record(mode: other, now: optIn2, defaults: defaults)
            #expect(ScribeAutoStartOptIn.date(defaults: defaults) == nil, "\(other)")
        }
    }

    @Test func choosingAutomaticAgainAfterWithdrawingIsAFreshOptIn() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        ScribeAutoStartOptIn.record(mode: .automatic, now: optIn1, defaults: defaults)
        ScribeAutoStartOptIn.record(mode: .ask, now: optIn1, defaults: defaults)
        ScribeAutoStartOptIn.record(mode: .automatic, now: optIn2, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == optIn2)
    }

    @Test func reconcileRemovesAStampFoundWhileTheModeIsNotAutomatic() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        for other in [ScribeAutoStartMode.ask, .off] {
            defaults.set(optIn1.timeIntervalSince1970, forKey: ScribeAutoStartOptIn.key)
            ScribeAutoStartOptIn.reconcile(mode: other, defaults: defaults)
            #expect(ScribeAutoStartOptIn.date(defaults: defaults) == nil, "\(other)")
        }
        ScribeAutoStartOptIn.record(mode: .automatic, now: optIn1, defaults: defaults)
        ScribeAutoStartOptIn.reconcile(mode: .automatic, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == optIn1)
    }

    // MARK: Launch migration

    @Test func aStaleStampWithAskMeIsRemovedAtLaunch() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        defaults.set(optIn1.timeIntervalSince1970, forKey: ScribeAutoStartOptIn.key)
        ScribeAutoStartOptIn.migrate(mode: .ask, hasSavedMeetings: false, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == nil)
    }

    /// The same steps as `aStaleStampWithAskMeIsRemovedAtLaunch`, on many suites at once.
    /// A shared defaults domain lets one task's stamp survive another's removal.
    @Test func parallelFreshSuitesDoNotKeepAStaleStamp() async {
        let missed = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<48 {
                group.addTask {
                    guard let (defaults, cleanup) = try? fresh() else { return false }
                    defer { cleanup() }
                    defaults.set(optIn1.timeIntervalSince1970, forKey: ScribeAutoStartOptIn.key)
                    ScribeAutoStartOptIn.migrate(mode: .ask, hasSavedMeetings: false, defaults: defaults)
                    return ScribeAutoStartOptIn.date(defaults: defaults) == nil
                }
            }
            var failures = 0
            for await removed in group where !removed { failures += 1 }
            return failures
        }
        #expect(missed == 0)
    }

    @Test func anOldStampWithAutomaticCarriesOver() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        defaults.set(5_000.0, forKey: ScribeAutoStartOptIn.legacyKey)
        ScribeAutoStartOptIn.migrate(mode: .automatic, hasSavedMeetings: false, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == Date(timeIntervalSince1970: 5_000))
        #expect(defaults.object(forKey: ScribeAutoStartOptIn.legacyKey) == nil)
    }

    @Test func anOldStampWithAnyOtherChoiceIsDroppedNotCarried() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        for other in [ScribeAutoStartMode.ask, .off] {
            defaults.set(5_000.0, forKey: ScribeAutoStartOptIn.legacyKey)
            ScribeAutoStartOptIn.migrate(mode: other, hasSavedMeetings: false, defaults: defaults)
            #expect(ScribeAutoStartOptIn.date(defaults: defaults) == nil, "\(other)")
            #expect(defaults.object(forKey: ScribeAutoStartOptIn.legacyKey) == nil, "\(other)")
        }
    }

    @Test func anOldStampThatIsNotATimestampIsNeverCarried() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        defaults.set("yes", forKey: ScribeAutoStartOptIn.legacyKey)
        ScribeAutoStartOptIn.migrate(mode: .automatic, hasSavedMeetings: false, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == nil)
        #expect(defaults.object(forKey: ScribeAutoStartOptIn.legacyKey) == nil)
    }

    @Test func migrationNeverReplacesAnOptInThatIsAlreadyThere() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        ScribeAutoStartOptIn.record(mode: .automatic, now: optIn2, defaults: defaults)
        defaults.set(5_000.0, forKey: ScribeAutoStartOptIn.legacyKey)
        ScribeAutoStartOptIn.migrate(mode: .automatic, hasSavedMeetings: false, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == optIn2)
    }

    @Test func migrationRunsTwiceWithTheSameResult() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        defaults.set(5_000.0, forKey: ScribeAutoStartOptIn.legacyKey)
        ScribeAutoStartOptIn.migrate(mode: .automatic, hasSavedMeetings: true, defaults: defaults)
        ScribeAutoStartOptIn.migrate(mode: .automatic, hasSavedMeetings: true, defaults: defaults)
        #expect(ScribeAutoStartOptIn.date(defaults: defaults) == Date(timeIntervalSince1970: 5_000))
        #expect(ScribeAutoStartOptIn.hasRecorded(defaults: defaults))
    }

    @Test func aMacThatAlreadyHoldsASavedMeetingHasRecorded() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        ScribeAutoStartOptIn.migrate(mode: .ask, hasSavedMeetings: false, defaults: defaults)
        #expect(!ScribeAutoStartOptIn.hasRecorded(defaults: defaults))
        ScribeAutoStartOptIn.migrate(mode: .ask, hasSavedMeetings: true, defaults: defaults)
        #expect(ScribeAutoStartOptIn.hasRecorded(defaults: defaults))
    }

    // MARK: The first recording

    @Test func theFirstRecordingIsNotedOnceAndKeepsItsFirstTime() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        #expect(!ScribeAutoStartOptIn.hasRecorded(defaults: defaults))
        ScribeAutoStartOptIn.noteRecordingBegan(now: optIn1, defaults: defaults)
        #expect(ScribeAutoStartOptIn.hasRecorded(defaults: defaults))
        ScribeAutoStartOptIn.noteRecordingBegan(now: optIn2, defaults: defaults)
        #expect(defaults.object(forKey: ScribeAutoStartOptIn.firstRecordingKey) as? Double == optIn1.timeIntervalSince1970)
    }

    @Test func theStampKeysAreTheOnesThePlanNames() {
        #expect(ScribeAutoStartOptIn.key == "scribe.autoStart.optInAt")
        #expect(ScribeAutoStartOptIn.legacyKey == "scribe.autoStart.consentAt")
        #expect(ScribeAutoStartOptIn.firstRecordingKey == "scribe.firstRecordingAt")
    }

    // MARK: Readiness

    @Test func aDefaultsWriteOfAutomaticWithoutTheClickIsNotReady() throws {
        let (defaults, cleanup) = try fresh(); defer { cleanup() }
        defaults.set("Start automatically", forKey: FeatureSettings.key(ScribeAutoStartMode.settingID))
        ScribeAutoStartOptIn.noteRecordingBegan(now: optIn1, defaults: defaults)
        let mode = ScribeAutoStartMode.current(defaults: defaults)
        #expect(mode == .automatic)
        let readiness = ScribeAutoStartReadiness.resolve(
            mode: mode, optIn: ScribeAutoStartOptIn.date(defaults: defaults) != nil,
            microphone: .allowed, hasRecorded: ScribeAutoStartOptIn.hasRecorded(defaults: defaults))
        #expect(readiness == .blocked(.noOptIn))
    }

    @Test func readinessChecksInTheOrderTheRowShowsThem() {
        typealias Readiness = ScribeAutoStartReadiness
        // Not automatic: nothing else matters.
        for mode in [ScribeAutoStartMode.off, .ask] {
            #expect(Readiness.resolve(mode: mode, optIn: true, microphone: .allowed, hasRecorded: true) == .blocked(.notChosen))
            #expect(Readiness.resolve(mode: mode, optIn: false, microphone: .denied, hasRecorded: false) == .blocked(.notChosen))
        }
        // No opt-in comes before the microphone and the first recording.
        #expect(Readiness.resolve(mode: .automatic, optIn: false, microphone: .denied, hasRecorded: false) == .blocked(.noOptIn))
        // A denied microphone comes before one never asked, and both before the first recording.
        #expect(Readiness.resolve(mode: .automatic, optIn: true, microphone: .denied, hasRecorded: false) == .blocked(.microphoneDenied))
        #expect(Readiness.resolve(mode: .automatic, optIn: true, microphone: .notAsked, hasRecorded: false) == .blocked(.microphoneNotAsked))
        #expect(Readiness.resolve(mode: .automatic, optIn: true, microphone: .allowed, hasRecorded: false) == .blocked(.firstRecordingOwed))
        #expect(Readiness.resolve(mode: .automatic, optIn: true, microphone: .allowed, hasRecorded: true) == .ready)
    }

    @Test func everyCombinationResolvesToTheFirstMissingThing() {
        for mode in ScribeAutoStartMode.allCases {
            for optIn in [false, true] {
                for microphone in [ScribeMicrophoneAccess.allowed, .notAsked, .denied] {
                    for hasRecorded in [false, true] {
                        let expected: ScribeAutoStartReadiness
                        if mode != .automatic { expected = .blocked(.notChosen) }
                        else if !optIn { expected = .blocked(.noOptIn) }
                        else if microphone == .denied { expected = .blocked(.microphoneDenied) }
                        else if microphone == .notAsked { expected = .blocked(.microphoneNotAsked) }
                        else if !hasRecorded { expected = .blocked(.firstRecordingOwed) }
                        else { expected = .ready }
                        let actual = ScribeAutoStartReadiness.resolve(
                            mode: mode, optIn: optIn, microphone: microphone, hasRecorded: hasRecorded)
                        #expect(actual == expected, "\(mode) \(optIn) \(microphone) \(hasRecorded)")
                        #expect(actual.isReady == (expected == .ready))
                    }
                }
            }
        }
    }

    @Test func aBlockedReadinessNamesItsBlock() {
        #expect(ScribeAutoStartReadiness.ready.block == nil)
        #expect(ScribeAutoStartReadiness.blocked(.noOptIn).block == .noOptIn)
    }

    @Test func restrictedMicrophoneCountsAsDenied() {
        // AVAuthorizationStatus: 0 not determined, 1 restricted, 2 denied, 3 authorized.
        #expect(ScribeMicrophoneAccess(authorizationRaw: 0) == .notAsked)
        #expect(ScribeMicrophoneAccess(authorizationRaw: 1) == .denied)
        #expect(ScribeMicrophoneAccess(authorizationRaw: 2) == .denied)
        #expect(ScribeMicrophoneAccess(authorizationRaw: 3) == .allowed)
        #expect(ScribeMicrophoneAccess(authorizationRaw: 99) == .denied)
    }
}
