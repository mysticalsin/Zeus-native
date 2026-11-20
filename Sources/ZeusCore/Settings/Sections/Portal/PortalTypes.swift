import Foundation

/// Caps for a local drop conversion. 8 MiB is the whole file, input and output.
public enum PortalLimits {
    public static let maxConversionBytes = 8 * 1024 * 1024
    public static let maxTrayItems = 100
    public static let maxImagePixels = 16_000_000
}

public enum PortalFileType: String, Equatable, Sendable, CaseIterable {
    case plainText, png, jpeg, gif, tiff, heic, unknown
}

public enum PortalFileTypes {
    public static func fromExtension(_ name: String) -> PortalFileType {
        let ext = (name as NSString).pathExtension
        switch (ext.isEmpty ? name : ext).lowercased() {
        case "txt", "text": return .plainText
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "gif": return .gif
        case "tif", "tiff": return .tiff
        case "heic", "heif": return .heic
        default: return .unknown
        }
    }
}

public enum PortalConversionKind: Equatable, Sendable {
    case utf8Text, png
}

public enum PortalDropFailure: Error, Equatable, Sendable {
    case escapesSandbox
    case notAbsolute
    case emptyPath
    case symlink
    case notRegularFile
    case hardLink
    case wrongOwner
    case unresolved
    case empty
    case tooLarge
    case unreadableSize
    case typeNotAllowed
    case typeMismatch
    case invalidContents
    case sizeMismatch
    case outputTooLarge
    case systemCodecUnavailable
    case trayFull
    case outputEscapesSandbox
    case unsafeName
    case notAdmitted
    case insecureSandbox
    case writeFailed
}

public enum PortalCopy {
    public static func sentence(_ failure: PortalDropFailure) -> String {
        switch failure {
        case .escapesSandbox: "That file is outside the folder this Mac is allowed to use."
        case .notAbsolute: "The file needs a full path."
        case .emptyPath: "The file has no path."
        case .symlink: "Symbolic links are not converted."
        case .notRegularFile: "Only a regular file can be converted."
        case .hardLink: "A file with more than one name is not converted."
        case .wrongOwner: "Only a file owned by this user can be converted."
        case .unresolved: "The file could not be resolved."
        case .empty: "The file is empty."
        case .tooLarge: "The file is larger than 8 MB."
        case .unreadableSize: "The file size could not be read."
        case .typeNotAllowed: "This file type is not converted."
        case .typeMismatch: "The file type does not match its name."
        case .invalidContents: "The file contents are not valid for that type."
        case .sizeMismatch: "The file changed size before it could be converted."
        case .outputTooLarge: "The converted file would be larger than 8 MB."
        case .systemCodecUnavailable: "This Mac cannot convert that image locally."
        case .trayFull: "The file tray is full."
        case .outputEscapesSandbox: "The converted file would be saved outside the allowed folder."
        case .unsafeName: "That file name is not safe to save."
        case .notAdmitted: "The file was not accepted."
        case .insecureSandbox: "The conversion folder is not private to this user."
        case .writeFailed: "The converted file could not be saved."
        }
    }
}

public enum PortalSectionMetrics {
    public static let panelPadding = 32.0
    public static let cardSpacing = 28.0
    public static let rowHeight = 52.0
    public static let topbarTab = 8

    public static func animationDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : MotionTokens.crossfadeDuration
    }

    public static func pressScale(reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : MotionTokens.pressScale
    }
}

public enum PortalPhaseName {
    public static func name(_ phase: PortalDropFlow.Phase) -> String {
        switch phase {
        case .idle: "idle"
        case .received: "received"
        case .converting: "converting"
        case .done: "done"
        case .failed: "failed"
        }
    }
}

/// Image pixel cap. The product is refused before a multiply can overflow.
public enum PortalImageBounds {
    public static let maxPixels = PortalLimits.maxImagePixels

    public static func admit(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= maxPixels, height <= maxPixels else { return false }
        return width <= maxPixels / height
    }
}

/// PNG's CRC-32 (ISO-HDLC). Used to check chunks, not as a hash of a secret.
public enum PortalChecksum {
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 { crc = (crc >> 1) ^ 0xEDB8_8320 }
                else { crc >>= 1 }
            }
        }
        return ~crc
    }
}

public enum PortalToolBoundary {
    /// Split so this file does not itself contain the markers it rejects.
    public static func violations(in source: String) -> [String] {
        let markers = [
            "Pro" + "cess(",
            "URL" + "Session",
            "/b" + "in/",
            "NST" + "ask",
            "posix_" + "spawn",
            "sys" + "tem(",
            "po" + "pen(",
        ]
        return markers.filter { source.contains($0) }
    }
}

public enum PortalOutputName {
    public static func make(displayName: String, kind: PortalConversionKind) -> Result<String, PortalDropFailure> {
        let ext = kind == .utf8Text ? "txt" : "png"
        let ns = displayName as NSString
        let stem = ns.pathExtension.isEmpty ? displayName : ns.deletingPathExtension
        let cleaned = FlingNames.clean(stem, reserve: ext.utf8.count + 1)
        let name = cleaned + "." + ext
        guard case .success = FlingNames.validate(name), !name.contains("/"), !name.contains("\\") else {
            return .failure(.unsafeName)
        }
        return .success(name)
    }
}

/// Still-image transcode. The core default refuses; a system framework supplies the bytes on a Mac.
public protocol PortalImageCoding: Sendable {
    func pngData(from data: Data, type: PortalFileType) -> Result<Data, PortalDropFailure>
}

public struct PortalUnavailableImageCoding: PortalImageCoding, Sendable {
    public init() {}
    public func pngData(from data: Data, type: PortalFileType) -> Result<Data, PortalDropFailure> {
        .failure(.systemCodecUnavailable)
    }
}

public struct PortalCodecs: Sendable {
    public var images: any PortalImageCoding
    public init(images: any PortalImageCoding) { self.images = images }
    public static var standard: PortalCodecs { PortalCodecs(images: PortalUnavailableImageCoding()) }
}
