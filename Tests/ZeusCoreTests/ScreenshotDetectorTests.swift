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
        let location = ScreenshotDetector.location()
        #expect(location.path.contains("Desktop") || FileManager.default.fileExists(atPath: location.path))
    }
}
