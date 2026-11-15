import Foundation
import Testing
@testable import ZeusCore

private func hasNoDash(_ text: String) -> Bool {
    !text.contains("\u{2014}") && !text.contains("\u{2013}")
}

private func process(
    _ bundleID: String?,
    pid: Int32,
    object: UInt32? = nil,
    output: Bool = true,
    input: Bool? = false,
    devices: [String] = ["speakers"]
) -> AudioProcessFacts {
    AudioProcessFacts(
        objectID: object ?? UInt32(pid) + 1000,
        pid: pid,
        bundleID: bundleID,
        runningOutput: output,
        runningInput: input,
        devices: devices)
}

private func shapedBook(_ ids: [String], gains: [Double]? = nil, volume: Double = 1, shapes: Bool = true) -> AppSoundBook {
    var book = AppSoundBook()
    for id in ids {
        book.add(
            AppSoundSettings(
                bundleID: id, displayName: id,
                gainsDB: gains ?? [6, 0, 0, 0, 0, 0, 0, 0, 0, 0], volume: volume, shapes: shapes))
    }
    return book
}

// MARK: - Grouping

@Suite struct EqualiserGroupingTests {
    private let ownPID: Int32 = 1

    @Test func helpersJoinTheirApp() {
        let processes = [
            process("com.google.Chrome", pid: 10),
            process("com.google.Chrome.helper", pid: 11),
            process("com.google.Chrome.helper.Renderer", pid: 12),
        ]
        let groups = EqualiserPolicy.groups(
            processes, runningAppBundleIDs: ["com.google.Chrome"], ownPID: ownPID)
        #expect(groups.count == 1)
        #expect(groups[0].bundleID == "com.google.Chrome")
        #expect(groups[0].pids == [10, 11, 12])
        #expect(groups[0].objectIDs.count == 3)
    }

    @Test func theLongestRunningAppWins() {
        let processes = [process("com.google.Chrome.canary.helper", pid: 20)]
        let groups = EqualiserPolicy.groups(
            processes,
            runningAppBundleIDs: ["com.google.Chrome", "com.google.Chrome.canary"],
            ownPID: ownPID)
        #expect(groups.map(\.bundleID) == ["com.google.Chrome.canary"])
    }

    @Test func aDottedAncestorNeedsTheDotNotJustThePrefix() {
        let processes = [process("com.google.ChromeRemote", pid: 21)]
        let groups = EqualiserPolicy.groups(
            processes, runningAppBundleIDs: ["com.google.Chrome"], ownPID: ownPID)
        #expect(groups.map(\.bundleID) == ["com.google.ChromeRemote"])
    }

    @Test func aWebKitHelperIsNeverMappedToSafari() {
        let processes = [
            process("com.apple.WebKit.GPU", pid: 30),
            process("com.apple.WebKit.WebContent", pid: 31),
        ]
        let groups = EqualiserPolicy.groups(
            processes, runningAppBundleIDs: ["com.apple.Safari"], ownPID: ownPID)
        #expect(groups.map(\.bundleID).sorted() == ["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"])
    }

    @Test func aProcessWithNoRunningAppKeepsItsOwnBundleID() {
        let groups = EqualiserPolicy.groups(
            [process("com.example.daemon", pid: 40)], runningAppBundleIDs: [], ownPID: ownPID)
        #expect(groups.map(\.bundleID) == ["com.example.daemon"])
    }

    @Test func processesWithNoBundleIDAreDroppedFromGroups() {
        let groups = EqualiserPolicy.groups(
            [process(nil, pid: 50), process("", pid: 51), process("com.apple.Music", pid: 52)],
            runningAppBundleIDs: ["com.apple.Music"], ownPID: ownPID)
        #expect(groups.map(\.bundleID) == ["com.apple.Music"])
    }

    @Test func ownPIDNeverJoinsAGroup() {
        let groups = EqualiserPolicy.groups(
            [process("app.zeus.Zeus", pid: ownPID)], runningAppBundleIDs: ["app.zeus.Zeus"], ownPID: ownPID)
        #expect(groups.isEmpty)
    }

