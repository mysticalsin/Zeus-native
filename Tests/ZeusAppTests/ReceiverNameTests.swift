import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Receiver names")
struct ReceiverNameTests {
    @Test func foundReceiversAppearInTheOutputMenuAndStoppingClearsThem() {
        let browser = ReceiverNameBrowser(live: false)
        browser.setEnabled(true)
        #expect(!browser.isBrowsing)
        browser.note(name: "Kitchen", type: "_airplay._tcp.")
        browser.note(name: "AABBCC@Bedroom", type: "_raop._tcp")
        let rows = OutputDeviceMenuRows.receivers(browser.names)
        #expect(rows.map(\.name) == ["Kitchen", "Bedroom"])
        #expect(rows.allSatisfy { $0.symbol == "airplayaudio" && !$0.selectable })
        browser.setEnabled(false)
        #expect(browser.names.isEmpty)
        #expect(!browser.isBrowsing)
    }
}
