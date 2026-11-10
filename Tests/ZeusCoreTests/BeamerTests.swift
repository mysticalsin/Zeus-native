import Foundation
import Testing
@testable import ZeusCore

/// Fixtures come from Beamer 1.5.18: `instance_signal`, `settings_store` (peers), `link_state`,
/// `machines` and the tray menu in kvm_bridge_app.py. See docs/BEAMER.md.
@Suite struct BeamerTests {
    // MARK: Protocol

    @Test func socketAndFilesMatchBeamer() {
        let home = URL(fileURLWithPath: "/Users/tony")
        #expect(BeamerFiles.socket(home: home).path == "/Users/tony/Library/Application Support/Beamer/Beamer.sock")
        #expect(BeamerFiles.settings(home: home).path == "/Users/tony/Library/Application Support/Beamer/settings.json")
        #expect(BeamerFiles.log(home: home).path == "/Users/tony/Library/Logs/Beamer/Beamer.log")
        #expect(BeamerFiles.bundleID == "uk.co.kalkman.beamer")
    }

    @Test func activateIsTheOneMessage() {
        // `request_running_instance` sends b"activate\n"; UnixSocket.request adds the newline.
        #expect(BeamerMessage.activateLine == "activate\n")
        #expect(String(decoding: BeamerMessage.activate, as: UTF8.self) + "\n" == BeamerMessage.activateLine)
    }

    // MARK: settings.json

    static let settingsJSON = """
    {"machine_id": "AAECAwQFBgcICQoLDA0ODw==", "name": "Tony's MacBook", "port": 24800,
     "peers": [
       {"id": "EBESExQVFhcYGRobHB0eHw==", "name": "Studio PC", "platform": "windows", "token": "SECRET-TOKEN-1", "host": "192.168.1.20", "port": 24801,
        "hw": "aa:bb:cc:dd:ee:ff", "send": true, "allow_drive": true, "in_use": true, "side": "right", "linked": true},
       {"id": "ICEiIyQlJicoKSorLC0uLw==", "name": "Mac mini", "platform": "mac", "token": "SECRET-TOKEN-2", "host": "mini.local", "port": 24801,
        "send": true, "allow_drive": false, "in_use": false},
       {"id": "", "name": "", "platform": "tablet", "host": "10.0.0.9", "port": 24801}
     ],
     "zones": [{"peer": "x", "kind": "edge", "off": false}]}
    """

    @Test func parsesPairedMachinesAndIgnoresTokens() {
        let machines = BeamerSettingsFile.machines(from: Data(Self.settingsJSON.utf8))
        #expect(machines.count == 3)
        #expect(machines[0].name == "Studio PC")
        #expect(machines[0].platform == .windows)
        #expect(machines[0].host == "192.168.1.20" && machines[0].port == 24801)
        #expect(machines[0].canDrive && machines[0].inUse)
        #expect(machines[1].platform == .mac && !machines[1].inUse && !machines[1].canDrive)
        // A peer with no id or name still reads: named after its address, platform "other".
        #expect(machines[2].name == "10.0.0.9" && machines[2].platform == .other && machines[2].id == "peer-2")
        #expect(!String(describing: machines).contains("SECRET"))
    }

    @Test func brokenSettingsGiveNoMachines() {
        #expect(BeamerSettingsFile.machines(from: Data("not json".utf8)).isEmpty)
        #expect(BeamerSettingsFile.machines(from: Data("{}".utf8)).isEmpty)
    }

    // MARK: Tray menu

    @Test func menuIdle() {
        let state = BeamerMenuState.parse(titles: ["Beamer 1.5.18", "Idle", "Send input to Studio PC", "Pause crossing", "This Mac drives other machines", "Settings…", "Quit Beamer"])
        #expect(state.version == "1.5.18")
        #expect(state.link == .idle)
        #expect(state.paused == false)
        #expect(state.targets == ["Studio PC"])
        #expect(state.canSend)
    }

    @Test func menuDrivingAndDriven() {
        #expect(BeamerMenuState.parse(titles: ["Beamer 1.5.18", "Driving Studio PC", "Return input to Mac", "Pause crossing"]).link == .driving("Studio PC"))
        #expect(BeamerMenuState.parse(titles: ["Beamer 1.5.18", "Driven by Mac mini", "Pause crossing"]).link == .drivenBy("Mac mini"))
    }

