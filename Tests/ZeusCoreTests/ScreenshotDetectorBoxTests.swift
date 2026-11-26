import Foundation
import Testing
@testable import ZeusCore

@Suite("Screenshot detector box")
struct ScreenshotDetectorBoxTests {
    private let prefixes = [
        "screenshot",
        "screen shot",
        "capture d’écran",
        "capture d'écran",
        "capture d’ecran",
        "capture d'ecran",
        "captura de tela",
        "captura de ecrã",
        "captura de ecra",
        "captura de pantalla",
        "bildschirmfoto",
        "istantanea",
        "снимок экрана",
        "スクリーンショット",
        "截屏",
        "屏幕截图",
    ]

    private let extensions: Set<String> = ["png", "jpg", "jpeg", "pdf", "tiff", "heic", "mov", "mp4"]

    @Test func thePrefixesAreTheLocalizedScreenshotNames() {
        #expect(ScreenshotDetectorBox.localizedPrefixes == prefixes)
    }

    @Test func theExtensionsAreTheCaptureFormats() {
        #expect(ScreenshotDetectorBox.validExtensions == extensions)
    }

    @Test func anEnglishNameIsAScreenshot() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screenshot 2026-11-02 at 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screen Shot 2026-11-02 at 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screen Shot.jpg"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Photo 2026-11-02.png"))
    }

    @Test func aFrenchNameMatchesEitherApostrophe() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Capture d'écran 2026-11-02 à 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Capture d’écran 2026-11-02 à 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Capture d'ecran 2026-11-02.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Capture d’ecran 2026-11-02.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Capture.png"))
    }

    @Test func aPortugueseNameIsAScreenshot() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Captura de Tela 2026-11-02 às 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Captura de tela 2026-11-02 às 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Captura de ecrã 2026-11-02 às 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Captura de ecra 2026-11-02.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Captura.png"))
    }

    @Test func spanishGermanAndItalianNamesAreScreenshots() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Captura de pantalla 2026-11-02.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Bildschirmfoto 2026-11-02 um 12.00.00.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Istantanea 2026-11-02 alle 12.00.00.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Foto 2026-11-02.png"))
    }

    @Test func cyrillicJapaneseAndChineseNamesAreScreenshots() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Снимок экрана 2026-11-02.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "スクリーンショット 2026-11-02.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "截屏 2026-11-02.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "屏幕截图 2026-11-02.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "照片.png"))
    }

    @Test func aHiddenWrongOrBlankNameIsNotAScreenshot() {
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: ".Screenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.txt"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Document.pdf"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: ""))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "   "))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.png"))
    }

    @Test func theNameIsTrimmedAndTheExtensionIsLowercased() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "  SCREENSHOT.PNG  "))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "\nScreen Shot.JPEG\t"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "  notes.PNG  "))
    }

    @Test func aPrefixHasToStartTheName() {
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "screenshot extra.png"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "screen shot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "myscreenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "not a screenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "shot.png"))
    }

    @Test func everyCaptureExtensionCounts() {
        for ext in ["png", "jpg", "jpeg", "pdf", "tiff", "heic", "mov", "mp4"] {
            #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.\(ext)"))
        }
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.gif"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Screenshot"))
    }

    @Test func aURLUsesItsLastPathComponent() {
        let shot = URL(fileURLWithPath: "/synthetic/Desktop/Screenshot 2026-11-02.png")
        let photo = URL(fileURLWithPath: "/synthetic/Desktop/Photo.png")
        let hidden = URL(fileURLWithPath: "/synthetic/Desktop/.Screenshot.png")
        #expect(ScreenshotDetectorBox.isScreenshot(url: shot))
        #expect(!ScreenshotDetectorBox.isScreenshot(url: photo))
        #expect(!ScreenshotDetectorBox.isScreenshot(url: hidden))
    }

    @Test func noConfiguredPathUsesTheDesktop() {
        let desktop = URL(fileURLWithPath: "/synthetic/Desktop")
        let location = ScreenshotDetectorBox.resolveLocation(
            configuredPath: nil, desktop: desktop,
            expandPath: { _ in Issue.record("No configured path should be expanded"); return "" },
            exists: { _ in Issue.record("No configured path should be inspected"); return false })
        #expect(location == desktop)
    }

    @Test func anExistingConfiguredPathIsTheExpandedFolder() {
        let location = ScreenshotDetectorBox.resolveLocation(
            configuredPath: "~/Pictures/Captures",
            desktop: URL(fileURLWithPath: "/synthetic/Desktop"),
            expandPath: { path in
                #expect(path == "~/Pictures/Captures")
                return "/synthetic/Pictures/Captures"
            },
            exists: { path in
                #expect(path == "/synthetic/Pictures/Captures")
                return true
            })
        #expect(location.path == "/synthetic/Pictures/Captures")
    }

    @Test func aMissingConfiguredPathFallsBackToTheDesktop() {
        let desktop = URL(fileURLWithPath: "/synthetic/Desktop")
        let location = ScreenshotDetectorBox.resolveLocation(
            configuredPath: "/synthetic/missing",
            desktop: desktop,
            expandPath: { path in
                #expect(path == "/synthetic/missing")
                return path
            },
            exists: { path in
                #expect(path == "/synthetic/missing")
                return false
            })
        #expect(location == desktop)
    }

    @Test func anEmptyConfiguredPathFallsBackWhenItDoesNotExist() {
        let desktop = URL(fileURLWithPath: "/synthetic/Desktop")
        let location = ScreenshotDetectorBox.resolveLocation(
            configuredPath: "",
            desktop: desktop,
            expandPath: { path in
                #expect(path == "")
                return path
            },
            exists: { path in
                #expect(path.isEmpty)
                return false
            })
        #expect(location == desktop)
    }
}
