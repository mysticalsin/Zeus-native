import CoreGraphics
import CZeusVisual
import ZeusCore

/// The pointer stroke while show-me is held. Spacing, pauses, and corner smoothing come from
/// `crates/zeus-visual`. This type does not move the system pointer.
final class VisualInk {
    private let box: OpaquePointer
    private var xs = [Double](repeating: 0, count: 16 * 8192)
    private var ys = [Double](repeating: 0, count: 16 * 8192)
    private var lengths = [Int32](repeating: 0, count: 16)

    init() {
        box = zeus_visual_ink_new()
    }

    deinit {
        zeus_visual_ink_free(box)
    }

    func reset() {
        zeus_visual_ink_reset(box)
    }

    func endStroke() {
        zeus_visual_ink_end(box)
    }

    func add(_ point: CGPoint, at time: Double) -> PointingInkTrail.Step {
        switch zeus_visual_ink_add(box, Double(point.x), Double(point.y), time) {
        case 1: return .began
        case 2: return .extended
        default: return .dropped
        }
    }

    var smoothed: [[CGPoint]] {
        let strokeCount = xs.withUnsafeMutableBufferPointer { xsBuf in
            ys.withUnsafeMutableBufferPointer { ysBuf in
                lengths.withUnsafeMutableBufferPointer { lengthsBuf in
                    guard let xsPtr = xsBuf.baseAddress, let ysPtr = ysBuf.baseAddress,
                          let lengthsPtr = lengthsBuf.baseAddress else { return Int32(0) }
                    return zeus_visual_ink_smoothed(
                        box, xsPtr, ysPtr, lengthsPtr, Int32(lengths.count), Int32(xs.count))
                }
            }
        }
        guard strokeCount > 0 else { return [] }
        var strokes: [[CGPoint]] = []
        var start = 0
        for index in 0..<Int(strokeCount) {
            let count = Int(lengths[index])
            let points = (0..<count).map { offset in
                CGPoint(x: xs[start + offset], y: ys[start + offset])
            }
            strokes.append(points)
            start += count
        }
        return strokes
    }
}
