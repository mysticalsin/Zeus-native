// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceDetector.swift, FaceAligner.swift, FaceEmbedder.swift, Liveness/LandmarkGeometry.swift, Liveness/LivenessFeatures.swift, Liveness/GlareCueExtractor.swift, Liveness/DeviceBezelDetector.swift.
import CoreGraphics
import Foundation
import Vision
import ZeusCore

/// The Vision half of face presence: find the faces in one frame, pick the person at the screen, align the crop,
/// take a feature print, and measure the two spoof cues. Everything is synchronous and nonisolated, called from one
/// detached task with a `CGImage` passed in; only numbers come back. No image is kept, written or shown.
enum FaceVision {
    enum VisionError: Error, Equatable {
        case detectionFailed
        case noFeaturePrint
        case unsupportedElementType
    }

    /// What one analyzed frame holds. Numbers and small value types only, so no image can leave the analyzer.
    struct FrameAnalysis: Equatable, Sendable {
        /// Faces Vision found, bystanders included.
        let faceCount: Int
        /// The dominant face as Vision's normalized rectangle (origin bottom left). Feed it back as `previousFace`.
        let faceBox: CGRect?
        /// The feature print of the aligned crop of the dominant face.
        let observation: ZeusCore.FaceObservation?
        /// Vision's capture quality for the dominant face, 0 to 1.
        let quality: Float?
        let alignment: AlignmentTier?
        let spoofFrame: SpoofFrame
    }

    /// The feature print revision this build asks Vision for. Recorded with every sample and every observation.
    static var featurePrintRevision: Int { VNGenerateImageFeaturePrintRequest.currentRevision }

    // MARK: Frame analysis

    /// `previousFace` is the last frame's `faceBox`, so two similar faces do not swap every frame.
    static func analyze(_ image: CGImage, previousFace: CGRect?) throws -> FrameAnalysis {
        let empty = FrameAnalysis(faceCount: 0, faceBox: nil, observation: nil, quality: nil, alignment: nil,
                                 spoofFrame: SpoofFrame(glare: nil, deviceOverlapFraction: nil))
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let rectangles = VNDetectFaceRectanglesRequest()
        do { try handler.perform([rectangles]) } catch { throw VisionError.detectionFailed }
        let faces = rectangles.results ?? []
        guard !faces.isEmpty else { return empty }

        // Chained to the rectangle results so every request answers for the same faces, in the same order.
        let quality = VNDetectFaceCaptureQualityRequest()
        let landmarks = VNDetectFaceLandmarksRequest()
        quality.inputFaceObservations = faces
        landmarks.inputFaceObservations = faces
        do { try handler.perform([quality, landmarks]) } catch { throw VisionError.detectionFailed }

        let boxes = faces.map(\.boundingBox)
        guard let index = FaceSelection.select(in: boxes, preferNear: previousFace) else {
            return FrameAnalysis(faceCount: faces.count, faceBox: nil, observation: nil, quality: nil, alignment: nil,
                                 spoofFrame: empty.spoofFrame)
        }
        let size = CGSize(width: image.width, height: image.height)
        let box = boxes[index]
        let pixelBox = FaceSelection.imageRect(fromNormalized: box, imageSize: size)
        let faceQuality = (quality.results ?? []).indices.contains(index) ? quality.results?[index].faceCaptureQuality : nil
        let faceLandmarks = (landmarks.results ?? []).indices.contains(index) ? landmarks.results?[index].landmarks : nil

        let five = faceLandmarks.flatMap { fivePoints(from: $0, imageSize: size) }
        let eyes = faceLandmarks.flatMap { eyePoints(from: $0, imageSize: size) }
        guard let aligned = alignedCrop(from: image, fivePoints: five, eyePoints: eyes, faceBox: pixelBox) else {
            return FrameAnalysis(faceCount: faces.count, faceBox: box, observation: nil, quality: faceQuality, alignment: nil,
                                 spoofFrame: empty.spoofFrame)
        }
        let observation = try featurePrint(of: aligned.image)

        let glare = FaceSelection.paddedCrop(pixelBox, imageSize: size).flatMap { image.cropping(to: $0) }
            .flatMap { glareSample(of: $0) }
        let overlap = deviceOverlap(in: image, faceBox: pixelBox)
        return FrameAnalysis(faceCount: faces.count, faceBox: box, observation: observation, quality: faceQuality,
                             alignment: aligned.tier, spoofFrame: SpoofFrame(glare: glare, deviceOverlapFraction: overlap))
    }