    @Test func menuPausedAndSingleMachine() {
        let state = BeamerMenuState.parse(titles: ["Beamer 1.5.18", "Idle", "Send input", "Resume crossing"])
        #expect(state.paused == true)
        #expect(state.canSend && state.targets.isEmpty)
        #expect(BeamerMenuState.parse(titles: ["missing value", ""]).paused == nil)
    }

    @Test func scriptOutputSplitsIntoTitles() {
        #expect(BeamerScripts.titles(fromOutput: "Beamer 1.5.18\nIdle\n\nPause crossing\n") == ["Beamer 1.5.18", "Idle", "Pause crossing"])
        #expect(BeamerScripts.click(title: "Send input to \"Tony's\" PC").contains("click menu item \"Send input to \\\"Tony's\\\" PC\""))
        #expect(BeamerScripts.menuTitles.contains("menu bar 2 of process \"Beamer\""))
    }

    // MARK: Names

    @Test func matchesSpokenNames() {
        let names = ["Tony's iPhone", "Studio PC", "Mac mini"]
        #expect(BeamerMatching.machine(named: "my studio pc", in: names) == "Studio PC")
        #expect(BeamerMatching.machine(named: "the mac mini", in: names) == "Mac mini")
        #expect(BeamerMatching.machine(named: "iphone", in: names) == "Tony's iPhone")
        #expect(BeamerMatching.machine(named: "toaster", in: names) == nil)
        #expect(BeamerMatching.isIPad("my iPad") && !BeamerMatching.isIPad("iPhone"))
    }

    // MARK: Client

    final class FakeEnvironment: BeamerEnvironment, @unchecked Sendable {
        var isInstalled = true, isRunning = true, accessibilityGranted = true
        var settings: Data? = Data(BeamerTests.settingsJSON.utf8)
        var socketAnswers = true
        var menu = "Beamer 1.5.18\nIdle\nSend input to Studio PC\nSend input to Mac mini\nPause crossing\n"
        var scripts: [String] = []
        var launched: [Bool] = []
        func settingsData() -> Data? { settings }
        func sendToSocket(_ payload: Data) -> Bool { socketAnswers }
        func runScript(_ source: String) -> String? {
            scripts.append(source)
            return source.contains("name of every menu item") ? menu : ""
        }
        func launch(window: Bool) -> Bool { launched.append(window); return true }
    }

    @Test func notInstalled() {
        let env = FakeEnvironment(); env.isInstalled = false
        let client = BeamerClient(environment: env)
        #expect(client.status() == .missing)
        #expect(client.status().headline == "Beamer is not installed")
        let outcome = client.perform(.pause)
        #expect(!outcome.ok && outcome.message.contains("isn't installed"))
    }

    @Test func notRunningStillListsPairedMachines() {
        let env = FakeEnvironment(); env.isRunning = false
        let client = BeamerClient(environment: env)
        let status = client.status()
        #expect(status.availability == .notRunning)
        #expect(status.machines.count == 3)
        #expect(status.headline == "Beamer is not running · 3 paired")
        #expect(!client.perform(.pause).ok)
        #expect(client.perform(.start).ok && env.launched == [false])
        #expect(client.perform(.showWindow).ok && env.launched == [false, true])
    }

    @Test func needsAccessibility() {
        let env = FakeEnvironment(); env.accessibilityGranted = false
        let client = BeamerClient(environment: env)
        #expect(client.status().availability == .needsPermission)
        #expect(client.status().isRunning)
        #expect(env.scripts.isEmpty)
        let outcome = client.perform(.pause)
        #expect(!outcome.ok && outcome.message.contains("Accessibility"))
        // The window needs no permission: the socket answers.
        #expect(client.perform(.showWindow).ok)
    }

    @Test func readsLiveStatus() {
        let env = FakeEnvironment(); env.menu = "Beamer 1.5.18\nDriving Studio PC\nReturn input to Mac\nResume crossing\n"
        let status = BeamerClient(environment: env).status()
        #expect(status.availability == .ready && status.version == "1.5.18")
        #expect(status.link == .driving("Studio PC") && status.isCrossed)
        #expect(status.paused == true)
        #expect(status.headline == "Crossing is paused")
    }