    @Test func aGroupPlaysWhenAnyMemberDoesAndKeepsEveryDevice() {
        let processes = [
            process("com.spotify.client", pid: 60, output: false, devices: []),
            process("com.spotify.client.helper", pid: 61, output: true, devices: ["speakers", "buds"]),
            process("com.spotify.client.helper", pid: 62, output: true, devices: ["speakers"]),
        ]
        let groups = EqualiserPolicy.groups(
            processes, runningAppBundleIDs: ["com.spotify.client"], ownPID: ownPID)
        #expect(groups.count == 1)
        #expect(groups[0].isPlaying)
        #expect(groups[0].devices == ["buds", "speakers"])
    }

    @Test func aQuietGroupIsNotPlaying() {
        let groups = EqualiserPolicy.groups(
            [process("com.apple.Music", pid: 70, output: false, devices: [])],
            runningAppBundleIDs: ["com.apple.Music"], ownPID: ownPID)
        #expect(groups.map(\.isPlaying) == [false])
    }

    @Test func groupsComeInStableOrder() {
        let processes = [process("com.b.app", pid: 81), process("com.a.app", pid: 80)]
        let groups = EqualiserPolicy.groups(processes, runningAppBundleIDs: [], ownPID: ownPID)
        #expect(groups.map(\.bundleID) == ["com.a.app", "com.b.app"])
    }

    @Test func playingGroupsKeepOnlyPlayingAppsAndTakeNamesWhenKnown() {
        let processes = [
            process("com.apple.Music", pid: 90),
            process("com.example.quiet", pid: 91, output: false, devices: []),
            process("com.example.noname", pid: 92),
        ]
        let groups = EqualiserPolicy.groups(processes, runningAppBundleIDs: [], ownPID: ownPID)
        let playing = EqualiserPolicy.playingGroups(groups, names: ["com.apple.Music": "Music"])
        #expect(
            playing == [
                EqualiserPlayingGroup(bundleID: "com.apple.Music", displayName: "Music"),
                EqualiserPlayingGroup(bundleID: "com.example.noname", displayName: "com.example.noname"),
            ])
    }
}

// MARK: - Exclusion

@Suite struct EqualiserExclusionTests {
    private let own = "app.zeus.Zeus"

    @Test func aWebKitHelperIsASharedEngineNeverSafari() {
        #expect(EqualiserPolicy.exclusion(for: "com.apple.WebKit.GPU", ownBundleID: own) == .sharedEngine)
        #expect(EqualiserPolicy.exclusion(for: "com.apple.WebKit.WebContent", ownBundleID: own) == .sharedEngine)
        #expect(EqualiserPolicy.exclusion(for: "com.apple.WebKit.Networking", ownBundleID: own) == .sharedEngine)
    }

    @Test func zeusAndItsHelpersAreExcluded() {
        #expect(EqualiserPolicy.exclusion(for: own, ownBundleID: own) == .zeus)
        #expect(EqualiserPolicy.exclusion(for: own + ".helper", ownBundleID: own) == .zeus)
    }

    @Test func everyCallAppIsExcluded() {
        let callApps = [
            "com.microsoft.teams2", "com.microsoft.teams", "us.zoom.xos", "com.apple.FaceTime",
            "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark",
            "net.whatsapp.WhatsApp", "com.skype.skype", "org.whispersystems.signal-desktop", "ru.keepcoder.Telegram",
        ]
        for id in callApps {
            #expect(EqualiserPolicy.exclusion(for: id, ownBundleID: own) == .callApp, "\(id)")
            #expect(EqualiserPolicy.exclusion(for: id + ".helper", ownBundleID: own) == .callApp, "\(id) helper")
        }
    }

    @Test func aBrowserIsNotACallAppByItself() {
        #expect(EqualiserPolicy.exclusion(for: "com.google.Chrome", ownBundleID: own) == nil)
        #expect(EqualiserPolicy.exclusion(for: "com.apple.Safari", ownBundleID: own) == nil)
    }

