import Foundation
#if canImport(Darwin)
import CryptoKit
import Darwin
import Security
#endif

/// The Security framework side of peer identity: reads a connected peer's code signature from its
/// audit token and hands the facts to `PeerBinaryRule`. Everything that can fail refuses.
/// Nothing here logs a path, a token or any signing material beyond the refusal reason.
/// Signing identifiers for one direction of a socket. The file name is the identifier `scripts/bundle.sh` passes.
public enum SocketPeerIdentifier {
    public static let app = ZeusPaths.bundleIdentifier
    public static let command = "zeus"
    public static let hook = "zeus-hook"
    public static let bridge = "zeus-bridge"
    public static let helpers = [command, hook, bridge]

    /// The app's server allows a helper only when that helper's own identifier matches.
    public static func acceptHelper(_ auditToken: Data?) -> PeerVerdict {
        var denial: PeerVerdict = .deny("peer is not a Zeus helper")
        for name in helpers {
            let verdict = PeerSigning.verifyApp(auditToken: auditToken, expectedPeerIdentifier: name)
            if verdict.isAllowed { return verdict }
            denial = verdict
        }
        return denial
    }
}

public enum PeerSigning {
    /// The verifier the app's socket uses for a helper. Each helper carries its own identifier.
    /// A client checking the app passes `SocketPeerIdentifier.app` instead.
    public static let defaultVerifier: PeerVerifier = { SocketPeerIdentifier.acceptHelper($0) }

    #if canImport(Darwin)
    /// True when the process behind `auditToken` is this app's own program.
    /// `expectedPeerIdentifier` is the signing identifier the peer must carry, for a server whose only client is the app.
    /// `trustShippingBundle` lets an installed ad hoc bridge accept the app bundle that ships a bridge of its name;
    /// only the bridge's verifier sets it.
    public static func verifyApp(auditToken: Data?, expectedPeerIdentifier: String? = nil, trustShippingBundle: Bool = false) -> PeerVerdict {
        guard let token = auditToken, token.count == 32 else { return .deny("peer audit token unavailable") }
        let own = OwnApp.current
        // A team or a local certificate is checked against the running peer in the same call that validates it, so a
        // certificate that only names the team, or a file swapped after a separate read, cannot pass as the app.
        let requirement = PeerRequirement.text(ownTeam: own.signature?.teamIdentifier, ownLeafSHA1: own.leafSHA1,
                                               ownIsAdHoc: own.signature?.isAdHoc ?? true, peerIdentifier: expectedPeerIdentifier)
        guard let peer = describePeer(auditToken: token, requirement: requirement) else { return .deny("peer code signature unreadable") }
        // An installed ad hoc helper has no bundle of its own: the app that shipped it is the peer, and the names of
        // the valid ad hoc programs in that bundle's Helpers are what tie the two together. Read only for that case,
        // never at idle, and never for a signed build, which compares its team or certificate instead.
        var peerBundleHelpers = Set<String>()
        if trustShippingBundle, own.bundlePath == nil, own.signature?.isAdHoc == true, own.signature?.identifier?.isEmpty == false,
           let path = peer.path, let bundle = AppBundleLocator.bundlePath(forExecutable: path) {
            peerBundleHelpers = Set(signatures(bundle: bundle, folders: ["Contents/Helpers"], requireValid: true)
                .filter(\.isAdHoc).compactMap(\.identifier))
        }
        let installed = resolve(ZeusPaths.binDirectory.path) ?? ZeusPaths.binDirectory.path
        return PeerBinaryRule.decide(own: own.signature, peer: peer.signature, peerExecutablePath: peer.path,
                                     ownBundlePath: own.bundlePath, ownExecutableDirectory: own.executableDirectory,
                                     ownBundleCDHashes: own.bundleCDHashes, peerBundleHelperIdentifiers: peerBundleHelpers,
                                     installedHelpersDirectory: installed, expectedPeerIdentifier: expectedPeerIdentifier,
                                     trustShippingBundle: trustShippingBundle)
    }

    /// Reads this program's own identity now and keeps it. A long-running program (the bridge Chrome keeps alive
    /// while the app is rebuilt or updated) must call this at start: once the file on disk has been replaced the
    /// signature of the running copy can no longer be validated against it, and every peer would be refused.
    @discardableResult
    public static func captureOwnIdentity() -> CodeSignature? { OwnApp.current.signature }

    // MARK: This program

    private struct OwnApp: Sendable {
        var signature: CodeSignature?
        var bundlePath: String?
        var executableDirectory: String?
        var bundleCDHashes: Set<String>
        /// SHA-1 of this program's leaf signing certificate, hex: what `certificate leaf = H"..."` names.
        var leafSHA1: String?

        /// Read on the first use, then kept: a program that never serves a signed-peer command never reads it, and
        /// `captureOwnIdentity` reads it at start for one that does.
        static let current: OwnApp = read()

