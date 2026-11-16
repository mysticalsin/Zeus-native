import Foundation
import Testing
import ZeusCore
import ZeusFling
@testable import Zeus

@MainActor
@Suite("Fling settings page")
struct FlingSettingsTests {
    private func model() -> TopBarModel { TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.fling-settings.\(UUID().uuidString)")!) }
    private func service(_ transport: FakeTransport, _ values: [String: String] = [:]) -> FlingService {
        FlingService(model: model(), transport: transport,
                     setting: { id in values[id] ?? (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
    }

    /// REG-684: Shelf is a section of the live Settings window, in Your tools, found by name.
    @Test func theShelfSectionIsInYourToolsAndFoundByName() {
        #expect(GSSection.shelf.group == .tools)
        #expect(GSSection.shelf.title == "Shelf")
        #expect(GSSection.shelf.symbol == "tray.fill")
        #expect(GSSection.matching("shelf") == .shelf)
        #expect(GSSection.matching("Shelf") == .shelf)
        #expect(GSSection.shown.contains(.shelf))
    }

    /// REG-684: Remove forgets the Mac, and a failure keeps it listed so nothing shows as removed that is not.
    @Test func removingAPairedMacForgetsItAndAFailureKeepsIt() {
        let transport = FakeTransport()
        let peer = FlingPairedPeer(id: "idB", name: "Mac B", model: "Mac15,3", pairedAt: Date(), lastSeen: Date())
        transport.paired = [peer]
        let service = service(transport)
        #expect(service.pairedMacs.map(\.id) == ["idB"])
        transport.removeFails = true
        #expect(!service.removePairedMac(id: "idB"))
        #expect(service.pairedMacs.map(\.id) == ["idB"])
        transport.removeFails = false
        #expect(service.removePairedMac(id: "idB"))
        #expect(service.pairedMacs.isEmpty)
    }

    /// REG-684: every Settings row reaches something that acts on it.
    @Test func theRowsReachTheServiceThatActsOnThem() {
        let transport = FakeTransport()
        let on = service(transport, ["fling.flickSensitivity": "High", "fling.openLinks": "false", "fling.papers": "true"])
        #expect(on.flickSensitivity == .high && !on.opensLinks && on.showsPapers)
        let off = service(transport, [:])
        #expect(off.flickSensitivity == .normal && off.opensLinks && !off.showsPapers)
        #expect(service(transport, ["fling.flickSensitivity": "Low"]).flickSensitivity == .low)
        #expect(service(transport, ["fling.flickSensitivity": "nonsense"]).flickSensitivity == .normal)
    }

    @Test func theLocalNetworkHelpPointsAtThePrivacyPane() {
        #expect(FlingService.localNetworkSettingsURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    }
}