    // MARK: Feature print

    /// Apple's feature print of an aligned crop, as plain floats with the revision that produced it.
    static func featurePrint(of crop: CGImage) throws -> ZeusCore.FaceObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = featurePrintRevision
        let handler = VNImageRequestHandler(cgImage: crop, options: [:])
        do { try handler.perform([request]) } catch { throw VisionError.noFeaturePrint }
        guard let result = request.results?.first else { throw VisionError.noFeaturePrint }
        let count = result.elementCount
        var vector = [Float](repeating: 0, count: count)
        switch result.elementType {
        case .float:
            result.data.withUnsafeBytes { raw in
                let values = raw.bindMemory(to: Float.self)
                for index in 0..<min(count, values.count) { vector[index] = values[index] }
            }
        case .double:
            result.data.withUnsafeBytes { raw in
                let values = raw.bindMemory(to: Double.self)
                for index in 0..<min(count, values.count) { vector[index] = Float(values[index]) }
            }
        default:
            throw VisionError.unsupportedElementType
        }
        return ZeusCore.FaceObservation(embedding: vector, revision: request.revision)
    }

    // MARK: Alignment

    /// The face as a 112 pixel square: the five points warped onto the template, else the two eyes, else a padded
    /// crop of the face box. Points and `faceBox` are in image pixels with the origin at the top left. Nil when none
    /// of the three can be made.
    static func alignedCrop(from image: CGImage, fivePoints: [CGPoint]?, eyePoints: [CGPoint]?,
                            faceBox: CGRect) -> (image: CGImage, tier: AlignmentTier)? {
        if let fivePoints, fivePoints.count == LandmarkMath.template.count,
           let warped = warp(image, from: fivePoints, to: LandmarkMath.template) {
            return (warped, .fivePoint)
        }
        if let eyePoints, eyePoints.count == LandmarkMath.eyeTemplate.count,
           let warped = warp(image, from: eyePoints, to: LandmarkMath.eyeTemplate) {
            return (warped, .twoPoint)
        }
        let size = CGSize(width: image.width, height: image.height)
        guard let rect = FaceSelection.paddedCrop(faceBox, imageSize: size), let cropped = image.cropping(to: rect),
              let resized = resize(cropped) else { return nil }
        return (resized, .paddedCrop)
    }

    /// Points arrive with the origin at the top left; the context draws with it at the bottom left, so both sets are
    /// flipped before the transform is solved. The image itself needs no flip.
    private static func warp(_ image: CGImage, from source: [CGPoint], to destination: [CGPoint]) -> CGImage? {
        let flippedSource = LandmarkMath.flipVertical(source, imageHeight: CGFloat(image.height))
        let flippedDestination = LandmarkMath.flipVertical(destination, imageHeight: CGFloat(LandmarkMath.templateSize))
        guard let transform = LandmarkMath.similarityTransform(from: flippedSource, to: flippedDestination),
              let context = squareContext() else { return nil }
        context.interpolationQuality = .high
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func resize(_ image: CGImage) -> CGImage? {
        guard let context = squareContext() else { return nil }
        context.interpolationQuality = .high
        let side = CGFloat(LandmarkMath.templateSize)
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func squareContext() -> CGContext? {
        let side = LandmarkMath.templateSize
        return CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: Landmarks

    private static func points(_ region: VNFaceLandmarkRegion2D?, imageSize: CGSize) -> [CGPoint] {
        guard let region else { return [] }
        return LandmarkMath.flipVertical(region.pointsInImage(imageSize: imageSize), imageHeight: imageSize.height)
    }

    private static func eyeCenters(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> (CGPoint, CGPoint)? {
        guard let first = LandmarkMath.eyeCenter(pupil: points(landmarks.leftPupil, imageSize: imageSize),
                                                 eye: points(landmarks.leftEye, imageSize: imageSize)),
              let second = LandmarkMath.eyeCenter(pupil: points(landmarks.rightPupil, imageSize: imageSize),
                                                  eye: points(landmarks.rightEye, imageSize: imageSize))
        else { return nil }
        return (first, second)
    }

    private static func fivePoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let (first, second) = eyeCenters(from: landmarks, imageSize: imageSize),
              let nose = LandmarkMath.centroid(points(landmarks.nose, imageSize: imageSize))
        else { return nil }
        return LandmarkMath.fivePoints(eyeA: first, eyeB: second, nose: nose,
                                       lips: points(landmarks.outerLips, imageSize: imageSize))
    }

    private static func eyePoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        eyeCenters(from: landmarks, imageSize: imageSize).map { LandmarkMath.twoPoints(eyeA: $0.0, eyeB: $0.1) }
    }

    // MARK: Spoof cue measurements

    /// Near white, near grey: the signature of a direct specular highlight rather than a bright coloured surface.
    private static let specularLumaFloor: Float = 235
    private static let specularChromaTolerance: Float = 10
    /// Coarse on purpose: it only separates one blob from many scattered points.
    private static let clusterGridSize = 8

    /// Three numbers about a face crop. Nil only when the crop cannot be read; a small crop still gives a sample,
    /// which `SpoofCues` discounts by its width.
    static func glareSample(of crop: CGImage) -> GlareSample? {
        let width = crop.width
        let height = crop.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = data.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))

        var cells = [Int](repeating: 0, count: clusterGridSize * clusterGridSize)
        var specular = 0
        data.withUnsafeBufferPointer { bytes in
            for y in 0..<height {
                let row = y * width * 4
                let cellY = min(clusterGridSize - 1, y * clusterGridSize / height)
                for x in 0..<width {
                    let offset = row + x * 4
                    let r = Float(bytes[offset]), g = Float(bytes[offset + 1]), b = Float(bytes[offset + 2])
                    guard 0.299 * r + 0.587 * g + 0.114 * b >= specularLumaFloor else { continue }
                    let cb = -0.168736 * r - 0.331264 * g + 0.5 * b + 128
                    let cr = 0.5 * r - 0.418688 * g - 0.081312 * b + 128
                    guard abs(cb - 128) <= specularChromaTolerance, abs(cr - 128) <= specularChromaTolerance else { continue }
                    specular += 1
                    cells[cellY * clusterGridSize + min(clusterGridSize - 1, x * clusterGridSize / width)] += 1
                }
            }
        }
        let fraction = Float(specular) / Float(width * height)
        let ratio = specular > 0 ? Float(cells.max() ?? 0) / Float(specular) : 0
        return GlareSample(cropPixelWidth: CGFloat(width), specularFraction: fraction, specularClusterRatio: ratio)
    }

    /// The share of the face box inside the largest phone or tablet shaped rectangle in the frame. Nil when there
    /// is no such rectangle or the face has no area.
    private static func deviceOverlap(in image: CGImage, faceBox: CGRect) -> Float? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.6
        // A fraction of the image area, not of its width or height.
        request.minimumSize = 0.15
        request.maximumObservations = 3
        // From a phone held upright (0.35) to a near square tablet (1.0).
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        // Generous, so a phone held at a slight angle still registers.
        request.quadratureTolerance = 30
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let results = request.results, !results.isEmpty else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let rectangles = results.map { FaceSelection.imageRect(fromNormalized: $0.boundingBox, imageSize: size) }
        // The largest candidate is taken to be the device, not a smaller detail on it.
        guard let largest = rectangles.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        return overlapFraction(of: faceBox, inside: largest)
    }

    /// The part of `face` that lies inside `rectangle`, 0 to 1. Nil when the face has no area.
    static func overlapFraction(of face: CGRect, inside rectangle: CGRect) -> Float? {
        let area = face.width * face.height
        guard area > 0, area.isFinite else { return nil }
        let shared = rectangle.intersection(face)
        guard !shared.isNull else { return 0 }
        return Float((shared.width * shared.height) / area)
    }
}