    @Test func aMusicAppIsNotExcluded() {
        #expect(EqualiserPolicy.exclusion(for: "com.apple.Music", ownBundleID: own) == nil)
        #expect(EqualiserPolicy.exclusion(for: "com.spotify.client", ownBundleID: own) == nil)
    }

    @Test func noBundleIDIsExcluded() {
        #expect(EqualiserPolicy.exclusion(for: "", ownBundleID: own) == .noBundleID)
    }

    private func group(_ id: String, playing: Bool = true, devices: [String]) -> EqualiserProcessGroup {
        EqualiserProcessGroup(
            bundleID: id, objectIDs: [1], pids: [2], isPlaying: playing, devices: devices)
    }

    @Test func aGroupPlayingToAnotherDeviceIsExcluded() {
        let elsewhere = group("com.apple.Music", devices: ["buds"])
        #expect(
            EqualiserPolicy.exclusion(for: elsewhere, ownBundleID: own, defaultOutputUID: "speakers")
                == .otherDevice)
        let both = group("com.apple.Music", devices: ["buds", "speakers"])
        #expect(
            EqualiserPolicy.exclusion(for: both, ownBundleID: own, defaultOutputUID: "speakers") == .otherDevice)
    }

    @Test func aPlayingGroupWithNoReadableDeviceIsExcludedRatherThanGuessed() {
        let unknown = group("com.apple.Music", devices: [])
        #expect(
            EqualiserPolicy.exclusion(for: unknown, ownBundleID: own, defaultOutputUID: "speakers")
                == .otherDevice)
    }

    @Test func aGroupOnTheDefaultOutputIsNotExcluded() {
        let home = group("com.apple.Music", devices: ["speakers"])
        #expect(EqualiserPolicy.exclusion(for: home, ownBundleID: own, defaultOutputUID: "speakers") == nil)
    }

    @Test func aQuietGroupIsJudgedByItsBundleOnly() {
        let quiet = group("com.apple.Music", playing: false, devices: [])
        #expect(EqualiserPolicy.exclusion(for: quiet, ownBundleID: own, defaultOutputUID: "speakers") == nil)
        let quietCall = group("us.zoom.xos", playing: false, devices: [])
        #expect(
            EqualiserPolicy.exclusion(for: quietCall, ownBundleID: own, defaultOutputUID: "speakers") == .callApp)
    }

    @Test func theBundleReasonWinsOverTheDevice() {
        let call = group("us.zoom.xos", devices: ["buds"])
        #expect(EqualiserPolicy.exclusion(for: call, ownBundleID: own, defaultOutputUID: "speakers") == .callApp)
    }

    @Test func exclusionsAreKeyedByBundleIDForTheList() {
        let groups = [
            group("com.apple.Music", devices: ["speakers"]),
            group("us.zoom.xos", devices: ["speakers"]),
            group("com.example.far", devices: ["buds"]),
        ]
        let map = EqualiserPolicy.exclusions(groups, ownBundleID: own, defaultOutputUID: "speakers")
        #expect(map == ["us.zoom.xos": .callApp, "com.example.far": .otherDevice])
    }
}

// MARK: - What may be tapped

@Suite struct EqualiserTargetTests {
    private let own = "app.zeus.Zeus"

    private func group(_ id: String, playing: Bool = true, devices: [String] = ["speakers"]) -> EqualiserProcessGroup {
        EqualiserProcessGroup(bundleID: id, objectIDs: [1], pids: [2], isPlaying: playing, devices: devices)
    }

    private func targets(_ groups: [EqualiserProcessGroup], _ book: AppSoundBook) -> [EqualiserLifecycle.Target] {
        EqualiserPolicy.targets(
            groups, names: [:], book: book, ownBundleID: own, defaultOutputUID: "speakers")
    }

