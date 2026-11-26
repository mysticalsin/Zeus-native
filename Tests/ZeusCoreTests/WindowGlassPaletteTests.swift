import Testing
import ZeusCore

@Suite("Window glass palette")
struct WindowGlassPaletteTests {
    @Test func lightDarkAndSystemFollowTheStoredChoice() {
        #expect(WindowGlassPalette.storageKey == "opt.general.windowTheme")
        #expect(WindowGlassPalette.resolve(stored: "Light", systemIsLight: false) == .light)
        #expect(WindowGlassPalette.resolve(stored: "Dark", systemIsLight: true) == .dark)
        #expect(WindowGlassPalette.resolve(stored: "System", systemIsLight: true) == .light)
        #expect(WindowGlassPalette.resolve(stored: "System", systemIsLight: false) == .dark)
        #expect(WindowGlassPalette.resolve(stored: nil, systemIsLight: true) == .light)
        #expect(WindowGlassPalette.resolve(stored: nil, systemIsLight: false) == .dark)
        #expect(WindowGlassPalette.resolve(stored: "", systemIsLight: false) == .dark)
        #expect(WindowGlassPalette.resolve(stored: "Sepia", systemIsLight: true) == .light)
    }

    @Test func darkTokensAreTheSettingsGlassDrawnToday() {
        let dark = WindowGlassPalette.tokens(.dark)
        #expect(dark.window == WindowGlassPalette.RGB(20, 22, 27))
        #expect(dark.panel == WindowGlassPalette.RGB(31, 32, 37))
        #expect(dark.card == WindowGlassPalette.RGB(35, 37, 44))
        #expect(dark.text == WindowGlassPalette.RGB(241, 243, 248))
        #expect(dark.secondary == WindowGlassPalette.RGB(173, 181, 195))
        #expect(dark.controlFill == WindowGlassPalette.RGB(54, 57, 66))
        #expect(dark.controlStroke == WindowGlassPalette.RGB(104, 109, 122))
        #expect(dark.controlText == WindowGlassPalette.RGB(232, 235, 242))
        #expect(WindowGlassPalette.tokens(.light).window != dark.window)
    }

    @Test func textClearsTheWindowPanelAndCard() {
        for resolved in [WindowGlassPalette.Resolved.light, .dark] {
            let tokens = WindowGlassPalette.tokens(resolved)
            #expect(WindowGlassPalette.contrast(tokens.text, tokens.window) >= 4.5)
            #expect(WindowGlassPalette.contrast(tokens.text, tokens.panel) >= 4.5)
            #expect(WindowGlassPalette.contrast(tokens.text, tokens.card) >= 4.5)
            #expect(WindowGlassPalette.contrast(tokens.secondary, tokens.window) >= 4.5)
            #expect(WindowGlassPalette.contrast(tokens.secondary, tokens.card) >= 4.5)
            #expect(WindowGlassPalette.contrast(tokens.selectedText, tokens.selectedFill) >= 4.5)
            #expect(WindowGlassPalette.contrast(tokens.controlText, tokens.controlFill) >= 4.5)
        }
        let light = WindowGlassPalette.tokens(.light)
        #expect(WindowGlassPalette.contrast(light.controlStroke, light.card) >= 3)
    }
}
