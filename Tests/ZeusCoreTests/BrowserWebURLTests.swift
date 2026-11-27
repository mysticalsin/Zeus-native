import Testing
@testable import ZeusCore

@Suite struct BrowserWebURLTests {
    @Test func aMailLinkIsNotOpenedAsAPage() {
        #expect(WebAddress.page("mailto:user@example.com") == nil)
        #expect(WebAddress.page("about:blank.example") == nil)
        #expect(WebAddress.page("file:notes.txt") == nil)
        #expect(WebAddress.page("javascript:alert(1)") == nil)
        #expect(WebAddress.page("data:text/html,hi.example") == nil)
        #expect(WebAddress.page("example.com") == "https://example.com")
        #expect(WebAddress.page("example.com:8080") == "https://example.com:8080")
        #expect(WebAddress.page("localhost:3000") == "https://localhost:3000")
        #expect(WebAddress.page("https://example.com") == "https://example.com")
    }
}