    @Test func pauseAndResumeClickTheRightItem() {
        let env = FakeEnvironment()
        let client = BeamerClient(environment: env)
        #expect(client.perform(.pause).ok)
        #expect(env.scripts.last?.contains("click menu item \"Pause crossing\"") == true)
        // Already running: resume does nothing.
        let before = env.scripts.count
        #expect(client.perform(.resume).message == "Crossing isn't paused.")
        #expect(env.scripts.count == before + 1) // only the menu read
        env.menu = "Beamer 1.5.18\nIdle\nResume crossing\n"
        #expect(client.perform(.resume).ok)
        #expect(env.scripts.last?.contains("click menu item \"Resume crossing\"") == true)
    }

    @Test func switchesToANamedMachine() {
        let env = FakeEnvironment()
        let client = BeamerClient(environment: env)
        #expect(client.perform(.switchTo("my studio pc")).ok)
        #expect(env.scripts.last?.contains("click menu item \"Send input to Studio PC\"") == true)
        let unknown = client.perform(.switchTo("toaster"))
        #expect(!unknown.ok && unknown.message.contains("Studio PC, Mac mini"))
    }

    @Test func anIPadIsNotABeamerMachine() {
        let outcome = BeamerClient(environment: FakeEnvironment()).perform(.switchTo("my iPad"))
        #expect(!outcome.ok && outcome.message.contains("Universal Control"))
    }

    @Test func returnHomeOnlyWhenCrossed() {
        let env = FakeEnvironment()
        let client = BeamerClient(environment: env)
        #expect(client.perform(.returnHome).message == "Input is already on this Mac.")
        env.menu = "Beamer 1.5.18\nDriving Studio PC\nReturn input to Mac\nPause crossing\n"
        #expect(client.perform(.returnHome).ok)
        #expect(env.scripts.last?.contains("click menu item \"Return input to Mac\"") == true)
    }

    @Test func showWindowFallsBackToLaunchWhenTheSocketIsDead() {
        let env = FakeEnvironment(); env.socketAnswers = false
        #expect(BeamerClient(environment: env).perform(.showWindow).ok)
        #expect(env.launched == [true])
    }

    // MARK: Continuity tab

    @Test func continuityTabIsLastAndOffByDefault() {
        #expect(TopBarTab.allCases.firstIndex(of: .continuity)! > TopBarTab.allCases.firstIndex(of: .usage)!) // appended after the original tabs (later tabs, such as Waves, come after it)
        #expect(TopBarTab.continuity.symbol == "rectangle.connected.to.line.below")
        #expect(!TopBarLayout.defaultRow.contains(.continuity))
        #expect(!TopBarLayout.standard.contains(.continuity))
        var layout = TopBarLayout.standard
        layout.toggle(.continuity)
        #expect(layout.tabs.last == .continuity)
        // A layout saved before the tab existed does not gain it.
        let saved = TopBarLayout.decode(TopBarLayout.standard.encoded(), known: TopBarLayout.knownEncoded())
        #expect(!saved.contains(.continuity))
    }

    // MARK: Voice

    @Test func parsesBeamerPhrases() {
        #expect(FastIntent.parse("pause Beamer") == .beamer(.pause))
        #expect(FastIntent.parse("Hey Zeus, pause beamer please") == .beamer(.pause))
        #expect(FastIntent.parse("resume Beamer") == .beamer(.resume))
        #expect(FastIntent.parse("start Beamer") == .beamer(.start))
        #expect(FastIntent.parse("open Beamer") == .beamer(.showWindow))
        #expect(FastIntent.parse("bring my keyboard back") == .beamer(.returnHome))
        #expect(FastIntent.parse("switch to my iPad") == .beamer(.switchTo("iPad")))
        #expect(FastIntent.parse("switch to my studio pc") == .beamer(.switchTo("studio pc")))
        #expect(FastIntent.parse("send my keyboard to my Mac mini") == .beamer(.switchTo("Mac mini")))
        #expect(FastIntent.parse("go to the iPad") == .beamer(.switchTo("iPad")))
        #expect(FastIntent.parse("pause Beamer")?.intentLabel == "beamer")
    }

    @Test func beamerPhrasesLeaveOtherCommandsAlone() {
        // "switch to Safari" is still an app switch; "pause" alone is still the music.
        #expect(FastIntent.parse("switch to Safari") == .openApp("Safari", website: nil))
        #expect(FastIntent.parse("pause") == .media(.pause))
        #expect(FastIntent.parse("open Spotify") != nil)
        if case .beamer = FastIntent.parse("open Spotify") { Issue.record("Spotify is not Beamer") }
    }
}
