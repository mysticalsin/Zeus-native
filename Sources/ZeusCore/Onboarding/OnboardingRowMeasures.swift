import Foundation

/// Row pitch and centres for the onboarding grid, as Doubles. The window frame stays in CoreGraphics.
public enum OnboardingRowMeasures {
    public static let headingTopY = 168.0
    public static let headingHeight = 44.0
    public static let headingToRows = 24.0
    /// Default distance between row tops (row 61 pt plus the 1 pt divider).
    public static let rowPitch = 62.0

    /// Top of the first row on any step.
    public static var rowsTopY: Double { headingTopY + headingHeight + headingToRows }

    /// Vertical extent of `count` rows of `pitch` points, from the first row's top to the last row's bottom.
    public static func rowsBlock(count: Int, pitch: Double = rowPitch) -> (top: Double, height: Double) {
        (rowsTopY, Double(max(count, 0)) * pitch)
    }

    /// Window y of the centre of row `index` (0-based).
    public static func rowCenterY(_ index: Int, pitch: Double = rowPitch) -> Double {
        rowsTopY + Double(index) * pitch + pitch / 2
    }

    /// Window y of the centre of the whole rows block.
    public static func rowsMidY(count: Int, pitch: Double = rowPitch) -> Double {
        let block = rowsBlock(count: count, pitch: pitch)
        return block.top + block.height / 2
    }
}