    @Test func aShapedPlayingAppIsATargetWithItsParameters() {
        let result = targets([group("com.apple.Music")], shapedBook(["com.apple.Music"], volume: 0.5))
        #expect(result.count == 1)
        #expect(result[0].app.bundleID == "com.apple.Music")
        #expect(result[0].isPlaying)
        #expect(result[0].parameters.volume == 0.5)
        #expect(result[0].parameters.gainsDB[0] == 6)
    }

    @Test func aNeutralAppIsNeverATarget() {
        let flat = shapedBook(["com.apple.Music"], gains: [Double](repeating: 0, count: 10), volume: 1)
        #expect(targets([group("com.apple.Music")], flat).isEmpty)
        let off = shapedBook(["com.apple.Music"], shapes: false)
        #expect(targets([group("com.apple.Music")], off).isEmpty)
    }

    @Test func anAppWithNoSavedSettingsIsNeverATarget() {
        #expect(targets([group("com.apple.Music")], AppSoundBook()).isEmpty)
    }

    @Test func anExcludedAppIsNeverATargetEvenWhenSaved() {
        let book = shapedBook(["us.zoom.xos", "com.apple.WebKit.GPU", "com.example.far", "app.zeus.Zeus"])
        let result = targets(
            [
                group("us.zoom.xos"), group("com.apple.WebKit.GPU"),
                group("com.example.far", devices: ["buds"]), group("app.zeus.Zeus"),
            ], book)
        #expect(result.isEmpty)
    }

    @Test func aQuietShapedAppIsATargetThatIsNotPlaying() {
        let result = targets(
            [group("com.apple.Music", playing: false, devices: [])], shapedBook(["com.apple.Music"]))
        #expect(result.map(\.isPlaying) == [false])
    }

    @Test func theTargetTakesTheNameTheAppPlaysUnder() {
        let result = EqualiserPolicy.targets(
            [group("com.apple.Music")], names: ["com.apple.Music": "Music"],
            book: shapedBook(["com.apple.Music"]), ownBundleID: own, defaultOutputUID: "speakers")
        #expect(result.map(\.app.displayName) == ["Music"])
    }
}

// MARK: - Call recording

@Suite struct EqualiserCallRecordingTests {
    private let ownPID: Int32 = 1

    @Test func aCallAppReadingTheMicrophonePauses() {
        let facts = [process("us.zoom.xos", pid: 200, input: true)]
        #expect(EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func aCallHelperReadingTheMicrophonePauses() {
        let facts = [process("com.google.Chrome.helper", pid: 201, input: true)]
        #expect(EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func zeusItselfRecordingNeverPauses() {
        let facts = [process("app.zeus.Zeus", pid: ownPID, input: true)]
        #expect(!EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func aNonCallRecorderNeverPauses() {
        let facts = [process("com.example.recorder", pid: 202, input: true)]
        #expect(!EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func aCallAppWithTheMicrophoneClosedDoesNotPause() {
        let facts = [process("us.zoom.xos", pid: 203, input: false)]
        #expect(!EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func anUnreadableInputIsNotRecordingOnItsOwn() {
        let facts = [process("us.zoom.xos", pid: 204, input: nil)]
        #expect(!EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func anotherZeusProcessNeverPauses() {
        let facts = [process("app.zeus.helper", pid: 205, input: true)]
        #expect(!EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func aProcessWithNoBundleIDNeverPauses() {
        let facts = [process(nil, pid: 206, input: true)]
        #expect(!EqualiserPolicy.callRecording(facts, ownPID: ownPID))
    }

    @Test func unreadableCandidatesAreOnlyCallAppsOtherThanZeus() {
        let facts = [
            process("us.zoom.xos", pid: 210, input: nil),
            process("com.example.recorder", pid: 211, input: nil),
            process("app.zeus.Zeus", pid: ownPID, input: nil),
            process("com.apple.FaceTime", pid: 212, input: true),
            process("com.google.Chrome", pid: 213, input: nil),
        ]
        let unreadable = EqualiserPolicy.unreadableCallCandidates(facts, ownPID: ownPID)
        #expect(unreadable.map(\.pid) == [210, 213])
    }

