import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// The open panel eases between heights when the page changes, and the old page fades out fast instead of cutting.
@Suite("Panel resize motion")
@MainActor
struct PanelResizeMotionTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Zeus")
    private static func text(_ path: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theHeightKeyIsTheOpenPanelHeightOrNil() {
        let home = NotchView.topBarPanelSize(barHeight: 32, hasApproval: false, home: true).height
        let calendar = NotchView.topBarPanelSize(barHeight: 32, hasApproval: false, home: false).height
        #expect(home != calendar)
        #expect(NotchView.panelHeightKey(presentation: .panel, panelHeight: home) == home)
        #expect(NotchView.panelHeightKey(presentation: .panel, panelHeight: calendar) == calendar)
        #expect(NotchView.panelHeightKey(presentation: .closed, panelHeight: home) == nil)
        #expect(NotchView.panelHeightKey(presentation: .peek, panelHeight: home) == nil)
    }

    @Test func aTabChangeAnimatesTheHeightWithThePageSpring() throws {
        let source = try Self.text("Notch/NotchView.swift")
        #expect(source.contains(".animation(TopBarStyle.pageSpring, value: panelHeightKey)"))
        // It sits outside the open-height animation, which stays innermost and so wins on open.
        let openHeight = try #require(source.range(of: "value: model.shownHeight)"))
        let resize = try #require(source.range(of: "value: panelHeightKey)"))
        #expect(openHeight.upperBound < resize.lowerBound)
    }

    @Test func theOldPageFadesOutInsteadOfCutting() throws {
        let source = try Self.text("TopBar/TopBarViews.swift")
        #expect(source.contains("Motion.pageOut"))
        #expect(!source.contains("removal: .identity))\n        .id(topBar.selectedTab)"))
    }
}
