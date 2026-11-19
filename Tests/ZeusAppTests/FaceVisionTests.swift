import CoreGraphics
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Vision side of face presence. Generated images only: no camera, no file, no Keychain.
@Suite("Face vision")
struct FaceVisionTests {
    // MARK: Image helpers

    /// An RGBA image drawn by `paint`, which receives the raw bytes (top row first) and the size.
    static func image(width: Int, height: Int, _ paint: (inout [UInt8], Int, Int) -> Void) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        paint(&bytes, width, height)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func fill(_ bytes: inout [UInt8], _ width: Int, _ x: Int, _ y: Int, _ rgb: (UInt8, UInt8, UInt8)) {
        let offset = (y * width + x) * 4
        bytes[offset] = rgb.0; bytes[offset + 1] = rgb.1; bytes[offset + 2] = rgb.2; bytes[offset + 3] = 255
    }

    static func solid(width: Int, height: Int, _ rgb: (UInt8, UInt8, UInt8)) -> CGImage {
        image(width: width, height: height) { bytes, w, h in
            for y in 0..<h { for x in 0..<w { fill(&bytes, w, x, y, rgb) } }
        }
    }

    /// The colour of one pixel, with the origin at the top left.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = data.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    // MARK: Detection

    @Test func aBlankImageHasNoFace() throws {
        let blank = Self.solid(width: 320, height: 240, (128, 128, 128))
        let analysis = try FaceVision.analyze(blank, previousFace: nil)
        #expect(analysis.faceCount == 0)
        #expect(analysis.faceBox == nil)
        #expect(analysis.observation == nil)
        #expect(analysis.quality == nil)
        #expect(analysis.alignment == nil)
        // With no face there is nothing to measure for the spoof cues either.
        #expect(analysis.spoofFrame == SpoofFrame(glare: nil, deviceOverlapFraction: nil))
        #expect(SpoofCues.counted(in: analysis.spoofFrame).isEmpty)
    }

    // MARK: Alignment

    /// The template's five points moved to where a face of 1.5 times the size would sit in a 400 by 300 frame.
    static let fivePoints: [CGPoint] = LandmarkMath.template.map { CGPoint(x: 110 + $0.x * 1.5, y: 40 + $0.y * 1.5) }
    static let box = CGRect(x: 100, y: 40, width: 168, height: 168)

    /// A grey frame with a red 6 pixel square on each of the five points, so the warp can be checked by sight.
    static func markedFrame() -> CGImage {
        image(width: 400, height: 300) { bytes, w, h in
            for y in 0..<h { for x in 0..<w { fill(&bytes, w, x, y, (90, 90, 90)) } }
            for point in fivePoints {
                for dy in -3..<3 { for dx in -3..<3 {
                    fill(&bytes, w, Int(point.x) + dx, Int(point.y) + dy, (255, 0, 0))
                } }
            }
        }
    }

    @Test func alignedCropIs112Square() throws {
        let frame = Self.markedFrame()
        let five = try #require(FaceVision.alignedCrop(from: frame, fivePoints: Self.fivePoints, eyePoints: nil, faceBox: Self.box))
        #expect(five.tier == .fivePoint)
        #expect(five.image.width == 112 && five.image.height == 112)
        // Each marked point lands on its template position (the squares shrink to about 4 pixels).
        for point in LandmarkMath.template {
            let sample = Self.pixel(five.image, x: Int(point.x.rounded()), y: Int(point.y.rounded()))
            #expect(sample.r > 150 && sample.g < 120 && sample.b < 120, "at \(point): \(sample)")
        }
        // A point far from any marker stays grey.
        let away = Self.pixel(five.image, x: 6, y: 6)
        #expect(away.r < 130 && away.g > 60)

        let two = try #require(FaceVision.alignedCrop(from: frame, fivePoints: nil, eyePoints: Array(Self.fivePoints.prefix(2)), faceBox: Self.box))
        #expect(two.tier == .twoPoint)
        #expect(two.image.width == 112 && two.image.height == 112)

        let padded = try #require(FaceVision.alignedCrop(from: frame, fivePoints: nil, eyePoints: nil, faceBox: Self.box))
        #expect(padded.tier == .paddedCrop)
        #expect(padded.image.width == 112 && padded.image.height == 112)
    }

