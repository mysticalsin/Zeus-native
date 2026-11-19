import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

@Suite("Halo renderer")
struct HaloRendererTests {
    @Test func flattenedBezierCurvesKeepEndpointsAndMidpoints() {
        var quadratic = Path()
        quadratic.move(to: .zero)
        quadratic.addQuadCurve(to: CGPoint(x: 20, y: 0), control: CGPoint(x: 10, y: 20))
        let quad = Polyline(path: quadratic)
        #expect(quad.points.count == 9)
        #expect(quad.points.first == .zero)
        #expect(quad.points[4] == CGPoint(x: 10, y: 10))
        #expect(quad.points.last == CGPoint(x: 20, y: 0))

        var cubic = Path()
        cubic.move(to: .zero)
        cubic.addCurve(to: CGPoint(x: 30, y: 0), control1: CGPoint(x: 0, y: 30), control2: CGPoint(x: 30, y: 30))
        let curve = Polyline(path: cubic)
        #expect(curve.points.count == 11)
        #expect(curve.points.first == .zero)
        #expect(curve.points[5] == CGPoint(x: 15, y: 22.5))
        #expect(curve.points.last == CGPoint(x: 30, y: 0))
    }

    @Test func polylineSlicesByArcLength() {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 100, y: 0))
        let line = Polyline(path: path)
        #expect(abs(line.length - 100) < 0.001)
        let half = line.slice(from: 0.5, to: 1)
        #expect(abs(half.length - 50) < 0.001 && abs(half.origin - 50) < 0.001)
        // Samples sit at fixed arc positions, so they do not slide as the lit part grows.
        let a = line.slice(from: 0, to: 0.6).samples(every: 10).map(\.arc)
        let b = line.slice(from: 0, to: 0.9).samples(every: 10).map(\.arc)
        #expect(Array(b.prefix(a.count)) == a)
        #expect(line.slice(from: 0.4, to: 0.4).isEmpty)
    }

    @MainActor @Test func previewDrawsEveryStyleDifferently() throws {
        func pixels(_ style: HaloStyle) -> [UInt8]? {
            let view = HaloOutline(style: style, arm: "Medium", thickness: 1, drawn: 1)
                .frame(width: 260, height: 81).background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = { context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return context.data }() else { return nil }
            return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
        }
        let styles = HaloStyle.allCases.filter { $0 != .off }
        var frames: [HaloStyle: [UInt8]] = [:]
        for style in styles {
            guard let p = pixels(style) else { Issue.record("could not render \(style)"); return }
            frames[style] = p
            #expect(p.contains { $0 > 40 }, "\(style) drew nothing")
        }
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            var sum = 0.0
            for i in 0..<min(a.count, b.count) { sum += abs(Double(a[i]) - Double(b[i])) }
            return sum / Double(a.count)
        }
        for (i, a) in styles.enumerated() {
            for b in styles[(i + 1)...] {
                // Aurora, Storm and Classic share a line at one frozen instant, but their colour differs.
                #expect(difference(frames[a]!, frames[b]!) > 0.05, "\(a) and \(b) look the same")
            }
        }
    }
}