    @Test func oneTransientUnreadableReadDoesNotCount() {
        #expect(!EqualiserPolicy.unreadableCounts(firstRead: nil, reRead: false, pidAlive: true))
        #expect(!EqualiserPolicy.unreadableCounts(firstRead: nil, reRead: true, pidAlive: true))
    }

    @Test func unreadableTwiceWithTheProcessAliveCounts() {
        #expect(EqualiserPolicy.unreadableCounts(firstRead: nil, reRead: nil, pidAlive: true))
    }

    @Test func unreadableTwiceWithTheProcessGoneDoesNotCount() {
        #expect(!EqualiserPolicy.unreadableCounts(firstRead: nil, reRead: nil, pidAlive: false))
    }

    @Test func aReadableFirstReadNeverCountsAsUnreadable() {
        #expect(!EqualiserPolicy.unreadableCounts(firstRead: true, reRead: nil, pidAlive: true))
        #expect(!EqualiserPolicy.unreadableCounts(firstRead: false, reRead: nil, pidAlive: true))
    }

    @Test func theRecheckWaitsTwoHundredFiftyMilliseconds() {
        #expect(EqualiserPolicy.unreadableRecheckDelay == 0.25)
    }
}

// MARK: - Zeus capture

@Suite struct EqualiserZeusCaptureTests {
    private let id = ScribeSessionID()

    @Test func scribeStartingRecordingAndEndingEachCount() {
        #expect(EqualiserPolicy.zeusCaptures(scribe: .starting(id), polyglotActive: false, recordlySystemAudio: false))
        #expect(
            EqualiserPolicy.zeusCaptures(
                scribe: .recording(id, since: 1), polyglotActive: false, recordlySystemAudio: false))
        #expect(
            EqualiserPolicy.zeusCaptures(
                scribe: .ending(id, deadline: 5), polyglotActive: false, recordlySystemAudio: false))
    }

    @Test func scribeIdleProcessingCompleteAndFailedDoNotCount() {
        for phase in [
            ScribePhase.idle, .processing(id), .complete(id), .failed(id, reason: "x"),
        ] {
            #expect(!EqualiserPolicy.zeusCaptures(scribe: phase, polyglotActive: false, recordlySystemAudio: false))
        }
    }

    @Test func polyglotAloneCounts() {
        #expect(EqualiserPolicy.zeusCaptures(scribe: .idle, polyglotActive: true, recordlySystemAudio: false))
    }

    @Test func recordlySystemAudioAloneCounts() {
        #expect(EqualiserPolicy.zeusCaptures(scribe: .idle, polyglotActive: false, recordlySystemAudio: true))
    }

    @Test func nothingRecordingMeansNoPause() {
        #expect(!EqualiserPolicy.zeusCaptures(scribe: .idle, polyglotActive: false, recordlySystemAudio: false))
    }
}

// MARK: - Pause reason

@Suite struct EqualiserPauseReasonTests {
    private let fine = EqualiserFormat.Verdict.supported
    private let bad = EqualiserFormat.Verdict.unsupported(reason: "no channels")

    private func reason(
        call: Bool = false, zeus: Bool = false, other: Bool = false, asleep: Bool = false,
        format: EqualiserFormat.Verdict? = nil
    ) -> EqualiserPause? {
        EqualiserPolicy.pauseReason(
            callRecording: call, zeusCaptures: zeus, otherShaper: other, asleep: asleep, format: format ?? fine)
    }

    @Test func nothingWrongMeansNoPause() {
        #expect(reason() == nil)
    }

    @Test func eachReasonAloneGivesItsPause() {
        #expect(reason(call: true) == .callRecording)
        #expect(reason(zeus: true) == .zeusCaptures)
        #expect(reason(other: true) == .otherShaper)
        #expect(reason(asleep: true) == .asleep)
        #expect(reason(format: bad) == .unsupportedOutput(reason: "no channels"))
    }

