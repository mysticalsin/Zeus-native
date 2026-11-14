import Foundation
#if canImport(Darwin)
import CryptoKit
import Darwin
import Security
#endif

/// The Security framework side of peer identity: reads a connected peer's code signature from its
/// audit token and hands the facts to `PeerBinaryRule`. Everything that can fail refuses.
/// Nothing here logs a path, a token or any signing material beyond the refusal reason.
public enum PeerSigning {
    /// The verifier a server uses unless a test injects another.
    public static let defaultVerifier: PeerVerifier = { PeerSigning.verifyApp(auditToken: $0) }

    #if canImport(Darwin)
    /// True when the process behind `auditToken` is this app's own program.
    public static func verifyApp(auditToken: Data?) -> PeerVerdict {
        guard let token = auditToken, token.count == 32 else { return .deny("peer audit token unavailable") }
        guard let peer = describePeer(auditToken: token) else { return .deny("peer code signature unreadable") }
        let own = OwnApp.current
        return PeerBinaryRule.decide(own: own.signature, peer: peer.signature, peerExecutablePath: peer.path,
                                     ownBundlePath: own.bundlePath, ownExecutableDirectory: own.executableDirectory,
                                     ownBundleCDHashes: own.bundleCDHashes)
    }

    // MARK: This program

    private struct OwnApp: Sendable {
        var signature: CodeSignature?
        var bundlePath: String?
        var executableDirectory: String?
        var bundleCDHashes: Set<String>

        /// Read on the first verification, then kept. A process that never serves a signed-peer command never reads it.
        static let current: OwnApp = read()

        private static func read() -> OwnApp {
            var signature: CodeSignature?
            var selfCode: SecCode?
            if SecCodeCopySelf(SecCSFlags(), &selfCode) == errSecSuccess, let selfCode {
                signature = PeerSigning.describe(code: selfCode)?.signature
            }
            let path = PeerCheck.executablePath(pid: getpid()).flatMap(PeerSigning.resolve)
            let bundle = path.flatMap(AppBundleLocator.bundlePath(forExecutable:))
            let directory = path.map { ($0 as NSString).deletingLastPathComponent }
            // Cdhashes of the bundled programs only matter when the app has no team to compare.
            var hashes = Set<String>()
            if signature?.teamIdentifier?.isEmpty ?? true, let bundle {
                hashes = bundledCDHashes(bundle: bundle)
            }
            return OwnApp(signature: signature, bundlePath: bundle, executableDirectory: directory, bundleCDHashes: hashes)
        }

        private static func bundledCDHashes(bundle: String) -> Set<String> {
            var hashes = Set<String>()
            for folder in ["Contents/MacOS", "Contents/Helpers"] {
                let directory = bundle + "/" + folder
                for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
                    var staticCode: SecStaticCode?
                    let url = URL(fileURLWithPath: directory + "/" + name)
                    // Only the hash the signature declares is read. It is not a trust decision on its own: a peer
                    // must still pass its own signature check, which hashes its real content.
                    guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode,
                          let hash = PeerSigning.describe(staticCode: staticCode, valid: true)?.signature.cdHash else { continue }
                    hashes.insert(hash)
                }
            }
            return hashes
        }
    }

    // MARK: Reading a signature

    private struct Described {
        var signature: CodeSignature
        var mainExecutable: String?
    }

    private struct PeerDescription {
        var signature: CodeSignature
        var path: String?
    }

    private static func describePeer(auditToken: Data) -> PeerDescription? {
        var guest: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guest) == errSecSuccess, let guest,
              let described = describe(code: guest) else { return nil }
        // The running image's path comes from the kernel (pid word of the audit token), not from the file system lookup.
        let pid = auditToken.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 5 * MemoryLayout<UInt32>.size, as: UInt32.self) }
        let kernelPath = pid > 0 ? PeerCheck.executablePath(pid: pid_t(pid)) : nil
        let path = (kernelPath ?? described.mainExecutable).flatMap(resolve)
        return PeerDescription(signature: described.signature, path: path)
    }

    private static func describe(code: SecCode) -> Described? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        return describe(staticCode: staticCode, valid: SecCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess)
    }

    private static func describe(staticCode: SecStaticCode, valid: Bool) -> Described? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return Described(signature: CodeSignature(isValid: false), mainExecutable: nil)
        }
        let adHocFlag: UInt32 = 0x2 // kSecCodeSignatureAdhoc
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let leaf = certificates?.first.map { hex(SHA256.hash(data: SecCertificateCopyData($0) as Data)) }
        let signature = CodeSignature(
            isValid: valid,
            identifier: info[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            isAdHoc: codeFlags & adHocFlag != 0,
            certificateHash: leaf,
            cdHash: (info[kSecCodeInfoUnique as String] as? Data).map { hex($0) })
        return Described(signature: signature, mainExecutable: (info[kSecCodeInfoMainExecutable as String] as? URL)?.path)
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func resolve(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
    #else
    public static func verifyApp(auditToken: Data?) -> PeerVerdict { .deny("peer signatures are not available on this platform") }
    #endif
}
