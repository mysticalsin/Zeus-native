import Foundation
import Testing
@testable import ZeusCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite struct FocusNameGateTests {
    @Test func closedSettingsReadNothingAndAnImportCannotTurnThemOn() {
        let closed = FocusSectionSettings.closed
        #expect(closed.transitionOverlay == false)
        #expect(closed.overlaysAllowed == false)
        #expect(closed.lockScreen == false)
        #expect(closed.readName == false)
        #expect(closed.storeFile == false)
        #expect(closed.localNetwork == false)
        #expect(closed.sharedLink == false)
        #expect(closed.homeWidget == "Focus")
        #expect(FocusSettingKey.optIn.count == 7)
        #expect(!FocusSettingKey.optIn.contains(FocusSettingKey.homeWidget))
        #expect(!FocusSettingKey.optIn.contains("notify.focus"))
        #expect(!FocusSettingKey.optIn.contains("tiling.focusBorder"))

        for mask in 0..<128 {
            var bools: [String: Bool] = [:]
            for (index, key) in FocusSettingKey.optIn.enumerated() where mask & (1 << index) != 0 {
                bools[key] = true
            }
            let imported = FocusSectionSettings.imported(bools: bools, homeWidget: "Music")
            #expect(imported.transitionOverlay == false)
            #expect(imported.overlaysAllowed == false)
            #expect(imported.lockScreen == false)
            #expect(imported.readName == false)
            #expect(imported.storeFile == false)
            #expect(imported.localNetwork == false)
            #expect(imported.sharedLink == false)
            #expect(imported.homeWidget == "Music")
        }
        let outside = Set(SettingsKeyReachability.outsideKeys)
        for key in FocusSettingKey.optIn {
            #expect(!outside.contains(key))
        }
    }

    @Test func offIgnoresSamplesAndNeverReadsTheStoreOrTheNetwork() {
        var machine = FocusNameMachine()
        #expect(machine.handle(.setStoreFile(true)).isEmpty)
        #expect(machine.handle(.setLocalNetwork(true)).isEmpty)
        #expect(machine.handle(.setSharedLink(true)).isEmpty)
        #expect(machine.handle(.permission(.focusStatus, .allowed)).isEmpty)
        #expect(machine.handle(.permission(.fullDisk, .allowed)).isEmpty)
        #expect(machine.handle(.permission(.localNetwork, .allowed)).isEmpty)
        let stored = machine.handle(.storeSample(.on(name: "Deep Work", symbol: "moon.fill")))
        let browsed = machine.handle(.networkNames(["Quiet"]))
        let linked = machine.handle(.link(FocusLink(transport: .tls, scope: .sharedWiFi, hasOneTimeToken: true, name: "Deep Work")))
        #expect(stored.isEmpty)
        #expect(browsed.isEmpty)
        #expect(linked.isEmpty)
        #expect(machine.phase == .off)
        #expect(machine.activity == .unknown)
        #expect(machine.displayName == nil)
        #expect(!machine.handle(.publicSample(isFocused: true, attachedName: "Deep Work")).contains(.readStore))
    }

    @Test func focusNameUsesThePublicFilterUnlessTheStoreFileIsOptedIn() {
        var machine = FocusNameMachine()
        let turnedOn = machine.handle(.setRead(true))
        #expect(turnedOn == [.request(.focusStatus)])
        #expect(machine.phase == .checking)
        #expect(machine.handle(.permission(.focusStatus, .allowed)) == [.readPublic])
        let sample = machine.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
        #expect(!sample.contains(.readStore))
        #expect(!sample.contains(.browseLocalNetwork))
        #expect(machine.phase == .allowed(.publicFilter))
        #expect(machine.displayName == "Deep Work")
        #expect(machine.activity == .on(name: "Deep Work"))
        let ignoredStore = machine.handle(.storeSample(.on(name: "Reading", symbol: "book")))
        #expect(ignoredStore.isEmpty)
        #expect(machine.displayName == "Deep Work")
        #expect(machine.phase == .allowed(.publicFilter))

        var opted = FocusNameMachine()
        _ = opted.handle(.setRead(true))
        _ = opted.handle(.setStoreFile(true))
        _ = opted.handle(.permission(.focusStatus, .allowed))
        _ = opted.handle(.permission(.fullDisk, .allowed))
        let needsStore = opted.handle(.publicSample(isFocused: true, attachedName: nil))
        #expect(needsStore.contains(.readStore))
        #expect(opted.displayName == nil)
        #expect(opted.activity == .on(name: nil))
        _ = opted.handle(.storeSample(.on(name: "Reading", symbol: "moon.fill")))
        #expect(opted.phase == .allowed(.storeFile))
        #expect(opted.displayName == "Reading")

        var named = FocusNameMachine()
        _ = named.handle(.setRead(true))
        _ = named.handle(.setStoreFile(true))
        _ = named.handle(.permission(.focusStatus, .allowed))
        _ = named.handle(.permission(.fullDisk, .allowed))
        let publicWins = named.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
        #expect(!publicWins.contains(.readStore))
        #expect(named.displayName == "Deep Work")
        #expect(named.phase == .allowed(.publicFilter))
    }

    @Test func aDeniedFocusStatusShowsUnavailableAndTheStoreIsASeparateOptIn() {
        var denied = FocusNameMachine()
        _ = denied.handle(.setRead(true))
        #expect(denied.handle(.permission(.focusStatus, .denied)).isEmpty)
        #expect(denied.phase == .unavailable(.focusStatus))
        #expect(denied.displayName == nil)
        #expect(denied.handle(.publicSample(isFocused: true, attachedName: "Deep Work")).isEmpty)
        #expect(denied.displayName == nil)
        #expect(denied.handle(.storeSample(.on(name: "Deep Work", symbol: "moon.fill"))).isEmpty)

        var fallback = FocusNameMachine()
        _ = fallback.handle(.setRead(true))
        _ = fallback.handle(.setStoreFile(true))
        let asks = fallback.handle(.permission(.focusStatus, .denied))
        #expect(asks == [.request(.fullDisk)])
        #expect(fallback.phase == .checking)
        #expect(fallback.handle(.permission(.fullDisk, .denied)).isEmpty)
        #expect(fallback.phase == .unavailable(.fullDisk))
        #expect(fallback.storeStatus == .unavailable("Unavailable. Full Disk Access was not allowed."))
        #expect(fallback.displayName == nil)

        _ = fallback.handle(.permission(.fullDisk, .allowed))
        #expect(fallback.handle(.storeSample(.on(name: "Reading", symbol: nil))) == [])
        #expect(fallback.phase == .allowed(.storeFile))
        #expect(fallback.displayName == "Reading")
    }

    @Test func thePublicOffWinsOverTheStoreAndAPlainLabelCoversAMissingName() {
        var machine = FocusNameMachine()
        _ = machine.handle(.setRead(true))
        _ = machine.handle(.setStoreFile(true))
        _ = machine.handle(.permission(.focusStatus, .allowed))
        _ = machine.handle(.permission(.fullDisk, .allowed))
        _ = machine.handle(.publicSample(isFocused: false, attachedName: nil))
        _ = machine.handle(.storeSample(.on(name: "Deep Work", symbol: "moon.fill")))
        #expect(machine.activity == .off)
        #expect(machine.displayName == nil)
        #expect(machine.phase == .allowed(.publicFilter))

        _ = machine.handle(.publicSample(isFocused: true, attachedName: " \n "))
        #expect(machine.activity == .on(name: nil))
        #expect(machine.displayName == nil)
        _ = machine.handle(.storeSample(.unreadable(.malformed)))
        #expect(machine.activity == .on(name: nil))
        #expect(machine.storeStatus == .unavailable("Unavailable. The Focus store could not be read."))
        #expect(machine.displayName == nil)
    }

    @Test func focusNameDoesNotBrowseUntilLocalNetworkIsOn() {
        var machine = FocusNameMachine()
        _ = machine.handle(.setRead(true))
        _ = machine.handle(.permission(.focusStatus, .allowed))
        _ = machine.handle(.permission(.localNetwork, .allowed))
        _ = machine.handle(.publicSample(isFocused: true, attachedName: nil))
        let ignored = machine.handle(.networkNames(["Quiet"]))
        #expect(ignored.isEmpty)
        #expect(!ignored.contains(.browseLocalNetwork))
        #expect(machine.displayName == nil)
        #expect(machine.networkStatus == .off)

        let requested = machine.handle(.setLocalNetwork(true))
        #expect(requested == [.browseLocalNetwork])
        _ = machine.handle(.networkNames(["Quiet", "Deep Work"]))
        #expect(machine.displayName == "Quiet")
        #expect(machine.phase == .allowed(.localNetwork))

        var denied = FocusNameMachine()
        _ = denied.handle(.setRead(true))
        _ = denied.handle(.permission(.focusStatus, .allowed))
        _ = denied.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
        let blocked = denied.handle(.setLocalNetwork(true))
        #expect(blocked == [.request(.localNetwork)])
        #expect(denied.handle(.permission(.localNetwork, .denied)).isEmpty)
        #expect(denied.networkStatus == .unavailable("Unavailable. Local network was not allowed."))
        #expect(denied.handle(.networkNames(["Other"])).isEmpty)
        #expect(denied.displayName == "Deep Work")
        #expect(denied.phase == .allowed(.publicFilter))
    }

    @Test func theDropPageRefusesPlainHttpOnSharedWiFi() {
        let refused = [
            FocusLink(transport: .plain, scope: .sharedWiFi, hasOneTimeToken: false, name: "Deep Work"),
            FocusLink(transport: .plain, scope: .sharedWiFi, hasOneTimeToken: true, name: "Deep Work"),
            FocusLink(transport: .tls, scope: .sharedWiFi, hasOneTimeToken: false, name: "Deep Work"),
        ]
        for link in refused {
            #expect(FocusLinkRule.decide(link) == .refused)
        }
        let secured = FocusLink(transport: .tls, scope: .sharedWiFi, hasOneTimeToken: true, name: "Deep Work")
        #expect(FocusLinkRule.decide(secured) == .accepted(label: "Deep Work"))
        let local = FocusLink(transport: .plain, scope: .localOnly, hasOneTimeToken: false, name: "Reading")
        #expect(FocusLinkRule.decide(local) == .accepted(label: "Reading"))
        let blank = FocusLink(transport: .tls, scope: .localOnly, hasOneTimeToken: true, name: "   ")
        #expect(FocusLinkRule.decide(blank) == .accepted(label: nil))

        for transport in [FocusLink.Transport.plain, .tls] {
            for scope in [FocusLink.Scope.sharedWiFi, .localOnly] {
                for token in [false, true] {
                    let link = FocusLink(transport: transport, scope: scope, hasOneTimeToken: token, name: "Deep Work")
                    let decision = FocusLinkRule.decide(link)
                    let sharedPlain = scope == .sharedWiFi && (transport != .tls || !token)
                    if sharedPlain {
                        #expect(decision == .refused)
                    } else {
                        #expect(decision == .accepted(label: "Deep Work"))
                    }
                }
            }
        }

        var machine = FocusNameMachine()
        _ = machine.handle(.setRead(true))
        _ = machine.handle(.setSharedLink(true))
        _ = machine.handle(.permission(.focusStatus, .denied))
        let dropped = machine.handle(.link(refused[0]))
        #expect(dropped.isEmpty)
        #expect(machine.displayName == nil)
        #expect(machine.linkStatus == .unavailable("Unavailable. That link was refused."))
        _ = machine.handle(.link(secured))
        #expect(machine.displayName == "Deep Work")
        #expect(machine.phase == .allowed(.sharedLink))

        var quiet = FocusNameMachine()
        _ = quiet.handle(.setRead(true))
        _ = quiet.handle(.permission(.focusStatus, .allowed))
        _ = quiet.handle(.publicSample(isFocused: false, attachedName: nil))
        _ = quiet.handle(.setSharedLink(true))
        _ = quiet.handle(.link(secured))
        #expect(quiet.activity == .off)
        #expect(quiet.displayName == nil)
    }

    @Test func turningReadingOffDropsTheNameAndALateSample() {
        var machine = FocusNameMachine()
        _ = machine.handle(.setRead(true))
        _ = machine.handle(.setStoreFile(true))
        _ = machine.handle(.permission(.focusStatus, .allowed))
        _ = machine.handle(.permission(.fullDisk, .allowed))
        _ = machine.handle(.publicSample(isFocused: true, attachedName: nil))
        let stopped = machine.handle(.setRead(false))
        #expect(stopped == [.cancel])
        #expect(machine.phase == .off)
        #expect(machine.displayName == nil)
        #expect(machine.handle(.storeSample(.on(name: "Deep Work", symbol: "moon.fill"))).isEmpty)
        #expect(machine.displayName == nil)
    }

    @Test func namesAndSymbolsStayInsideTheBoundary() {
        #expect(FocusNameText.cleanName("Deep Work") == "Deep Work")
        #expect(FocusNameText.cleanName("  Work \n Mode  ") == "Work Mode")
        #expect(FocusNameText.cleanName(" \n\t ") == nil)
        #expect(FocusNameText.cleanName("A\u{0001}B") == "AB")
        #expect(FocusNameText.cleanName("Go\u{202E}Home") == "GoHome")
        #expect(FocusNameText.cleanName("Go\u{200B}Home") == "GoHome")
        #expect(FocusNameText.cleanName("A\u{200D}B") == "AB")
        #expect(FocusNameText.cleanName("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}") == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
        #expect(FocusNameText.cleanName("\u{1F1FA}\u{1F1F8}") == "\u{1F1FA}\u{1F1F8}")
        let wide = String(repeating: "名", count: 20)
        #expect(FocusNameText.cleanName(wide) == wide)
        let long = String(repeating: "名", count: 10_000)
        #expect(FocusNameText.cleanName(long)?.count == 64)
        let sixtyFive = String(repeating: "a", count: 65)
        #expect(FocusNameText.cleanSymbol(String(repeating: "a", count: 64)) == String(repeating: "a", count: 64))
        #expect(FocusNameText.cleanSymbol(sixtyFive) == nil)
        #expect(FocusNameText.cleanSymbol("moon.fill") == "moon.fill")
        #expect(FocusNameText.cleanSymbol("../x") == nil)
        #expect(FocusNameText.cleanSymbol("Moon Fill") == nil)
        #expect(FocusNameText.cleanSymbol("") == nil)
        #expect(FocusNameText.cleanSymbol("moon_fill") == nil)
    }

    @Test func theStoreParserFailsClosedAndNeverInventsAName() throws {
        #expect(FocusStoreParser.parse(assertions: Data("[".utf8), configurations: nil) == .unreadable(.malformed))
        #expect(FocusStoreParser.parse(assertions: Data("[]".utf8), configurations: nil) == .unreadable(.malformed))
        #expect(FocusStoreParser.parse(assertions: Data("{}".utf8), configurations: nil) == .unreadable(.malformed))
        #expect(FocusStoreParser.parse(assertions: Data(#"{"data":[]}"#.utf8), configurations: nil) == .unreadable(.malformed))
        let empty = #"{"data":[{"storeAssertionRecords":[]}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(empty.utf8), configurations: nil) == .off)
        let absent = #"{"data":[{"modeConfigurations":{}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(absent.utf8), configurations: nil) == .off)
        let history = #"{"data":[{"storeAssertionRecords":[],"history":[{"assertionDetails":{"assertionDetailsModeIdentifier":"old"}}]}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(history.utf8), configurations: nil) == .off)

        let named = record(id: "work", name: "Deep Work", symbol: "moon.fill", time: 10)
        #expect(FocusStoreParser.parse(assertions: Data(named.utf8), configurations: nil) == .on(name: "Deep Work", symbol: "moon.fill"))

        let later = twoRecords()
        #expect(FocusStoreParser.parse(assertions: Data(later.utf8), configurations: nil) == .on(name: "Reading", symbol: "book"))
        let noTime = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"a"}},{"assertionDetails":{"assertionDetailsModeIdentifier":"b"}}],"modeConfigurations":{"a":{"mode":{"name":"First","symbolImageName":"moon.fill"}},"b":{"mode":{"name":"Second","symbolImageName":"book"}}}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(noTime.utf8), configurations: nil) == .on(name: "First", symbol: "moon.fill"))
        let badBesideGood = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{},"assertionStartDateTimestamp":99},{"assertionDetails":{"assertionDetailsModeIdentifier":"work"},"assertionStartDateTimestamp":1}],"modeConfigurations":{"work":{"mode":{"name":"Deep Work","symbolImageName":"moon.fill"}}}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(badBesideGood.utf8), configurations: nil) == .on(name: "Deep Work", symbol: "moon.fill"))
        let onlyBad = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{}},{"assertionDetails":{"assertionDetailsModeIdentifier":""}}]}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(onlyBad.utf8), configurations: nil) == .on(name: nil, symbol: nil))
        let missingMode = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"missing"}}]}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(missingMode.utf8), configurations: nil) == .on(name: nil, symbol: nil))
        let numberName = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"work"}}],"modeConfigurations":{"work":{"mode":{"name":12,"symbolImageName":"moon.fill"}}}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(numberName.utf8), configurations: nil) == .on(name: nil, symbol: "moon.fill"))
        let bidi = "Go\u{202E}Home"
        let hostile = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"work"}}],"modeConfigurations":{"work":{"mode":{"name":"\#(bidi)","symbolImageName":"../x","extra":true}}}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(hostile.utf8), configurations: nil) == .on(name: "GoHome", symbol: nil))
        let longName = String(repeating: "名", count: 10_000)
        let longJSON = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"work"}}],"modeConfigurations":{"work":{"mode":{"name":"\#(longName)","symbolImageName":"moon.fill"}}}}]}"#
        let parsed = FocusStoreParser.parse(assertions: Data(longJSON.utf8), configurations: nil)
        #expect(parsed == .on(name: String(repeating: "名", count: 64), symbol: "moon.fill"))

        let tooBig = Data(count: FocusStoreParser.maxBytes + 1)
        #expect(FocusStoreParser.parse(assertions: tooBig, configurations: nil) == .unreadable(.tooLarge))
        let exact = Data(count: FocusStoreParser.maxBytes)
        #expect(FocusStoreParser.parse(assertions: exact, configurations: nil) == .unreadable(.malformed))

        let assertionsOnly = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"work"}}]}]}"#
        let configurations = #"{"data":[{"modeConfigurations":{"work":{"mode":{"name":"Deep Work","symbolImageName":"moon.fill"}}}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(assertionsOnly.utf8), configurations: Data(configurations.utf8)) == .on(name: "Deep Work", symbol: "moon.fill"))
        #expect(FocusStoreParser.parse(assertions: Data(assertionsOnly.utf8), configurations: Data("not json".utf8)) == .on(name: nil, symbol: nil))
        let oversizedConfigurations = Data(count: FocusStoreParser.maxBytes + 1)
        #expect(FocusStoreParser.parse(assertions: Data(assertionsOnly.utf8), configurations: oversizedConfigurations) == .on(name: nil, symbol: nil))

        let longID = String(repeating: "a", count: 201)
        let longIDJSON = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(longID)"}}]}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(longIDJSON.utf8), configurations: nil) == .on(name: nil, symbol: nil))
        let edgeID = String(repeating: "b", count: 200)
        let edgeJSON = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(edgeID)"}}],"modeConfigurations":{"\#(edgeID)":{"mode":{"name":"Edge","symbolImageName":"moon.fill"}}}}]}"#
        #expect(FocusStoreParser.parse(assertions: Data(edgeJSON.utf8), configurations: nil) == .on(name: "Edge", symbol: "moon.fill"))
    }

    @Test func errnoMapsFailClosedForEachStorePlace() {
        for code in [EPERM, EACCES] {
            #expect(FocusStoreParser.mapErrno(code, place: .folder) == .unreadable(.denied))
            #expect(FocusStoreParser.mapErrno(code, place: .assertions) == .unreadable(.denied))
            #expect(FocusStoreParser.mapErrno(code, place: .configurations) == .on(name: nil, symbol: nil))
        }
        #expect(FocusStoreParser.mapErrno(ENOENT, place: .folder) == .unreadable(.missing))
        #expect(FocusStoreParser.mapErrno(ENOENT, place: .assertions) == .off)
        #expect(FocusStoreParser.mapErrno(ENOENT, place: .configurations) == .on(name: nil, symbol: nil))
        for code in [ENOTDIR, ELOOP] {
            #expect(FocusStoreParser.mapErrno(code, place: .folder) == .unreadable(.notAFile))
        }
        #expect(FocusStoreParser.mapErrno(ELOOP, place: .assertions) == .unreadable(.notAFile))
        #expect(FocusStoreParser.mapErrno(999, place: .folder) == .unreadable(.other))
        #expect(FocusStoreParser.mapErrno(999, place: .assertions) == .unreadable(.other))
        #expect(FocusStoreParser.mapErrno(999, place: .configurations) == .on(name: nil, symbol: nil))
    }

    private func record(id: String, name: String, symbol: String, time: Int) -> String {
        #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(id)"},"assertionStartDateTimestamp":\#(time)}],"modeConfigurations":{"\#(id)":{"mode":{"name":"\#(name)","symbolImageName":"\#(symbol)"}}}}]}"#
    }

    private func twoRecords() -> String {
        """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"work"},"assertionStartDateTimestamp":1},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"read"},"assertionStartDateTimestamp":5}
        ],"modeConfigurations":{
          "work":{"mode":{"name":"Deep Work","symbolImageName":"moon.fill"}},
          "read":{"mode":{"name":"Reading","symbolImageName":"book"}}
        }}]}
        """
    }
}
