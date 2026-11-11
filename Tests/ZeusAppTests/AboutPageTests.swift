import Testing
@testable import Zeus

@Suite("About page")
struct AboutPageTests {
    @Test func versionLineUsesPlistValues() {
        #expect(AboutInfo.versionLine(short: "0.1.0", build: "1") == "Version 0.1.0 (1)")
        #expect(AboutInfo.versionLine(short: "0.1.0", build: nil) == "Version 0.1.0")
        #expect(AboutInfo.versionLine(short: nil, build: nil) == "Development build")
    }

    @Test func sectionIsRegisteredInTheAppGroup() {
        #expect(GSSection.about.title == "About")
        #expect(GSSection.about.group == .app)
        #expect(GSSection.matching("about") == .about)
        #expect(GSSection.matching("about you") == .features)
    }

    @Test func githubLinkIsThePublicRepo() {
        #expect(AboutLinks.github?.absoluteString == "https://github.com/mysticalsin/Zeus-native")
        #expect(AboutLinks.linkedIn == nil)
    }
}
