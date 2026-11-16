import AppKit
import Foundation
import Testing
@testable import Zeus

/// Structure checks for layout fixes that cannot be unit tested without opening a window.
@Suite("UI polish source")
struct UIPolishSourceTests {
    static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func thePermissionCueWrapsInsteadOfTruncatingMidWord() throws {
        let text = try Self.source("Sources/Zeus/TopBar/TopBarViews.swift")
        let start = try #require(text.range(of: "case .permission(let text, let pane):"))
        let block = String(text[start.upperBound...].prefix(900))
        #expect(block.contains("lineLimit(2)"))
        #expect(!block.contains("lineLimit(1)"))
    }

    @Test @MainActor func aSettingsPopupIsWideEnoughForItsLongestOption() {
        #expect(GSPopup.width(for: ["Fastest", "Best"]) == GSPopup.minWidth)
        #expect(GSPopup.width(for: []) == GSPopup.minWidth)
        let long = GSPopup.width(for: ["Fastest", "Automatic (best working voice)"])
        let needed = ("Automatic (best working voice)" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14.5)]).width
        #expect(long > GSPopup.minWidth)
        #expect(long >= needed + 20)
        #expect(GSPopup.width(for: [String(repeating: "W", count: 80)]) == GSPopup.maxWidth)
    }

    @Test func theOnboardingColumnIsPinnedTopLeadingEvenWithoutAVisual() throws {
        let text = try Self.source("Sources/Zeus/Onboarding/OnboardingSteps.swift")
        let start = try #require(text.range(of: "column\n"))
        let block = String(text[start.upperBound...].prefix(700))
        let pin = try #require(block.range(of: ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        let offset = try #require(block.range(of: ".offset(x: OB.contentX, y: OB.headingTopY)"))
        #expect(pin.lowerBound < offset.lowerBound)
    }
}