    @Test func whenSeveralApplyTheOrderIsSleepThenClaimThenCallThenZeusThenFormat() {
        #expect(reason(call: true, zeus: true, other: true, asleep: true, format: bad) == .asleep)
        #expect(reason(call: true, zeus: true, other: true, format: bad) == .otherShaper)
        #expect(reason(call: true, zeus: true, format: bad) == .callRecording)
        #expect(reason(zeus: true, format: bad) == .zeusCaptures)
    }
}

// MARK: - Format

@Suite struct EqualiserFormatTests {
    private func float(_ rate: Double = 48_000, _ channels: Int = 2) -> EqualiserStreamFormat {
        .float32(sampleRate: rate, channelCount: channels)
    }

    private func isUnsupported(_ verdict: EqualiserFormat.Verdict) -> Bool {
        if case .unsupported(let reason) = verdict { return !reason.isEmpty && hasNoDash(reason) }
        return false
    }

    @Test func float32LinearPCMAtEqualRatesIsSupported() {
        #expect(EqualiserFormat.verdict(tap: float(), output: float(), outputIsAggregate: false) == .supported)
    }

    @Test func aMonoOutputIsSupported() {
        #expect(EqualiserFormat.verdict(tap: float(), output: float(48_000, 1), outputIsAggregate: false) == .supported)
    }

    @Test func int16IsUnsupported() {
        let int16 = EqualiserStreamFormat(
            isLinearPCM: true, isFloat: false, bitsPerChannel: 16, sampleRate: 48_000, channelCount: 2)
        #expect(isUnsupported(EqualiserFormat.verdict(tap: int16, output: float(), outputIsAggregate: false)))
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(), output: int16, outputIsAggregate: false)))
    }

    @Test func float64AndNonPCMAreUnsupported() {
        let double = EqualiserStreamFormat(
            isLinearPCM: true, isFloat: true, bitsPerChannel: 64, sampleRate: 48_000, channelCount: 2)
        let coded = EqualiserStreamFormat(
            isLinearPCM: false, isFloat: true, bitsPerChannel: 32, sampleRate: 48_000, channelCount: 2)
        #expect(isUnsupported(EqualiserFormat.verdict(tap: double, output: float(), outputIsAggregate: false)))
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(), output: coded, outputIsAggregate: false)))
    }

    @Test func aRateMismatchIsUnsupported() {
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(44_100), output: float(48_000), outputIsAggregate: false)))
    }

    @Test func noChannelsIsUnsupported() {
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(), output: float(48_000, 0), outputIsAggregate: false)))
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(48_000, 0), output: float(), outputIsAggregate: false)))
    }

    @Test func anAggregateOrMultiOutputDeviceIsUnsupported() {
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(), output: float(), outputIsAggregate: true)))
    }

    @Test func aZeroRateIsUnsupported() {
        #expect(isUnsupported(EqualiserFormat.verdict(tap: float(0), output: float(0), outputIsAggregate: false)))
    }
}

// MARK: - Routing

@Suite struct EqualiserRoutingTests {
    private let firstPair = (left: 0, right: 1)

