import Testing
@testable import ZeusCore

@Suite("Tab badges")
struct GlanceMetricsTests {
    @Test func badges() {
        #expect(TabBadge.text(0) == nil)
        #expect(TabBadge.text(-3) == nil)
        #expect(TabBadge.text(1) == "1")
        #expect(TabBadge.text(29) == "29")
        #expect(TabBadge.text(120) == "99+")
    }
}
