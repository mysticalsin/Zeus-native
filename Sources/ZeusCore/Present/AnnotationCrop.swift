import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// O11: send only the marked crop to the brain, not the full display shot.
public enum AnnotationCrop {
    public static func croppedShot(from shot: ScreenShot, pixelRect: CGRect) -> ScreenShot? {
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let source = jpegImage(from: shot.jpegData) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let clip = pixelRect.intersection(bounds)
        guard !clip.isNull, clip.width >= 1, clip.height >= 1,
              let cropped = source.cropping(to: clip),
              let jpeg = jpegData(from: cropped, quality: 0.85) else { return nil }
        return ScreenShot(
            jpegData: jpeg,
            label: shot.label + " (marked crop)",
            pixelWidth: cropped.width,
            pixelHeight: cropped.height,
            displayFrame: shot.displayFrame
        )
    }
}

private func jpegImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func jpegData(from image: CGImage, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}
