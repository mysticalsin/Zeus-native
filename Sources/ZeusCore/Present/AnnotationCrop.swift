import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// O11: send only the marked crop to the brain, not the full display shot.
public enum AnnotationCrop {
    public static func croppedShot(from shot: ScreenShot, pixelRect: CGRect) -> ScreenShot? {
        // The stored size keeps a negative width so intersection can flip it around the origin.
        let storedWidth = Double(pixelRect.size.width)
        let storedHeight = Double(pixelRect.size.height)
        guard AnnotationCropBox.acceptsMark(width: storedWidth, height: storedHeight),
              let source = jpegImage(from: shot.jpegData) else { return nil }
        guard let clip = AnnotationCropBox.clip(
            x: Double(pixelRect.origin.x),
            y: Double(pixelRect.origin.y),
            width: storedWidth,
            height: storedHeight,
            imageWidth: source.width,
            imageHeight: source.height
        ) else { return nil }
        let rect = CGRect(x: clip.x, y: clip.y, width: clip.width, height: clip.height)
        guard let cropped = source.cropping(to: rect),
              let jpeg = jpegData(from: cropped, quality: AnnotationCropBox.jpegQuality) else { return nil }
        return ScreenShot(
            jpegData: jpeg,
            label: AnnotationCropBox.markedLabel(shot.label),
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
