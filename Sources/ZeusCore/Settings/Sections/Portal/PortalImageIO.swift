import Foundation

#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Local still-image transcode through the system image frameworks. One frame, bounded pixels, no network.
public struct PortalImageIOCoding: PortalImageCoding {
    public init() {}

    public func pngData(from data: Data, type: PortalFileType) -> Result<Data, PortalDropFailure> {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return .failure(.invalidContents) }
        guard CGImageSourceGetCount(source) == 1 else { return .failure(.invalidContents) }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .failure(.invalidContents)
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        if width <= 0 || height <= 0 { return .failure(.invalidContents) }
        if !PortalImageBounds.admit(width: width, height: height) { return .failure(.tooLarge) }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return .failure(.invalidContents) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return .failure(.systemCodecUnavailable)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return .failure(.invalidContents) }
        let produced = out as Data
        if produced.isEmpty { return .failure(.invalidContents) }
        if produced.count > PortalLimits.maxConversionBytes { return .failure(.outputTooLarge) }
        return .success(produced)
    }
}
#endif
