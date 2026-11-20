import Foundation

public struct PortalConversionOutput: Equatable, Sendable {
    public var fileName: String
    public var bytes: Data
    public var kind: PortalConversionKind

    public init(fileName: String, bytes: Data, kind: PortalConversionKind) {
        self.fileName = fileName
        self.bytes = bytes
        self.kind = kind
    }
}

public enum PortalTextConversion {
    public static func utf8(_ data: Data, limit: Int = PortalLimits.maxConversionBytes) -> Result<Data, PortalDropFailure> {
        var body = data
        if body.starts(with: Data([0xEF, 0xBB, 0xBF])) { body = Data(body.dropFirst(3)) }
        guard let text = String(data: body, encoding: .utf8) else { return .failure(.invalidContents) }
        if text.unicodeScalars.contains(where: { $0.value == 0 }) { return .failure(.invalidContents) }
        let folded = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let output = Data(folded.precomposedStringWithCanonicalMapping.utf8)
        if output.count > limit { return .failure(.outputTooLarge) }
        if output.isEmpty { return .failure(.invalidContents) }
        return .success(output)
    }
}

public enum PortalPNG {
    private static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    public static func sanitize(_ data: Data) -> Result<Data, PortalDropFailure> {
        guard data.starts(with: signature) else { return .failure(.invalidContents) }
        var offset = 8
        var sawHeader = false
        var sawEnd = false
        var end = 8
        while offset + 12 <= data.count {
            let lengthValue = u32(data, offset)
            guard lengthValue <= 0x7FFF_FFFF, data.count >= offset + 12 else { return .failure(.invalidContents) }
            let length = Int(lengthValue)
            guard length <= data.count - offset - 12 else { return .failure(.invalidContents) }
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let covered = data[(offset + 4)..<(offset + 8 + length)]
            let stored = u32(data, offset + 8 + length)
            guard stored == PortalChecksum.crc32(Data(covered)) else { return .failure(.invalidContents) }
            if !sawHeader {
                guard type == "IHDR", length == 13 else { return .failure(.invalidContents) }
                let width = Int(u32(data, offset + 8))
                let height = Int(u32(data, offset + 12))
                if width <= 0 || height <= 0 { return .failure(.invalidContents) }
                if !PortalImageBounds.admit(width: width, height: height) { return .failure(.tooLarge) }
                sawHeader = true
            } else if type == "IHDR" {
                return .failure(.invalidContents)
            } else if isCritical(type), !["PLTE", "IDAT", "IEND"].contains(type) {
                return .failure(.invalidContents)
            }
            offset += 12 + length
            end = offset
            if type == "IEND" {
                sawEnd = true
                break
            }
        }
        guard sawHeader, sawEnd else { return .failure(.invalidContents) }
        return .success(Data(data.prefix(end)))
    }

    private static func isCritical(_ type: String) -> Bool {
        guard let first = type.unicodeScalars.first else { return true }
        return CharacterSet.uppercaseLetters.contains(first)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

enum PortalMagic {
    static func isImage(_ data: Data) -> Bool {
        matches(data, type: .png) || matches(data, type: .jpeg) || matches(data, type: .gif) || matches(data, type: .tiff) || matches(data, type: .heic)
    }

    static func matches(_ data: Data, type: PortalFileType) -> Bool {
        switch type {
        case .png:
            return data.starts(with: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        case .jpeg:
            return data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
        case .gif:
            return data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
        case .tiff:
            return data.starts(with: Data([0x49, 0x49, 0x2A, 0x00])) || data.starts(with: Data([0x4D, 0x4D, 0x00, 0x2A]))
        case .heic:
            guard data.count >= 12, String(decoding: data[4..<8], as: UTF8.self) == "ftyp" else { return false }
            let brand = String(decoding: data[8..<12], as: UTF8.self)
            return ["heic", "heix", "hevc", "hevx", "heif", "mif1", "msf1"].contains(brand)
        case .plainText, .unknown:
            return false
        }
    }
}

public enum PortalConverter {
    public static func convert(file: PortalAdmittedFile, bytes: Data, codecs: PortalCodecs = .standard) -> Result<PortalConversionOutput, PortalDropFailure> {
        if Int64(bytes.count) != file.sizeBytes { return .failure(.sizeMismatch) }
        let produced: Result<Data, PortalDropFailure>
        switch file.type {
        case .plainText:
            if PortalMagic.isImage(bytes) { return .failure(.invalidContents) }
            produced = PortalTextConversion.utf8(bytes)
        case .png:
            produced = PortalPNG.sanitize(bytes)
        case .jpeg, .gif, .tiff, .heic:
            guard PortalMagic.matches(bytes, type: file.type) else { return .failure(.invalidContents) }
            switch codecs.images.pngData(from: bytes, type: file.type) {
            case .failure(let error): return .failure(error)
            case .success(let data): produced = PortalPNG.sanitize(data)
            }
        case .unknown:
            return .failure(.typeNotAllowed)
        }
        switch produced {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            switch PortalOutputName.make(displayName: file.displayName, kind: file.outputKind) {
            case .failure(let error):
                return .failure(error)
            case .success(let name):
                return .success(PortalConversionOutput(fileName: name, bytes: data, kind: file.outputKind))
            }
        }
    }
}
