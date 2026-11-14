import Foundation

/// What the Security framework says about one program's code signature. The adapter in
/// `PeerSigning` fills it in; the rule below only reads it, so every decision is testable.
public struct CodeSignature: Equatable, Sendable {
    /// The signature is intact (`SecCodeCheckValidity` passed). Unsigned or tampered code is never valid.
    public var isValid: Bool
    public var identifier: String?
    /// The Apple team that signed it. Nil for ad hoc, locally signed and Apple platform programs.
    public var teamIdentifier: String?
    public var isAdHoc: Bool
    /// SHA-256 of the leaf signing certificate, hex. Nil for ad hoc signatures.
    public var certificateHash: String?
    /// The code directory hash (cdhash), hex: the identity of one exact build of one program.
    public var cdHash: String?
    /// The running code met `PeerRequirement` in the same call that checked it, so its identity is anchored in
    /// Apple's chain (a team) or in the exact certificate (a local identity), not just claimed in its signing
    /// information. False when no requirement applied or it was not met.
    public var satisfiesIdentityRequirement: Bool

    public init(isValid: Bool, identifier: String? = nil, teamIdentifier: String? = nil, isAdHoc: Bool = false,
                certificateHash: String? = nil, cdHash: String? = nil, satisfiesIdentityRequirement: Bool = false) {
        self.isValid = isValid
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.isAdHoc = isAdHoc
        self.certificateHash = certificateHash
        self.cdHash = cdHash
        self.satisfiesIdentityRequirement = satisfiesIdentityRequirement
    }

    fileprivate var team: String? {
        guard let teamIdentifier, !teamIdentifier.isEmpty else { return nil }
        return teamIdentifier
    }
}

/// The code requirement a peer must meet, built from this program's own identity. The adapter hands it to
/// `SecCodeCheckValidity` together with the running code, so validity and identity are one check, and a
/// signing certificate that merely carries the team identifier as a name does not pass.
public enum PeerRequirement {
    /// - A team-signed program: the peer's certificate chains to Apple (`anchor apple generic`) and its leaf names
    ///   the same team.
    /// - A locally signed program: the peer's leaf certificate is the very certificate this program was signed with.
    /// - `peerIdentifier`, when given, is the signing identifier the peer must carry too.
    ///
    /// Nil when this program has no identity a requirement can name (an ad hoc build) or an input is malformed;
    /// the caller then treats every peer as not meeting it.
    public static func text(ownTeam: String?, ownLeafSHA1: String?, ownIsAdHoc: Bool, peerIdentifier: String?) -> String? {
        var suffix = ""
        if let peerIdentifier {
            guard isName(peerIdentifier, allowing: "._-") else { return nil }
            suffix = " and identifier \"\(peerIdentifier)\""
        }
        if let team = ownTeam, !team.isEmpty {
            guard isName(team, allowing: "") else { return nil }
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" + suffix
        }
        guard !ownIsAdHoc, let sha1 = ownLeafSHA1?.lowercased(), sha1.count == 40,
              sha1.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "certificate leaf = H\"\(sha1)\"" + suffix
    }

    /// Letters, digits and the given extras only, so nothing typed into a requirement can add a clause.
    private static func isName(_ text: String, allowing extra: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || extra.unicodeScalars.contains(scalar)))
        }
    }
}

/// Component-wise path containment. A prefix test would accept `/Applications/Zeus.app.evil`.
public enum PathContainment {
    /// True when `path` is strictly below `root`. Both must be absolute and free of `..`; the
    /// filesystem root is never a usable root. Callers pass paths that are already symlink-resolved.
    public static func isInside(_ path: String, root: String) -> Bool {
        guard let path = components(path), let root = components(root), !root.isEmpty, path.count > root.count else { return false }
        return Array(path.prefix(root.count)) == root
    }

    /// The components of an absolute path with no `..`; nil otherwise.
    static func components(_ text: String) -> [String]? {
        guard text.hasPrefix("/"), !text.contains("\u{0}") else { return nil }
        let parts = text.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.contains("..") else { return nil }
        return parts.filter { $0 != "." }
    }
}

public enum AppBundleLocator {
    /// The `.app` folder an executable runs from (`Zeus.app` for `Zeus.app/Contents/MacOS/Zeus` and for
    /// the helpers in `Contents/Helpers`), or nil for a loose binary such as a SwiftPM build product.
    public static func bundlePath(forExecutable path: String) -> String? {
        guard let parts = PathContainment.components(path), parts.count >= 3 else { return nil }
        // The executable itself never counts, and the folder after `.app` must be `Contents`.
        for index in stride(from: parts.count - 2, through: 0, by: -1) where parts[index].hasSuffix(".app") && parts[index].count > 4 {
            guard index + 1 < parts.count - 1, parts[index + 1] == "Contents" else { continue }
            return "/" + parts[0...index].joined(separator: "/")
        }
        return nil
    }
}