        private static func read() -> OwnApp {
            var signature: CodeSignature?
            var leafSHA1: String?
            var selfCode: SecCode?
            if SecCodeCopySelf(SecCSFlags(), &selfCode) == errSecSuccess, let selfCode {
                let described = PeerSigning.describe(code: selfCode, requirement: nil)
                signature = described?.signature
                leafSHA1 = described?.leafSHA1
            }
            let path = PeerCheck.executablePath(pid: getpid()).flatMap(PeerSigning.resolve)
            let bundle = path.flatMap(AppBundleLocator.bundlePath(forExecutable:))
            let directory = path.map { ($0 as NSString).deletingLastPathComponent }
            // Cdhashes of the bundled programs only matter when the app has no team to compare.
            var hashes = Set<String>()
            if signature?.teamIdentifier?.isEmpty ?? true, let bundle {
                hashes = Set(PeerSigning.signatures(bundle: bundle, folders: ["Contents/MacOS", "Contents/Helpers"], requireValid: false)
                    .compactMap(\.cdHash))
            }
            return OwnApp(signature: signature, bundlePath: bundle, executableDirectory: directory, bundleCDHashes: hashes,
                          leafSHA1: leafSHA1)
        }
    }

    // MARK: Reading a signature

    /// The signatures of the programs in `folders` of `bundle`. For this app's own bundle the declared signature
    /// is enough (the peer must still pass its own check, which hashes its real content). For a peer's bundle
    /// each program must also pass a static validity check, so a signature is only listed for intact code.
    fileprivate static func signatures(bundle: String, folders: [String], requireValid: Bool) -> [CodeSignature] {
        var found: [CodeSignature] = []
        for folder in folders {
            let directory = bundle + "/" + folder
            for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
                var staticCode: SecStaticCode?
                let url = URL(fileURLWithPath: directory + "/" + name)
                guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { continue }
                if requireValid {
                    let flags = SecCSFlags(rawValue: UInt32(kSecCSDoNotValidateResources))
                    guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else { continue }
                }
                if let signature = describe(staticCode: staticCode, valid: true)?.signature { found.append(signature) }
            }
        }
        return found
    }

    private struct Described {
        var signature: CodeSignature
        var mainExecutable: String?
        var leafSHA1: String?
    }

    private struct PeerDescription {
        var signature: CodeSignature
        var path: String?
    }

    private static func describePeer(auditToken: Data, requirement: String?) -> PeerDescription? {
        var guest: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guest) == errSecSuccess, let guest,
              let described = describe(code: guest, requirement: requirement) else { return nil }
        // The running image's path is looked up by the whole audit token, which carries the pid version, so a pid
        // reused by another process after the peer exits finds nothing. A bare pid lookup is never used.
        let path = (PeerCheck.executablePath(auditToken: auditToken) ?? described.mainExecutable).flatMap(resolve)
        return PeerDescription(signature: described.signature, path: path)
    }

    /// `requirement`, when given, is checked against the running code itself. Failing to build it counts as not met.
    ///
    /// One validity call decides the common case: code that passes with the requirement is valid by that same call. Only
    /// code that fails it is asked again without one, to tell a broken signature from an identity that is simply not ours.
    /// Default flags: passing `kSecCSDoNotValidateResources` made a validly signed running process read as invalid.
    private static func describe(code: SecCode, requirement: String?) -> Described? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var satisfied = false
        var compiled: SecRequirement?
        if let requirement, SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &compiled) == errSecSuccess,
           let compiled {
            let flags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate))
            satisfied = SecCodeCheckValidity(code, flags, compiled) == errSecSuccess
        }
        let valid = satisfied || SecCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess
        return describe(staticCode: staticCode, valid: valid, satisfiesRequirement: satisfied)
    }

    private static func describe(staticCode: SecStaticCode, valid: Bool, satisfiesRequirement: Bool = false) -> Described? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return Described(signature: CodeSignature(isValid: false), mainExecutable: nil)
        }
        let adHocFlag: UInt32 = 0x2 // kSecCodeSignatureAdhoc
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let leafData = certificates?.first.map { SecCertificateCopyData($0) as Data }
        let leaf = leafData.map { hex(SHA256.hash(data: $0)) }
        let signature = CodeSignature(
            isValid: valid,
            identifier: info[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            isAdHoc: codeFlags & adHocFlag != 0,
            certificateHash: leaf,
            cdHash: (info[kSecCodeInfoUnique as String] as? Data).map { hex($0) },
            satisfiesIdentityRequirement: satisfiesRequirement)
        return Described(signature: signature, mainExecutable: (info[kSecCodeInfoMainExecutable as String] as? URL)?.path,
                         leafSHA1: leafData.map { hex(Insecure.SHA1.hash(data: $0)) })
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
    /// `expectedPeerIdentifier` is the signing identifier the peer must carry, for a server whose only client is the app.
    public static func verifyApp(auditToken: Data?, expectedPeerIdentifier: String? = nil, trustShippingBundle: Bool = false) -> PeerVerdict { .deny("peer signatures are not available on this platform") }
    #endif
}
