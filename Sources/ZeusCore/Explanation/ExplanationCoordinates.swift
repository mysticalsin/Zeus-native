import Foundation

/// App-issued identity of the content/display that was captured. Change `contextID`
/// when the foreground content, scroll position, Space, or display configuration changes.
/// A saved identity is descriptive only; it never grants permission to capture or draw.
public struct ExplanationDisplayContext: Codable, Equatable, Sendable {
    public let contextID: UUID
    public let displayID: UInt32
    /// AppKit global points, bottom-left origin; negative display origins are supported.
    public let frame: ExplanationRect
    public let backingScale: Double

    public init(contextID: UUID = UUID(), displayID: UInt32, frame: ExplanationRect, backingScale: Double) throws {
        guard displayID != 0, ExplanationCoordinateValidation.rect(frame),
              backingScale.isFinite, (0.5...8).contains(backingScale) else {
            throw ExplanationFailure.invalid("display context")
        }
        self.contextID = contextID; self.displayID = displayID; self.frame = frame; self.backingScale = backingScale
    }

    private enum CodingKeys: String, CodingKey { case contextID, displayID, frame, backingScale }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(contextID: c.decode(UUID.self, forKey: .contextID), displayID: c.decode(UInt32.self, forKey: .displayID),
                      frame: c.decode(ExplanationRect.self, forKey: .frame), backingScale: c.decode(Double.self, forKey: .backingScale))
    }
}

/// Geometry of one explicitly captured image. No pixels, file paths, or provider data.
/// `crop` is in the original full-image pixel grid; `imageSize` is the delivered image's
/// pixel grid, which may be cropped AND resized. Backing scale is not a substitute for either.
public struct ExplanationCaptureGeometry: Codable, Equatable, Sendable {
    public let captureID: UUID
    public let display: ExplanationDisplayContext
    public let fullImageSize: ExplanationSize2
    public let crop: ExplanationRect
    public let imageSize: ExplanationSize2

    public init(captureID: UUID = UUID(), display: ExplanationDisplayContext, fullImageSize: ExplanationSize2,
                crop: ExplanationRect, imageSize: ExplanationSize2) throws {
        guard ExplanationCoordinateValidation.size(fullImageSize), ExplanationCoordinateValidation.size(imageSize),
              ExplanationCoordinateValidation.rect(crop), crop.x >= 0, crop.y >= 0,
              crop.x + crop.width <= fullImageSize.width, crop.y + crop.height <= fullImageSize.height else {
            throw ExplanationFailure.invalid("capture crop")
        }
        self.captureID = captureID; self.display = display; self.fullImageSize = fullImageSize
        self.crop = crop; self.imageSize = imageSize
    }

    public func isCurrent(captureID: UUID, display current: ExplanationDisplayContext) -> Bool {
        self.captureID == captureID && display == current
    }

    /// Delivered image pixels (top-left) to AppKit global points. A stale context hides
    /// the annotation rather than stretching it onto a replacement display or window.
    public func globalPoint(fromImage point: ExplanationVector3, current: ExplanationDisplayContext) -> ExplanationVector3? {
        guard display == current, ExplanationCoordinateValidation.point(point, in: imageSize) else { return nil }
        let x = crop.x + point.x * crop.width / imageSize.width
        let y = crop.y + point.y * crop.height / imageSize.height
        return .init(x: display.frame.x + x * display.frame.width / fullImageSize.width,
                     y: display.frame.y + display.frame.height - y * display.frame.height / fullImageSize.height)
    }

    /// Inverse hit test. Points outside the actual crop are not silently clamped to it.
    public func imagePoint(fromGlobal point: ExplanationVector3, current: ExplanationDisplayContext) -> ExplanationVector3? {
        guard display == current, ExplanationCoordinateValidation.point(point) else { return nil }
        let x = (point.x - display.frame.x) * fullImageSize.width / display.frame.width
        let y = (display.frame.y + display.frame.height - point.y) * fullImageSize.height / display.frame.height
        let result = ExplanationVector3(x: (x - crop.x) * imageSize.width / crop.width,
                                        y: (y - crop.y) * imageSize.height / crop.height)
        return ExplanationCoordinateValidation.point(result, in: imageSize) ? result : nil
    }

    private enum CodingKeys: String, CodingKey { case captureID, display, fullImageSize, crop, imageSize }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(captureID: c.decode(UUID.self, forKey: .captureID), display: c.decode(ExplanationDisplayContext.self, forKey: .display),
                      fullImageSize: c.decode(ExplanationSize2.self, forKey: .fullImageSize), crop: c.decode(ExplanationRect.self, forKey: .crop),
                      imageSize: c.decode(ExplanationSize2.self, forKey: .imageSize))
    }
}

/// Explicit aspect-fit, zoom, and pan between logical scene units and an owned view's
/// top-left points. Recreate after resize; its identity lets hit testing reject stale layouts.
public struct ExplanationViewportTransform: Equatable, Sendable {
    public let id: UUID
    public let canvasSize: ExplanationSize2
    public let viewport: ExplanationRect
    public let scale: Double
    public let origin: ExplanationVector3

