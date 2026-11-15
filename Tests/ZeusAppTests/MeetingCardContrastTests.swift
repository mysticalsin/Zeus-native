import Foundation
import Testing
@testable import Zeus

@Suite("Meeting card text contrast")
struct MeetingCardContrastTests {
    private static func luminance(_ hex: Int) -> Double {
        func lin(_ shift: Int) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(16) + 0.7152 * lin(8) + 0.0722 * lin(0)
    }

    static func ratio(_ a: Int, _ b: Int) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// QA m7: the purple accent text ("Now", "in 2 min") was about 2.5:1 on the card's mid blue-violet. WCAG AA
    /// for normal text is 4.5:1, against the mid tone the glass is tinted with (the darker tones only help).
    @Test func theAccentTextMeetsAAOnTheCardsMidTone() {
        let ratio = Self.ratio(ScribeMeetingCardPalette.violetHex, ScribeMeetingCardPalette.tintMidHex)
        #expect(ratio >= 4.5, "accent contrast is \(ratio):1")
    }

    @Test func theAccentIsStillTintedNotPlainWhite() {
        #expect(ScribeMeetingCardPalette.violetHex != 0xFFFFFF)
    }
}
