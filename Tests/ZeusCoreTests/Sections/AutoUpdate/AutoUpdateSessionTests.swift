import Foundation
import Testing
@testable import ZeusCore

/// R-022. Update actions stay off until a secure feed and a public key are configured, and a bad signature never installs.
@Suite("Updates session")
struct AutoUpdateSessionTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let publicKey = Data(repeating: 2, count: 32).base64EncodedString()
    private static let now = Date(timeIntervalSince1970: 1_763_683_200)

    @Test func anUpdateWithoutAValidSignatureDoesNotInstall() {
        let context = Self.context()
        let missing = Self.candidate("2.0.0", signature: "")
        var state = UpdateSession.initial(context)
        var step = UpdateSession.reduce(state, .checkRequested, context)
        state = step.state
        #expect(state == .checking)
        step = UpdateSession.reduce(state, .checkOffer(missing), context)
        #expect(step.state == .failed(.signature))
        #expect(step.effects.isEmpty)
        step = UpdateSession.reduce(step.state, .installRequested, context)
        #expect(step.state == .failed(.signature))
        #expect(!step.effects.contains(.install))
        #expect(!step.effects.contains(.relaunch))

        let presented = Self.candidate("2.0.0", signature: "not-a-real-signature")
        state = .verifying(presented)
        step = UpdateSession.reduce(state, .verifyFinished(.invalid), context)
        #expect(step.state == .failed(.signature))
        #expect(step.effects == [.discardStagedUpdate])
        step = UpdateSession.reduce(.verifying(presented), .verifyFinished(.missing), context)
        #expect(step.state == .failed(.signature))
        #expect(!step.effects.contains(.install))
        #expect(!step.effects.contains(.relaunch))
        #expect(UpdateInstallGate.replacesInstalledApp(.refuse, duringTests: true) == false)
    }

    @Test func automaticChecksAreOffAndTheMachineStartsDisabled() throws {
        #expect(UpdateConfiguration().automaticChecks == false)
        #expect(UpdateSession.initial(Self.context(automatic: false)) == .disabled)
        #expect(UpdateSession.initial(Self.context(automatic: true)) == .idle)
        let catalog = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let line = catalog.split(separator: "\n").first { $0.contains("\"about.autoUpdate\"") }
        #expect(line?.contains("defaultValue: \"false\"") == true)
        #expect(UpdateConfiguration.automaticChecksKey == "about.autoUpdate")
        #expect(UpdateConfiguration.feedURLKey == "about.updateFeedURL")
        #expect(UpdateConfiguration.checkNowKey == "about.checkNow")
        #expect(UpdateConfiguration.publicKeyInfoKey == "SUPublicEDKey")
    }

    @Test func aMissingKeyOrInsecureFeedDoesNothing() {
        for key in ["", "   ", Data(repeating: 9, count: 64).base64EncodedString(), "not-base64"] {
            let configuration = UpdateConfiguration(automaticChecks: true, feedURL: "https://updates.example.com/appcast.xml", publicKey: key)
            #expect(!configuration.isConfigured)
            let context = Self.context(configuration: configuration)
            #expect(UpdateSession.initial(context) == .disabled)
            let step = UpdateSession.reduce(.disabled, .checkRequested, context)
            #expect(step.state == .disabled)
            #expect(step.effects.isEmpty)
            let card = UpdatesCard.model(state: step.state, context: context, lastChecked: nil, confirmingInstall: false)
            #expect(card.status.contains("not configured"))
        }
        for feed in ["http://updates.example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:pass@updates.example.com/appcast.xml", ""] {
            let configuration = UpdateConfiguration(automaticChecks: true, feedURL: feed, publicKey: Self.publicKey)
            #expect(!configuration.isConfigured)
            let step = UpdateSession.reduce(.disabled, .checkRequested, Self.context(configuration: configuration))
            #expect(step.effects.isEmpty)
        }
        let resolved = UpdateConfiguration.resolve(
            automaticChecks: false,
            info: ["SUPublicEDKey": Self.publicKey, "SUFeedURL": "https://updates.example.com/appcast.xml"]
        )
        #expect(resolved.isConfigured)
        #expect(resolved.automaticChecks == false)
        let pinned = UpdateConfiguration.resolve(
            automaticChecks: false,
            info: [
                "SUPublicEDKey": Self.publicKey,
                "SUFeedURL": "https://updates.example.com/bundled.xml",
                "about.updateFeedURL": "https://evil.example/appcast.xml",
            ]
        )
        #expect(pinned.secureFeedURL?.absoluteString == "https://updates.example.com/bundled.xml")
    }

    @Test func networkDowngradeAndSkippedVerificationNeverInstall() {
        let context = Self.context()
        let candidate = Self.candidate("2.0.0")
        var step = UpdateSession.reduce(.checking, .checkFailed(.network), context)
        #expect(step.state == .failed(.network))
        #expect(step.effects.isEmpty)
        #expect(step.recordCheck)

        step = UpdateSession.reduce(.checking, .checkOffer(Self.candidate("0.9.0")), context)
        #expect(step.state == .failed(.downgrade))
        #expect(!step.effects.contains(.download(candidate.downloadURL)))
        #expect(!step.effects.contains(.install))

        step = UpdateSession.reduce(.checking, .checkOffer(Self.candidate("1.0.0")), context)
        #expect(step.state == .upToDate)
        #expect(step.effects.isEmpty)

        step = UpdateSession.reduce(.available(candidate), .verifyFinished(.valid), context)
        #expect(step.state == .available(candidate))
        #expect(step.effects.isEmpty)
        step = UpdateSession.reduce(.available(candidate), .installRequested, context)
        #expect(step.state == .available(candidate))
        #expect(!step.effects.contains(.install))

        step = UpdateSession.reduce(.downloading(candidate), .installRequested, context)
        #expect(step.state == .downloading(candidate))
        #expect(step.effects.isEmpty)
    }

    @Test func testsNeverReplaceTheInstalledApp() {
        let candidate = Self.candidate("2.0.0")
        let tests = Self.context(duringTests: true, disposableCopy: false)
        let ready = UpdateSessionState.readyToInstall(candidate)
        let refused = UpdateSession.reduce(ready, .installRequested, tests)
        #expect(refused.state == .failed(.installRefused))
        #expect(refused.effects.isEmpty)
        #expect(UpdateInstallGate.decision(signatureValid: true, versionIsNewer: true, duringTests: true, disposableCopy: false) == .refuse)
        #expect(UpdateInstallGate.replacesInstalledApp(.refuse, duringTests: true) == false)
        #expect(UpdateInstallGate.outcome(decision: .refuse, succeeded: false, duringTests: true) == .leftInPlace)

        let copy = Self.context(duringTests: true, disposableCopy: true)
        let started = UpdateSession.reduce(ready, .installRequested, copy)
        #expect(started.state == .installing(candidate))
        #expect(started.effects == [.install])
        #expect(UpdateInstallGate.replacesInstalledApp(.replaceDisposableCopy, duringTests: true) == false)
        let finished = UpdateSession.reduce(started.state, .installFinished(true), copy)
        #expect(!finished.effects.contains(.relaunch))
        #expect(UpdateInstallGate.outcome(decision: .replaceDisposableCopy, succeeded: true, duringTests: true) == .replacedDisposableCopy)

        let production = Self.context(duringTests: false)
        let installing = UpdateSession.reduce(ready, .installRequested, production)
        #expect(installing.effects == [.install])
        let relaunch = UpdateSession.reduce(installing.state, .installFinished(true), production)
        #expect(relaunch.effects == [.relaunch])
        let rolled = UpdateSession.reduce(installing.state, .installFinished(false), production)
        #expect(rolled.state == .failed(.installFailed))
        #expect(rolled.effects == [.rollback])
        #expect(UpdateInstallGate.outcome(decision: .replaceRunningApp, succeeded: false, duringTests: false) == .rolledBack)
        #expect(UpdateHosts.select(duringTests: true, disposableCopyPath: nil, runningBundlePath: "/Applications/Zeus.app") == .refuse)
        #expect(UpdateHosts.select(duringTests: true, disposableCopyPath: "/Applications/Zeus.app", runningBundlePath: "/Applications/Zeus.app") == .refuse)
        #expect(UpdateHosts.select(duringTests: true, disposableCopyPath: "/tmp/Zeus-copy.app", runningBundlePath: "/Applications/Zeus.app") == .disposableCopy("/tmp/Zeus-copy.app"))
        #expect(UpdateHosts.select(duringTests: false, disposableCopyPath: nil, runningBundlePath: "/Applications/Zeus.app") == .runningApp)
    }

    @Test func guardedTransitionsStayOnThePath() {
        let context = Self.context()
        let candidate = Self.candidate("2.0.0")
        let armed = UpdateSession.reduce(.disabled, .setAutomaticChecks(true), context)
        #expect(armed.state == .idle)
        #expect(armed.effects == [.armAutomaticChecks])
        #expect(!armed.effects.contains(.fetchFeed))
        let commands = UpdateCommands.events(forAutomaticChecks: true, configured: true)
        #expect(commands == [.setAutomaticChecks(true), .checkRequested])
        #expect(UpdateCommands.events(forAutomaticChecks: true, configured: false).isEmpty)
        #expect(UpdateCommands.events(forAutomaticChecks: false, configured: true) == [.setAutomaticChecks(false)])

        var state = UpdateSessionState.idle
        var step = UpdateSession.reduce(state, .checkRequested, context)
        #expect(step.state == .checking)
        #expect(step.effects == [.fetchFeed])
        state = step.state
        step = UpdateSession.reduce(state, .checkOffer(candidate), context)
        #expect(step.state == .available(candidate))
        #expect(step.recordCheck)
        #expect(step.effects.isEmpty)
        state = step.state
        step = UpdateSession.reduce(state, .downloadRequested, context)
        #expect(step.state == .downloading(candidate))
        #expect(step.effects == [.download(candidate.downloadURL)])
        state = step.state
        step = UpdateSession.reduce(state, .downloadFinished, context)
        #expect(step.state == .verifying(candidate))
        #expect(step.effects == [.verify])
        state = step.state
        step = UpdateSession.reduce(state, .verifyFinished(.valid), context)
        #expect(step.state == .readyToInstall(candidate))
        #expect(!step.effects.contains(.install))
        let cancelled = UpdateSession.reduce(.checking, .setAutomaticChecks(false), context)
        #expect(cancelled.state == .disabled)
        #expect(cancelled.effects == [.cancelNetwork])
        let ignored = UpdateSession.reduce(.idle, .downloadFinished, context)
        #expect(ignored.state == .idle)
        #expect(ignored.effects.isEmpty)
        let insecure = Self.candidate("2.0.0", url: "http://updates.example.com/Zeus.zip")
        let blocked = UpdateSession.reduce(.checking, .checkOffer(insecure), context)
        #expect(blocked.state == .failed(.insecureFeed))
        #expect(blocked.effects.isEmpty)
    }

    @Test func installIsUnreachableUnlessTheUpdateIsNewerSignedAndAllowed() {
        let versions = [0, 1, 2].flatMap { major in
            [0, 1].flatMap { minor in
                [0, 1].map { ZeusVersion(major: major, minor: minor, patch: $0) }
            }
        }
        let verdicts: [UpdateSignatureVerdict] = [.valid, .invalid, .missing]
        for current in versions {
            for offered in versions {
                for verdict in verdicts {
                    for configured in [false, true] {
                        for duringTests in [false, true] {
                            let effects = Self.attempt(
                                current: current,
                                offered: offered,
                                verdict: verdict,
                                configured: configured,
                                duringTests: duringTests,
                                disposableCopy: false
                            )
                            let newer = offered > current
                            let allowed = configured && newer && verdict == .valid && !duringTests
                            #expect(effects.contains(.install) == allowed)
                            #expect(!effects.contains(.relaunch) || allowed)
                            if !configured || !newer || verdict != .valid || duringTests {
                                #expect(!effects.contains(.install))
                                #expect(!effects.contains(.relaunch))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func releaseBoundariesAndTheFeedParserFailClosed() throws {
        #expect(UpdateVersions.release("1.2.3") == ZeusVersion(major: 1, minor: 2, patch: 3))
        #expect(UpdateVersions.release("1.2") == ZeusVersion(major: 1, minor: 2, patch: 0))
        #expect(UpdateVersions.release(" 1.2.0 ") == ZeusVersion(major: 1, minor: 2, patch: 0))
        for raw in ["", "1.2.3.4", "1.2.3-beta", "v1.2.3", "1..2", "1.2.a", "-1.0.0", "1.0.0 "] {
            if raw == "1.0.0 " { continue }
            #expect(UpdateVersions.release(raw) == nil)
        }
        #expect(UpdateVersions.release("1.0.0 ") == ZeusVersion(major: 1, minor: 0, patch: 0))

        let json = Data(#"{"version":"1.4.0","downloadURL":"https://updates.example.com/Zeus.zip","edSignature":"abc","notes":["Faster start","A fix"]}"#.utf8)
        let parsed = try #require(try UpdateFeedDocument.candidates(from: json).get())
        #expect(parsed.count == 1)
        #expect(parsed[0].notes == ["Faster start", "A fix"])
        #expect(parsed[0].version == ZeusVersion(major: 1, minor: 4, patch: 0))

        let appcast = Data("""
        <rss><channel>
        <item><sparkle:shortVersionString>1.5.0</sparkle:shortVersionString>
        <enclosure url="https://updates.example.com/old.zip" sparkle:edSignature="old" sparkle:shortVersionString="1.5.0"/></item>
        <item><sparkle:version>2.0.0-beta</sparkle:version>
        <enclosure url="https://updates.example.com/beta.zip" sparkle:edSignature="beta" sparkle:version="2.0.0-beta"/></item>
        <item><title>2.0.0</title><description><![CDATA[<ul><li>Notes stay on this Mac</li><li>Second line</li></ul>]]></description>
        <enclosure url="http://updates.example.com/plain.zip" sparkle:edSignature="bad" sparkle:shortVersionString="1.1.0"/>
        <enclosure url="https://updates.example.com/Zeus.zip" sparkle:edSignature="good" sparkle:shortVersionString="2.0.0"/></item>
        </channel></rss>
        """.utf8)
        let items = try #require(try UpdateFeedDocument.candidates(from: appcast).get())
        let best = try #require(UpdateFeedDocument.best(items))
        #expect(best.version == ZeusVersion(major: 2, minor: 0, patch: 0))
        #expect(best.edSignature == "good")
        #expect(best.downloadURL.scheme == "https")
        #expect(best.notes == ["Notes stay on this Mac", "Second line"])
        #expect(items.contains { $0.version == ZeusVersion(major: 1, minor: 5, patch: 0) })
        #expect(!items.contains { $0.edSignature == "beta" })

        #expect(UpdateFeedDocument.candidates(from: Data()) == .failure(.unreadable))
        let huge = Data(repeating: 0x20, count: UpdateFeedPolicy.maximumFeedBytes + 1)
        #expect(UpdateFeedDocument.candidates(from: huge) == .failure(.unreadable))
        #expect(UpdateFeedDocument.candidates(from: Data("not a feed".utf8)) == .failure(.unreadable))
    }

    @Test func anInsecureFeedIsNotRequested() async {
        let insecure = try! #require(URL(string: "http://updates.example.com/appcast.xml"))
        let result = await UpdateFeedTransport.load(insecure)
        #expect(result == .failure(.insecureFeed))
        let file = try! #require(URL(string: "file:///etc/hosts"))
        #expect(await UpdateFeedTransport.load(file) == .failure(.insecureFeed))
    }

    @Test func theCardShowsVersionNotesAndEveryHelper() {
        let context = Self.context()
        let candidate = Self.candidate("2.0.0", notes: ["One change"])
        let card = UpdatesCard.model(state: .available(candidate), context: context, lastChecked: Self.now, confirmingInstall: false)
        #expect(card.title == "Updates")
        #expect(card.panelPadding == 32)
        #expect(card.cardSpacing == 28)
        #expect(card.rowHeight == 52)
        #expect(card.rows.allSatisfy { !$0.helper.isEmpty && $0.keyboardReachable && !$0.accessibilityLabel.isEmpty })
        #expect(card.rows.map(\.id).contains("about.autoUpdate"))
        #expect(card.rows.map(\.id).contains("about.checkNow"))
        #expect(card.notes == ["One change"])
        #expect(card.preview.accessibilityLabel.contains("2.0.0") || card.preview.versionLine.contains("2.0.0"))
        let quiet = Self.context(reduceMotion: true)
        let loading = UpdatesCard.model(state: .checking, context: quiet, lastChecked: nil, confirmingInstall: false)
        #expect(loading.animationDuration == 0)
        #expect(loading.showsIndeterminateMotion == false)
        #expect(loading.phase == .loading)
        let moving = UpdatesCard.model(state: .checking, context: context, lastChecked: nil, confirmingInstall: false)
        #expect(moving.animationDuration > 0)
        #expect(moving.showsIndeterminateMotion)
        let empty = UpdatesCard.model(state: .upToDate, context: context, lastChecked: nil, confirmingInstall: false)
        #expect(!empty.notesEmpty.isEmpty)
        #expect(empty.notes.isEmpty)
        let failed = UpdatesCard.model(state: .failed(.signature), context: context, lastChecked: Self.now, confirmingInstall: false)
        #expect(failed.phase == .error)
        #expect(failed.status.contains("signature"))
        let checked = card.rows.first { $0.id == "updates.lastChecked" }
        #expect(checked?.control == .text(UpdateClock.checkedLine(Self.now)) || card.rows.contains { row in
            if case .text(let value) = row.control, row.id == "updates.lastChecked" { return value == UpdateClock.checkedLine(Self.now) }
            return false
        })
        #expect(UpdateClock.checkedLine(nil) == "Not checked yet.")
        let prompt = UpdatesCard.installPrompt(state: .readyToInstall(candidate), confirming: true)
        #expect(prompt == .confirm(version: "2.0.0"))
        #expect(UpdatesCard.installPrompt(state: .available(candidate), confirming: true) == .hidden)
    }

    @Test func theUpdatesCardStaysOnAboutAndDoesNotOpenAWindow() throws {
        #expect(AutoUpdateSectionSlot.descriptor.id == "glass.autoUpdate")
        #expect(AutoUpdateSectionSlot.descriptor.title == "Auto-update")
        #expect(AutoUpdateSectionSlot.descriptor.filled)
        #expect(AutoUpdateSectionSlot.descriptor.keys.isEmpty)
        #expect(AutoUpdateSectionSlot.descriptor.placement == .cardOn(.about, 1))
        #expect(AutoUpdateSectionSlot.cardTitle == "Updates")
        let section = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/AutoUpdateSettingsSection.swift"), encoding: .utf8)
        let folder = Self.root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate")
        var text = section
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "swift" {
                text += try String(contentsOf: file, encoding: .utf8)
            }
        }
        #expect(text.contains("accessibilityLabel"))
        #expect(text.contains("animationDuration") || text.contains("reduceMotion"))
        #expect(!text.contains("NSWindow("))
        #expect(!text.contains(".sheet("))
    }

    @Test func theRepositoryDoesNotContainAnUpdatePrivateKey() throws {
        let plist = try String(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        #expect(!plist.contains("SUPrivate"))
        #expect(!plist.contains("BEGIN PRIVATE"))
        let folders = [
            "Sources/ZeusCore/Settings/Sections/AutoUpdate",
            "Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate",
        ]
        let banned = ["BEGIN PRIVATE KEY", "BEGIN OPENSSH PRIVATE KEY", "SUPrivateEDKey"]
        for folder in folders {
            let url = Self.root.appendingPathComponent(folder)
            guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for word in banned {
                    #expect(!text.contains(word))
                }
            }
        }
    }

    private static func attempt(
        current: ZeusVersion,
        offered: ZeusVersion,
        verdict: UpdateSignatureVerdict,
        configured: Bool,
        duringTests: Bool,
        disposableCopy: Bool
    ) -> [UpdateEffect] {
        let configuration = UpdateConfiguration(
            automaticChecks: false,
            feedURL: configured ? "https://updates.example.com/appcast.xml" : "",
            publicKey: configured ? publicKey : ""
        )
        let context = UpdateContext(
            configuration: configuration,
            currentVersion: current,
            duringTests: duringTests,
            disposableCopy: disposableCopy,
            now: now,
            reduceMotion: false,
            acceptsUpdates: true
        )
        var effects: [UpdateEffect] = []
        var state = UpdateSession.initial(context)
        let check = UpdateSession.reduce(state, .checkRequested, context)
        state = check.state
        effects += check.effects
        guard state == .checking else { return effects }
        let signature = verdict == .missing ? "" : "signature"
        let offer = UpdateSession.reduce(state, .checkOffer(candidate(offered, signature: signature)), context)
        state = offer.state
        effects += offer.effects
        guard case .available = state else { return effects }
        let download = UpdateSession.reduce(state, .downloadRequested, context)
        state = download.state
        effects += download.effects
        guard case .downloading = state else { return effects }
        let finished = UpdateSession.reduce(state, .downloadFinished, context)
        state = finished.state
        effects += finished.effects
        let verified = UpdateSession.reduce(state, .verifyFinished(verdict), context)
        state = verified.state
        effects += verified.effects
        guard case .readyToInstall = state else { return effects }
        let install = UpdateSession.reduce(state, .installRequested, context)
        state = install.state
        effects += install.effects
        guard case .installing = state else { return effects }
        let done = UpdateSession.reduce(state, .installFinished(true), context)
        effects += done.effects
        return effects
    }

    private static func context(
        automatic: Bool = false,
        configuration: UpdateConfiguration? = nil,
        duringTests: Bool = true,
        disposableCopy: Bool = false,
        reduceMotion: Bool = false
    ) -> UpdateContext {
        let resolved = configuration ?? UpdateConfiguration(
            automaticChecks: automatic,
            feedURL: "https://updates.example.com/appcast.xml",
            publicKey: publicKey
        )
        return UpdateContext(
            configuration: resolved,
            currentVersion: ZeusVersion(major: 1, minor: 0, patch: 0),
            duringTests: duringTests,
            disposableCopy: disposableCopy,
            now: now,
            reduceMotion: reduceMotion,
            acceptsUpdates: true
        )
    }

    private static func candidate(_ version: String, signature: String = "ed25519-signature", url: String = "https://updates.example.com/Zeus.zip", notes: [String] = []) -> UpdateCandidate {
        candidate(UpdateVersions.release(version)!, signature: signature, url: url, notes: notes)
    }

    private static func candidate(_ version: ZeusVersion, signature: String, url: String = "https://updates.example.com/Zeus.zip", notes: [String] = []) -> UpdateCandidate {
        UpdateCandidate(version: version, downloadURL: URL(string: url)!, edSignature: signature, notes: notes)
    }
}
