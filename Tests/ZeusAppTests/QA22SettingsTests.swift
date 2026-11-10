import SwiftUI
import Testing
@testable import Zeus

@Suite struct QA22SettingsTests {
    @Test func glanceSidebarHidesIPhoneUntilPairingExists() {
        #expect(GSSection.iPhonePairingAvailable == false)
        #expect(!GSSection.shown.contains(.iPhone))
        #expect(GSSection.shown.count == GSSection.allCases.count - 1)
        // Every other section stays in the sidebar, and every group still has items.
        let others = GSSection.allCases.filter { $0 != .iPhone }
        #expect(others.allSatisfy { $0.isShown })
        let shownGroups = Set(GSSection.shown.map(\.group))
        #expect(shownGroups == Set(GSSection.Group.allCases))
    }

    @Test @MainActor func iPhonePageIsNotEmpty() {
        let context = GSContext(services: OnboardingServices(permissions: PermissionsModel()))
        let view = GSPageView(section: .iPhone, navigation: GSNavigation(), context: context)
        let renderer = ImageRenderer(content: view.frame(width: 600, height: 400))
        renderer.scale = 1
        #expect(renderer.nsImage != nil)
    }
}