    @Test func stereoGoesToTheDevicePair() {
        let map = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 2, stereoPair: firstPair)
        #expect(map == [.tap(0), .tap(1)])
    }

    @Test func aMonoDeviceGetsTheAverage() {
        let map = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 1, stereoPair: firstPair)
        #expect(map == [.average])
    }

    @Test func aMonoTapOnAMonoDeviceIsTheSameChannel() {
        let map = EqualiserRouting.channelMap(tapChannels: 1, outputChannels: 1, stereoPair: firstPair)
        #expect(map == [.tap(0)])
    }

    @Test func aMonoTapFillsBothSidesOfAStereoPair() {
        let map = EqualiserRouting.channelMap(tapChannels: 1, outputChannels: 2, stereoPair: firstPair)
        #expect(map == [.tap(0), .tap(0)])
    }

    @Test func aSixChannelDeviceGetsStereoOnItsPairAndSilenceElsewhere() {
        let map = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 6, stereoPair: (left: 2, right: 3))
        #expect(map == [.silence, .silence, .tap(0), .tap(1), .silence, .silence])
    }

    @Test func aSixChannelDeviceWithTheDefaultPairUsesTheFirstTwo() {
        let map = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 6, stereoPair: firstPair)
        #expect(map == [.tap(0), .tap(1), .silence, .silence, .silence, .silence])
    }

    @Test func aSixChannelTapUsesItsFirstTwoChannels() {
        let map = EqualiserRouting.channelMap(tapChannels: 6, outputChannels: 2, stereoPair: firstPair)
        #expect(map == [.tap(0), .tap(1)])
        let toMono = EqualiserRouting.channelMap(tapChannels: 6, outputChannels: 1, stereoPair: firstPair)
        #expect(toMono == [.average])
    }

    @Test func aPairOutsideTheDeviceFallsBackToTheFirstTwo() {
        let past = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 4, stereoPair: (left: 4, right: 5))
        #expect(past == [.tap(0), .tap(1), .silence, .silence])
        let same = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 4, stereoPair: (left: 2, right: 2))
        #expect(same == [.tap(0), .tap(1), .silence, .silence])
        let negative = EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 4, stereoPair: (left: -1, right: 1))
        #expect(negative == [.tap(0), .tap(1), .silence, .silence])
    }

    @Test func noTapChannelsOrNoOutputChannelsGiveSilence() {
        #expect(
            EqualiserRouting.channelMap(tapChannels: 0, outputChannels: 2, stereoPair: firstPair)
                == [.silence, .silence])
        #expect(EqualiserRouting.channelMap(tapChannels: 2, outputChannels: 0, stereoPair: firstPair).isEmpty)
    }

    @Test func theTapStreamFollowsTheSubDevicesInputStreams() {
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 0, aggregateInputStreams: 1, tapStreams: 1) == 0)
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 1, aggregateInputStreams: 2, tapStreams: 1) == 1)
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 2, aggregateInputStreams: 3, tapStreams: 1) == 2)
    }

    @Test func aCountThatDoesNotAddUpGivesNoIndex() {
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 1, aggregateInputStreams: 1, tapStreams: 1) == nil)
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 1, aggregateInputStreams: 3, tapStreams: 1) == nil)
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 0, aggregateInputStreams: 0, tapStreams: 0) == nil)
    }

    @Test func moreThanOneTapStreamGivesNoIndex() {
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: 1, aggregateInputStreams: 3, tapStreams: 2) == nil)
    }

    @Test func negativeCountsGiveNoIndex() {
        #expect(EqualiserRouting.tapStreamIndex(deviceInputStreams: -1, aggregateInputStreams: 0, tapStreams: 1) == nil)
    }
}

// MARK: - Own devices

@Suite struct EqualiserOwnDeviceTests {
    @Test func theEqualiserUIDPrefixIsOwn() {
        #expect(ZeusAudioDevices.isOwnAggregate(uid: "app.zeus.eq.3F2A", name: "anything"))
        #expect(ZeusAudioDevices.isOwnAggregate(uid: "app.zeus.eq.", name: ""))
    }

    @Test func theSpectrumAndScribeNamesAreOwn() {
        #expect(ZeusAudioDevices.isOwnAggregate(uid: "x", name: "Zeus spectrum"))
        #expect(ZeusAudioDevices.isOwnAggregate(uid: "x", name: "Zeus Scribe"))
    }

    @Test func aTapNamedForTheEqualiserIsOwnByItsUID() {
        #expect(ZeusAudioDevices.isOwnAggregate(uid: "app.zeus.eq.9", name: "Zeus EQ Music"))
    }

    @Test func anotherDeviceIsNot() {
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers"))
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: "app.zeus.equaliser", name: "Other"))
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: "x", name: "Zeus spectrum 2"))
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: "x", name: "zeus spectrum"))
    }
}