    public init(id: UUID = UUID(), canvasSize: ExplanationSize2, viewport: ExplanationRect,
                zoom: Double = 1, pan: ExplanationVector3 = .zero) throws {
        guard ExplanationCoordinateValidation.size(canvasSize), ExplanationCoordinateValidation.rect(viewport),
              zoom.isFinite, (0.1...8).contains(zoom), ExplanationCoordinateValidation.point(pan) else {
            throw ExplanationFailure.invalid("viewport transform")
        }
        let scale = min(viewport.width / canvasSize.width, viewport.height / canvasSize.height) * zoom
        self.id = id; self.canvasSize = canvasSize; self.viewport = viewport; self.scale = scale
        origin = .init(x: viewport.x + (viewport.width - canvasSize.width * scale) / 2 + pan.x,
                       y: viewport.y + (viewport.height - canvasSize.height * scale) / 2 + pan.y)
    }

    public func viewPoint(fromCanvas point: ExplanationVector3) -> ExplanationVector3? {
        guard ExplanationCoordinateValidation.point(point, in: canvasSize) else { return nil }
        return .init(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    /// Letterboxing, clipping, and stale viewport identities produce no hit.
    public func canvasPoint(fromView point: ExplanationVector3, viewportID: UUID) -> ExplanationVector3? {
        guard viewportID == id, ExplanationCoordinateValidation.point(point),
              point.x >= viewport.x, point.y >= viewport.y,
              point.x <= viewport.x + viewport.width, point.y <= viewport.y + viewport.height else { return nil }
        let result = ExplanationVector3(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
        return ExplanationCoordinateValidation.point(result, in: canvasSize) ? result : nil
    }
}

/// Only the app constructs this live pairing. Persisted geometry alone cannot make
/// an annotation visible after its content/display identity has changed.
public struct ExplanationCaptureContext: Equatable, Sendable {
    public let geometry: ExplanationCaptureGeometry
    public let currentDisplay: ExplanationDisplayContext
    public init(geometry: ExplanationCaptureGeometry, currentDisplay: ExplanationDisplayContext) {
        self.geometry = geometry; self.currentDisplay = currentDisplay
    }
    public func isCurrent(captureID: UUID?) -> Bool {
        captureID == geometry.captureID && geometry.display == currentDisplay
    }
    /// First fit the delivered image into logical canvas units, then fit that canvas
    /// into the owned view. This keeps mixed canvas/capture objects in one stage.
    public func projection(canvasSize: ExplanationSize2, viewport: ExplanationRect,
                           viewportID: UUID, zoom: Double = 1, pan: ExplanationVector3 = .zero) throws -> ExplanationCaptureProjection? {
        guard isCurrent(captureID: geometry.captureID) else { return nil }
        let image = try ExplanationViewportTransform(id: viewportID, canvasSize: geometry.imageSize,
            viewport: .init(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        let canvas = try ExplanationViewportTransform(id: viewportID, canvasSize: canvasSize, viewport: viewport, zoom: zoom, pan: pan)
        return ExplanationCaptureProjection(captureID: geometry.captureID, image: image, canvas: canvas)
    }
}

public struct ExplanationCaptureProjection: Equatable, Sendable {
    public let captureID: UUID
    public let viewportID: UUID
    /// Uniform scale and top-left origin: useful when projecting an object's entire
    /// local geometry. Radius, stroke width, and drag deltas use this same scale.
    public let scale: Double
    public let origin: ExplanationVector3
    private let image: ExplanationViewportTransform
    private let canvas: ExplanationViewportTransform
    fileprivate init(captureID: UUID, image: ExplanationViewportTransform, canvas: ExplanationViewportTransform) {
        self.captureID = captureID; viewportID = canvas.id; self.image = image; self.canvas = canvas
        scale = image.scale * canvas.scale
        origin = .init(x: canvas.origin.x + image.origin.x * canvas.scale,
                       y: canvas.origin.y + image.origin.y * canvas.scale)
    }
    public func viewPoint(fromImage point: ExplanationVector3) -> ExplanationVector3? {
        guard let logical = image.viewPoint(fromCanvas: point) else { return nil }
        return canvas.viewPoint(fromCanvas: logical)
    }
    public func imagePoint(fromView point: ExplanationVector3, viewportID: UUID) -> ExplanationVector3? {
        guard let logical = canvas.canvasPoint(fromView: point, viewportID: viewportID) else { return nil }
        return image.canvasPoint(fromView: logical, viewportID: viewportID)
    }
    public func imageDelta(fromView delta: ExplanationVector3) -> ExplanationVector3? {
        guard ExplanationCoordinateValidation.point(delta) else { return nil }
        return .init(x: delta.x / scale, y: delta.y / scale)
    }
}

private enum ExplanationCoordinateValidation {
    static func point(_ p: ExplanationVector3) -> Bool {
        p.x.isFinite && p.y.isFinite && p.z == 0 && abs(p.x) <= 10_000_000 && abs(p.y) <= 10_000_000
    }
    static func point(_ p: ExplanationVector3, in size: ExplanationSize2) -> Bool {
        point(p) && p.x >= 0 && p.y >= 0 && p.x <= size.width && p.y <= size.height
    }
    static func size(_ s: ExplanationSize2) -> Bool {
        s.width.isFinite && s.height.isFinite && s.width >= 1 && s.height >= 1 && s.width <= 131_072 && s.height <= 131_072
    }
    static func rect(_ r: ExplanationRect) -> Bool {
        point(.init(x: r.x, y: r.y)) && size(.init(width: r.width, height: r.height))
            && point(.init(x: r.x + r.width, y: r.y + r.height))
    }
}
