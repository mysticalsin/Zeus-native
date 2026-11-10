import Testing
@testable import Zeus

@Suite("R24 settings debug")
struct R24AppTests {
    @Test func openSettingsAcceptsEverySectionIdAndAlias() {
        for section in GSSection.allCases {
            #expect(GSSection.matching(section.rawValue) == section)
            #expect(GSSection.matching(section.title) == section)
            #expect(GSSection.matching(section.rawValue.uppercased()) == section)
        }
        #expect(GSSection.matching("topBar") == .appearance)
        #expect(GSSection.matching("todo") == .features)
        #expect(GSSection.matching("memory") == .features)
        #expect(GSSection.matching("teleprompter") == .beamer)
        #expect(GSSection.matching("no such page") == nil)
    }
}
