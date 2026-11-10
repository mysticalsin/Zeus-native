import CoreGraphics
import Foundation

/// Maps screenshot pixels and AX frames to AppKit global points through the shared L0 mapper.
public enum PresentPointMapping {
    public static func displays(from shots: [ScreenShot]) -> [DisplayMap] {
        shots.enumerated().map { index, shot in
            let scale = shot.displayFrame.width > 0
                ? max(1, (Double(shot.pixelWidth) / shot.displayFrame.width).rounded())
                : 1
            return DisplayMap(id: index + 1, frame: shot.displayFrame, scale: scale)
        }
    }

    public static func mapper(from shots: [ScreenShot]) -> ScreenCoordinateMapper {
        ScreenCoordinateMapper(displays: displays(from: shots))
    }

    /// Model `[POINT]` pixels (top-left origin) on a 1-based screen index.
    public static func screenPoint(
        x: Int, y: Int, screen: Int?, in shots: [ScreenShot]
    ) -> CGPoint? {
        guard !shots.isEmpty else { return nil }
        let index = (screen ?? 1) - 1
        let shot = shots.indices.contains(index) ? shots[index] : shots[0]
        let mapper = mapper(from: shots)
        let displayID = shots.firstIndex(where: { $0.displayFrame == shot.displayFrame }).map { $0 + 1 } ?? 1
        let capture = CaptureMap(displayID: displayID, pixelWidth: shot.pixelWidth, pixelHeight: shot.pixelHeight)
        let ctx = MapContext(displayID: displayID, capture: capture)
        return mapper.convert(CGPoint(x: x, y: y), from: .pixel, to: .screen, context: ctx)
    }

    /// Center of an AX element in AppKit global points.
    public static func screenCenter(of element: AXSnapshotElement, mapper: ScreenCoordinateMapper) -> CGPoint? {
        let mid = CGPoint(x: element.frame.midX, y: element.frame.midY)
        return mapper.convert(mid, from: .ax, to: .screen, context: MapContext())
    }

    public static func ringTolerancePoints(for shot: ScreenShot) -> Double {
        let scale = shot.displayFrame.width > 0
            ? Double(shot.pixelWidth) / shot.displayFrame.width
            : 1
        return PresentTolerance.ringPoints(scale: scale, pixelWidth: shot.pixelWidth)
    }
}
