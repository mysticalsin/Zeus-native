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

    @Test func theFacePresenceHintIndentsToTheRowTitles() throws {
        let card = try Self.source("Sources/Zeus/Settings/GSFacePresenceCard.swift")
        #expect(card.contains(".padding(.leading, GS.rowIconColumn)"))
        let style = try Self.source("Sources/Zeus/Settings/GlanceSettingsStyle.swift")
        #expect(style.contains("frame(width: GS.rowIconColumn, alignment: .leading)"))
    }

    @Test func theNotchActionButtonTitleNeverWraps() throws {
        let text = try Self.source("Sources/Zeus/TopBar/TopBarViews.swift")
        let start = try #require(text.range(of: "struct NotchActionButton: View"))
        let block = String(text[start.upperBound...].prefix(700))
        #expect(block.contains(".lineLimit(1).fixedSize(horizontal: true, vertical: false)"))
    }

    @Test @MainActor func overlappedInitialDiscsKeepTwoCapitalsVisible() {
        for size: CGFloat in [16, 18] {
            let font = NSFont.systemFont(ofSize: ScribeInitialDisc.fontSize(size: size), weight: .bold)
            let width = ("MM" as NSString).size(withAttributes: [.font: font]).width
            let box = ScribeInitialDisc.textWidth(size: size)
            // The text box ends where the next disc begins, and even "MM" fits it at the 0.6 minimum scale.
            #expect(size / 2 + box / 2 <= size - ScribeInitialStack.overlap(size: size))
            #expect(width * 0.6 <= box)
        }
    }

    @Test func theCountdownScrimHidesTheScriptBehindTheDigit() throws {
        let text = try Self.source("Sources/Zeus/TopBar/TeleprompterPage.swift")
        #expect(text.contains("static let countdownScrimOpacity: Double = 0.92"))
        #expect(text.contains("Color.black.opacity(Self.countdownScrimOpacity)"))
        #expect(!text.contains("Color.black.opacity(0.55)"))
    }

    @Test @MainActor func theOpenPanelIgnoresThePointerLeavingWhileVoiceOverDrives() throws {
        #expect(NotchController.pointerExitKeepsPanelOpen(voiceOverOn: true))
        #expect(!NotchController.pointerExitKeepsPanelOpen(voiceOverOn: false))
        let text = try Self.source("Sources/Zeus/Notch/NotchController.swift")
        let exit = try #require(text.range(of: "guard outside else {"))
        let pin = try #require(text.range(of: "PolyglotPinPolicy.decide(.pointerExited", range: exit.upperBound..<text.endIndex))
        #expect(text[exit.upperBound..<pin.lowerBound].contains("Self.pointerExitKeepsPanelOpen(voiceOverOn: voiceOverProvider())"))
    }

    @Test func theClosedNotchIsNamedZeusAndOpensThePanelThroughAccessibility() throws {
        let view = try Self.source("Sources/Zeus/Notch/NotchView.swift")
        let body = try #require(view.range(of: ".ownedJourneyControl(\"notch.body\")"))
        let chain = String(view[..<body.lowerBound].suffix(700))
        #expect(chain.contains(".accessibilityElement(children: .contain)"))
        #expect(chain.contains(".accessibilityLabel(\"Zeus\")"))
        #expect(chain.contains(".accessibilityAction { openPanel?() }"))
        #expect(chain.contains("if model.presentation != .panel {"))
        #expect(chain.contains("Button(\"Open Zeus panel\") { openPanel?() }"))
        let controller = try Self.source("Sources/Zeus/Notch/NotchController.swift")
        #expect(controller.contains("openPanel: { [weak self] in self?.openFromAccessibility() }"))
        let open = try #require(controller.range(of: "func openFromAccessibility() {"))
        let opener = controller[open.upperBound...].prefix(420)
        #expect(opener.contains("guard !drawnNotch.isCalibrating else { return }"))
        #expect(opener.contains("show(.panel)"))
    }

    @Test func theSettingsDeepLinkOnlyOpensTheSettingsWindow() throws {
        let links = try Self.source("Sources/Zeus/App/DeepLinks.swift")
        let perform = try #require(links.range(of: "case .settings(let section):"))
        #expect(links[perform.upperBound...].prefix(80).contains("openSettings?(section)"))
        let delegate = try Self.source("Sources/Zeus/App/AppDelegate.swift")
        let wired = try #require(delegate.range(of: "DeepLinks.openSettings = { [weak self] section in"))
        #expect(delegate[wired.upperBound...].prefix(240).contains("self?.showSettings(GSSection.allCases.first"))
    }
}
