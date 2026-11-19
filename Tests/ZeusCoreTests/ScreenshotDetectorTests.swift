import Foundation
import Testing
@testable import ZeusCore

@Suite("ScreenshotDetector")
struct ScreenshotDetectorTests {
    @Test func detectsEnglishScreenshots() {
        #expect(ScreenshotDetector.isScreenshot(filename: "Screenshot 2026-11-02 at 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Screen Shot 2026-11-02 at 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Screenshot.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Screen Shot.jpg") == true)
    }

    @Test func detectsFrenchScreenshots() {
        #expect(ScreenshotDetector.isScreenshot(filename: "Capture d'écran 2026-11-02 à 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Capture d’écran 2026-11-02 à 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Capture d'ecran 2026-11-02.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Capture d’ecran 2026-11-02.png") == true)
    }

    @Test func detectsPortugueseScreenshots() {
        #expect(ScreenshotDetector.isScreenshot(filename: "Captura de Tela 2026-11-02 às 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Captura de tela 2026-11-02 às 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Captura de ecrã 2026-11-02 às 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Captura de ecra 2026-11-02.png") == true)
    }

    @Test func detectsOtherLanguages() {
        #expect(ScreenshotDetector.isScreenshot(filename: "Captura de pantalla 2026-11-02.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Bildschirmfoto 2026-11-02 um 12.00.00.png") == true)
        #expect(ScreenshotDetector.isScreenshot(filename: "Istantanea 2026-11-02 alle 12.00.00.png") == true)
    }

    @Test func rejectsNonScreenshots() {
        #expect(ScreenshotDetector.isScreenshot(filename: "Photo 2026-11-02.png") == false)
        #expect(ScreenshotDetector.isScreenshot(filename: "Document.pdf") == false)
        #expect(ScreenshotDetector.isScreenshot(filename: "Screenshot.txt") == false)
        #expect(ScreenshotDetector.isScreenshot(filename: ".Screenshot.png") == false)
        #expect(ScreenshotDetector.isScreenshot(filename: "") == false)
    }

    @Test func resolvesDefaultScreenshotLocation() {
        let desktop = URL(fileURLWithPath: "/synthetic/Desktop")
        let location = ScreenshotDetector.resolveLocation(configuredPath: nil, desktop: desktop,
            expandPath: { _ in Issue.record("No configured path should be expanded"); return "" },
            exists: { _ in Issue.record("No configured path should be inspected"); return false })
        #expect(location == desktop)
    }

    @Test func configuredScreenshotLocationUsesTheExpandedExistingPath() {
        let location = ScreenshotDetector.resolveLocation(configuredPath: "~/Pictures/Captures",
            desktop: URL(fileURLWithPath: "/synthetic/Desktop"), expandPath: { path in
                #expect(path == "~/Pictures/Captures")
                return "/synthetic/Pictures/Captures"
            }, exists: { path in
                #expect(path == "/synthetic/Pictures/Captures")
                return true
            })
        #expect(location.path == "/synthetic/Pictures/Captures")
    }

    @Test func missingConfiguredScreenshotLocationFallsBackToTheSuppliedDesktop() {
        let desktop = URL(fileURLWithPath: "/synthetic/Desktop")
        let location = ScreenshotDetector.resolveLocation(configuredPath: "/synthetic/missing",
            desktop: desktop, expandPath: { $0 }, exists: { _ in false })
        #expect(location == desktop)
    }
}