    @Test func aWrongNumberOfPointsFallsBackAndNothingUsableGivesNil() throws {
        let frame = Self.markedFrame()
        // Four points are not a five point alignment, and one eye is not two.
        let fell = try #require(FaceVision.alignedCrop(from: frame, fivePoints: Array(Self.fivePoints.prefix(4)),
                                                       eyePoints: [Self.fivePoints[0]], faceBox: Self.box))
        #expect(fell.tier == .paddedCrop)
        // Points that all coincide cannot give a transform: fall back to the next tier.
        let same = Array(repeating: CGPoint(x: 150, y: 90), count: 5)
        let coincide = try #require(FaceVision.alignedCrop(from: frame, fivePoints: same, eyePoints: Array(same.prefix(2)), faceBox: Self.box))
        #expect(coincide.tier == .paddedCrop)
        // No points and a box outside the image: nothing to crop.
        #expect(FaceVision.alignedCrop(from: frame, fivePoints: nil, eyePoints: nil, faceBox: CGRect(x: 900, y: 900, width: 20, height: 20)) == nil)
        #expect(FaceVision.alignedCrop(from: frame, fivePoints: nil, eyePoints: nil, faceBox: .zero) == nil)
    }

    // MARK: Spoof cue measurements

    @Test func glareExtractorFindsOneBlob() throws {
        // A 160 pixel crop with one white 16 pixel square inside a single cell of the 8 by 8 grid.
        let blob = Self.image(width: 160, height: 160) { bytes, w, h in
            for y in 0..<h { for x in 0..<w { Self.fill(&bytes, w, x, y, (128, 128, 128)) } }
            for y in 22..<38 { for x in 22..<38 { Self.fill(&bytes, w, x, y, (255, 255, 255)) } }
        }
        let sample = try #require(FaceVision.glareSample(of: blob))
        #expect(sample.cropPixelWidth == 160)
        #expect(abs(sample.specularFraction - 256.0 / 25600.0) < 0.0005)
        #expect(sample.specularClusterRatio == 1)

        // The same number of bright pixels scattered one per cell: many small points, not one blob.
        let scattered = Self.image(width: 160, height: 160) { bytes, w, h in
            for y in 0..<h { for x in 0..<w { Self.fill(&bytes, w, x, y, (128, 128, 128)) } }
            for cellY in 0..<8 { for cellX in 0..<8 {
                for dy in 0..<4 { for dx in 0..<4 { Self.fill(&bytes, w, cellX * 20 + 8 + dx, cellY * 20 + 8 + dy, (255, 255, 255)) } }
            } }
        }
        let spread = try #require(FaceVision.glareSample(of: scattered))
        #expect(abs(spread.specularFraction - 1024.0 / 25600.0) < 0.0005)
        #expect(abs(spread.specularClusterRatio - 1.0 / 64.0) < 0.001)
    }

    @Test func glareIgnoresDarkAndColouredPixels() throws {
        let none = try #require(FaceVision.glareSample(of: Self.solid(width: 100, height: 100, (128, 128, 128))))
        #expect(none.specularFraction == 0)
        #expect(none.specularClusterRatio == 0)
        // Bright but clearly coloured pixels (a yellow wall) are not a specular highlight.
        let yellow = try #require(FaceVision.glareSample(of: Self.solid(width: 100, height: 100, (255, 255, 200))))
        #expect(yellow.specularFraction == 0)
        let white = try #require(FaceVision.glareSample(of: Self.solid(width: 100, height: 100, (255, 255, 255))))
        #expect(white.specularFraction == 1)
    }

    @Test func theBezelOverlapIsTheShareOfTheFaceInsideTheRectangle() {
        let face = CGRect(x: 100, y: 100, width: 50, height: 50)
        #expect(FaceVision.overlapFraction(of: face, inside: CGRect(x: 0, y: 0, width: 400, height: 400)) == 1)
        #expect(FaceVision.overlapFraction(of: face, inside: CGRect(x: 125, y: 0, width: 400, height: 400)) == 0.5)
        #expect(FaceVision.overlapFraction(of: face, inside: CGRect(x: 300, y: 300, width: 40, height: 40)) == 0)
        #expect(FaceVision.overlapFraction(of: .zero, inside: CGRect(x: 0, y: 0, width: 40, height: 40)) == nil)
    }

    // MARK: Feature print

    @Test func featurePrintRevisionIsRecorded() throws {
        let crop = Self.image(width: 112, height: 112) { bytes, w, h in
            for y in 0..<h { for x in 0..<w { Self.fill(&bytes, w, x, y, (UInt8(x * 2), UInt8(y * 2), UInt8((x + y) % 256))) } }
        }
        let observation = try FaceVision.featurePrint(of: crop)
        #expect(observation.revision == FaceVision.featurePrintRevision)
        #expect(!observation.embedding.isEmpty)
        let allFinite = observation.embedding.allSatisfy { $0.isFinite }
        #expect(allFinite)
        // Two prints of the same image are the same vector, so a match against itself is distance zero.
        let again = try FaceVision.featurePrint(of: crop)
        #expect(FaceMatch.distance(observation.embedding, again.embedding) < 0.0001)
    }

    // MARK: What leaves the analyzer

    @Test func noImageLeavesTheAnalyzer() {
        let analysis = FaceVision.FrameAnalysis(faceCount: 1, faceBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                                                observation: FaceObservation(embedding: [1, 2, 3], revision: 2),
                                                quality: 0.8, alignment: .fivePoint,
                                                spoofFrame: SpoofFrame(glare: nil, deviceOverlapFraction: 0.1))
        let labels = Mirror(reflecting: analysis).children.compactMap(\.label)
        #expect(Set(labels) == ["faceCount", "faceBox", "observation", "quality", "alignment", "spoofFrame"])
        // Every stored value is a number, a rectangle or a small value type of numbers.
        let banned = ["CGImage", "CIImage", "CVPixelBuffer", "CMSampleBuffer", "NSImage", "Data", "URL", "UIImage", "IOSurface"]
        for child in Mirror(reflecting: analysis).children {
            let typeName = String(describing: type(of: child.value))
            for name in banned { #expect(!typeName.contains(name), "\(child.label ?? "?") is \(typeName)") }
        }
        let observationLabels = Mirror(reflecting: analysis.observation!).children.compactMap(\.label)
        #expect(Set(observationLabels) == ["embedding", "revision"])
        let spoofLabels = Mirror(reflecting: analysis.spoofFrame).children.compactMap(\.label)
        #expect(Set(spoofLabels) == ["glare", "deviceOverlapFraction"])
    }
}
