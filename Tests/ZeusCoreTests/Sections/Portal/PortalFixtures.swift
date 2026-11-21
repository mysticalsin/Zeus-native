import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ZeusCore

enum PortalFixtures {
    static let root = "/sandbox/inbox"
    static let maxBytes = PortalLimits.maxConversionBytes

    static func claim(
        name: String = "note.txt",
        type: PortalFileType = .plainText,
        size: Int64 = 4,
        root: String = PortalFixtures.root,
        path: String? = nil,
        canonical: String? = nil,
        symlink: Bool = false,
        symlinkAncestor: Bool = false,
        regular: Bool = true,
        links: Int = 1,
        owner: Bool = true
    ) -> PortalFileClaim {
        let full = path ?? "\(root)/\(name)"
        return PortalFileClaim(
            displayName: name,
            sandboxRoot: root,
            path: full,
            canonicalPath: canonical ?? full,
            isSymbolicLink: symlink,
            hasSymbolicLinkAncestor: symlinkAncestor,
            isRegularFile: regular,
            linkCount: links,
            sizeBytes: size,
            declaredType: type,
            ownerMatches: owner
        )
    }

    static func output(
        name: String = "note.txt",
        bytes: Data = Data("note".utf8),
        kind: PortalConversionKind = .utf8Text
    ) -> PortalConversionOutput {
        PortalConversionOutput(fileName: name, bytes: bytes, kind: kind)
    }

    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("portal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: url.path)
        return url
    }

    static func write(_ name: String, bytes: Data, in folder: URL, mode: Int = 0o600) throws -> String {
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
        return url.path
    }

    static func hardLink(from source: String, to destination: String) -> Bool {
        source.withCString { src in
            destination.withCString { dst in
                link(src, dst) == 0
            }
        }
    }

    static func png(width: UInt32 = 1, height: UInt32 = 1, trailing: Data = Data()) -> Data {
        var ihdr = Data()
        func be(_ value: UInt32) -> Data {
            var big = value.bigEndian
            return withUnsafeBytes(of: &big) { Data($0) }
        }
        ihdr.append(be(width))
        ihdr.append(be(height))
        ihdr.append(contentsOf: [8, 2, 0, 0, 0])
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(chunk("IHDR", ihdr))
        data.append(chunk("IDAT", Data([0])))
        data.append(chunk("IEND", Data()))
        data.append(trailing)
        return data
    }

    static func chunk(_ type: String, _ payload: Data) -> Data {
        var big = UInt32(payload.count).bigEndian
        var data = withUnsafeBytes(of: &big) { Data($0) }
        let kind = Data(type.utf8)
        data.append(kind)
        data.append(payload)
        var crc = PortalChecksum.crc32(kind + payload).bigEndian
        data.append(withUnsafeBytes(of: &crc) { Data($0) })
        return data
    }
}

struct PortalSplitMix: Sendable {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func int(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