/// Decides whether a socket peer is this app's own program, by what it is: a valid code signature
/// that ties it to this app, never by the name of its file.
public enum PeerBinaryRule {
    /// - Parameters:
    ///   - own: this program's signature (the server side), as read when the program started.
    ///   - peer: the peer's signature, nil when it could not be read.
    ///   - peerExecutablePath: the peer's executable after symlink resolution.
    ///   - ownBundlePath: the `.app` folder this program runs from, if any.
    ///   - ownExecutableDirectory: the folder holding this program (the build products folder for a loose binary).
    ///   - ownBundleCDHashes: cdhashes of the programs shipped inside this app, so an installed copy of a bundled helper still matches.
    ///   - peerBundleHelperIdentifiers: signing identifiers of the ad hoc programs shipped in the peer's own
    ///     `Contents/Helpers`, each one checked valid. Only read when this program is an ad hoc build with no
    ///     bundle (the installed bridge) and the peer runs inside an `.app`.
    ///   - installedHelpersDirectory: the folder the app copies its helpers into. Any program of this user can
    ///     write there, so it is never trusted as a build products folder.
    ///   - expectedPeerIdentifier: the signing identifier the peer must carry (the app's bundle identifier),
    ///     for a server whose only client is the app. Nil leaves the rest of the rule alone.
    ///   - trustShippingBundle: turns on the installed ad hoc bridge allowance below. Only the bridge's verifier
    ///     sets it; a loose ad hoc app serving the command socket must not accept an assembled bundle.
    ///
    /// Identity is a stable requirement, never the code directory hash of one build, because a long-running
    /// program (the bridge Chrome keeps alive) outlives the app build that shipped it. When this app is
    /// signed with a team identifier the peer must carry the same one. When it is locally signed (a
    /// certificate without a team) the peer must be signed with the same certificate, or live inside this
    /// app's bundle or next to this loose program, or be an exact copy of a bundled helper. An ad hoc build has
    /// no identity beyond a location, so it also trusts an installed helper's app (a peer inside an `.app`
    /// whose Helpers hold a valid ad hoc program of this program's name): a same-user program could still
    /// assemble such a bundle, which is why a signed build compares teams or certificates instead.
    /// Every other case, and every missing input, refuses.
    public static func decide(own: CodeSignature?, peer: CodeSignature?, peerExecutablePath: String?,
                              ownBundlePath: String?, ownExecutableDirectory: String?,
                              ownBundleCDHashes: Set<String> = [], peerBundleHelperIdentifiers: Set<String> = [],
                              installedHelpersDirectory: String? = nil, expectedPeerIdentifier: String? = nil,
                              trustShippingBundle: Bool = false) -> PeerVerdict {
        guard let own, own.isValid else { return .deny("own code signature unavailable") }
        guard let peer, peer.isValid else { return .deny("peer code signature missing or invalid") }
        if let expected = expectedPeerIdentifier {
            guard let identifier = peer.identifier, identifier == expected else { return .deny("peer is not the app") }
        }
        if let team = own.team {
            guard !peer.isAdHoc, peer.team == team, peer.satisfiesIdentityRequirement else {
                return .deny("peer is not signed by this app's team")
            }
            return .allow
        }
        let path = peerExecutablePath.flatMap { $0.isEmpty ? nil : $0 }
        if let path {
            let directory = isTrustedDirectory(ownExecutableDirectory, installedHelpers: installedHelpersDirectory) ? ownExecutableDirectory : nil
            for root in [ownBundlePath, directory] {
                if let root, PathContainment.isInside(path, root: root) { return .allow }
            }
        }
        if let hash = peer.cdHash, !hash.isEmpty, ownBundleCDHashes.contains(hash) { return .allow }
        if !own.isAdHoc, let certificate = own.certificateHash, !certificate.isEmpty, peer.certificateHash == certificate,
           peer.satisfiesIdentityRequirement { return .allow }
        // The installed ad hoc bridge: no bundle of its own, so the peer must be an app that ships a bridge of this name.
        if trustShippingBundle, own.isAdHoc, ownBundlePath == nil, let path, AppBundleLocator.bundlePath(forExecutable: path) != nil,
           let name = own.identifier, !name.isEmpty, peerBundleHelperIdentifiers.contains(name) { return .allow }
        return .deny("peer is not this app's program")
    }

    /// A folder holding this program is a build products folder only when it is not the installed helpers
    /// folder or inside it.
    private static func isTrustedDirectory(_ directory: String?, installedHelpers: String?) -> Bool {
        guard let directory, let installedHelpers else { return directory != nil }
        guard let own = PathContainment.components(directory), let installed = PathContainment.components(installedHelpers),
              !installed.isEmpty else { return false }
        return !(own.count >= installed.count && Array(own.prefix(installed.count)) == installed)
    }
}
