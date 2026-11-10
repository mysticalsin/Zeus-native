import Foundation

/// Pixel size, context scale and output path for `zeus debug screenshot`.
/// Pure: the window capture calls these so a unit test can lock the 2x crop and the `.png-settings.png` suffix.
public enum ScreenshotCapturePlan {
    /// Pixel buffer for a window of `pointWidth` x `pointHeight` at `backingScale` (1 on a non-Retina display, 2 on this Mac).
    public static func pixelSize(pointWidth: Double, pointHeight: Double, backingScale: Double) -> (width: Int, height: Int) {
        let scale = backingScale > 0 ? backingScale : 1
        return (max(1, Int((pointWidth * scale).rounded())), max(1, Int((pointHeight * scale).rounded())))
    }

    /// Extra CTM scale before drawing the view in points.
    /// An `NSBitmapImageRep` whose `size` is the point size and whose pixels are `point * backingScale`
    /// is already in point space. Scaling by `backingScale` again draws only the top-left corner, magnified.
    /// Pass `contextIsPointSpace: true` for that bitmap. Pass false only when 1 unit is 1 pixel.
    public static func contextScale(contextIsPointSpace: Bool, backingScale: Double) -> Double {
        if contextIsPointSpace { return 1 }
        return backingScale > 0 ? backingScale : 1
    }

    /// How much of the window (in points) lands in the bitmap after `contextScale`.
    /// Scale 1 shows the whole window. Scale 2 shows the top-left half of each edge.
    public static func visiblePointSize(pointWidth: Double, pointHeight: Double, contextScale: Double) -> (width: Double, height: Double) {
        let scale = contextScale > 0 ? contextScale : 1
        return (pointWidth / scale, pointHeight / scale)
    }

    /// Where one window's PNG is written.
    /// A concrete file (`/tmp/x.png`) plus one window (`--window settings`) writes that path.
    /// A bare prefix, or a capture of every window, keeps the `-<name>.png` suffix so the files do not collide.
    public static func outputPath(base: String, windowName: String, filter: String?) -> String {
        let expanded = (base as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let oneWindow = filter.map { !$0.isEmpty && $0.caseInsensitiveCompare("all") != .orderedSame } ?? false
        if oneWindow, !url.pathExtension.isEmpty { return url.path }
        return "\(url.path)-\(windowName).png"
    }
}
