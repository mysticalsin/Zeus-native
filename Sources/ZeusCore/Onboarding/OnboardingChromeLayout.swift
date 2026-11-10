import CoreGraphics

/// Shared onboarding chrome measurements (QA19: one left edge for the brand mark and headings).
public enum OnboardingChromeLayout {
    public static let leadingEdge: CGFloat = 48
    public static let headingTopY: CGFloat = 168
    public static let windowWidth: CGFloat = 960
    public static let windowHeight: CGFloat = 760
    public static let trailingMargin: CGFloat = 32
    public static let columnTrailingX: CGFloat = 468
    public static let introFilmCardWidth: CGFloat = 420
    /// Welcome hero panel height: it runs from the heading line down past the third value row.
    public static let welcomeHeroHeight: CGFloat = 432
    public static let footerTopY: CGFloat = 694

    // MARK: Rows (R24: every step's rows and its right-hand visual share one grid)
    /// Heading block (title) height and the gap under it.
    public static let headingHeight: CGFloat = 44
    public static let headingToRows: CGFloat = 24
    /// Top of the first row on any step.
    public static var rowsTopY: CGFloat { headingTopY + headingHeight + headingToRows }
    /// Default distance between row tops (row 61 pt plus the 1 pt divider).
    public static let rowPitch: CGFloat = 62

    /// Vertical extent of `count` rows of `pitch` points, from the first row's top to the last row's bottom.
    public static func rowsBlock(count: Int, pitch: CGFloat = rowPitch) -> (top: CGFloat, height: CGFloat) {
        (rowsTopY, CGFloat(max(count, 0)) * pitch)
    }

    /// Window y of the centre of row `index` (0-based).
    public static func rowCenterY(_ index: Int, pitch: CGFloat = rowPitch) -> CGFloat {
        rowsTopY + CGFloat(index) * pitch + pitch / 2
    }

    /// Window y of the centre of the whole rows block.
    public static func rowsMidY(count: Int, pitch: CGFloat = rowPitch) -> CGFloat {
        let block = rowsBlock(count: count, pitch: pitch)
        return block.top + block.height / 2
    }

    /// A step's content reads as balanced when its rows end past this fraction of the space between the
    /// heading line and the footer (the QA round 23 complaint was content in the top 55 percent).
    public static let minimumFillFraction: CGFloat = 0.6

    public static func fillFraction(rowsBottom: CGFloat) -> CGFloat {
        (rowsBottom - headingTopY) / (footerTopY - headingTopY)
    }

    /// Center X for the welcome intro card so it sits in the right column with even margins.
    public static var welcomePreviewCenterX: CGFloat {
        windowWidth - trailingMargin - introFilmCardWidth / 2
    }

    /// Window-space frame of the welcome preview card (top aligned with step headings).
    public static func welcomePreviewFrame(scale: CGFloat = 1) -> CGRect {
        let cardW = introFilmCardWidth * scale
        let cardH = welcomeHeroHeight * scale
        let centerX = welcomePreviewCenterX * scale
        let top = headingTopY * scale
        return CGRect(x: centerX - cardW / 2, y: top, width: cardW, height: cardH)
    }

    public static func previewFitsWindow(at scale: CGFloat = 1) -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: windowWidth * scale, height: windowHeight * scale)
        return bounds.contains(welcomePreviewFrame(scale: scale))
    }
}

/// Copy rules for film cards inside onboarding (12:19: no taglines in mocks).
public enum OnboardingMockCopy {
    public static let runningFilmSubtitle = ""
    public static let forbiddenTaglines: [String] = [
        "your agent at work, live in the notch",
        "allow or deny, right from the notch",
        "Control + Option, then Y, N or O",
    ]

    public static func mockSubtitleIsAllowed(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        return !forbiddenTaglines.contains { lower == $0.lowercased() }
    }
}
