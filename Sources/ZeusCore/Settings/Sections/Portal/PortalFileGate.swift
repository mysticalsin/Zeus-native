import Foundation

/// What the platform observed about a drop. The gate trusts these fields and nothing on disk.
public struct PortalFileClaim: Equatable, Sendable {
    public var displayName: String
    public var sandboxRoot: String
    public var path: String
    public var canonicalPath: String
    public var isSymbolicLink: Bool
    public var hasSymbolicLinkAncestor: Bool
    public var isRegularFile: Bool
    public var linkCount: Int
    public var sizeBytes: Int64
    public var declaredType: PortalFileType
    public var ownerMatches: Bool

    public init(displayName: String, sandboxRoot: String, path: String, canonicalPath: String, isSymbolicLink: Bool, hasSymbolicLinkAncestor: Bool, isRegularFile: Bool, linkCount: Int, sizeBytes: Int64, declaredType: PortalFileType, ownerMatches: Bool) {
        self.displayName = displayName
        self.sandboxRoot = sandboxRoot
        self.path = path
        self.canonicalPath = canonicalPath
        self.isSymbolicLink = isSymbolicLink
        self.hasSymbolicLinkAncestor = hasSymbolicLinkAncestor
        self.isRegularFile = isRegularFile
        self.linkCount = linkCount
        self.sizeBytes = sizeBytes
        self.declaredType = declaredType
        self.ownerMatches = ownerMatches
    }
}

public struct PortalAdmittedFile: Equatable, Sendable {
    public var displayName: String
    public var path: String
    public var canonicalPath: String
    public var sizeBytes: Int64
    public var type: PortalFileType
    public var outputKind: PortalConversionKind

    public init(displayName: String, path: String, canonicalPath: String, sizeBytes: Int64, type: PortalFileType, outputKind: PortalConversionKind) {
        self.displayName = displayName
        self.path = path
        self.canonicalPath = canonicalPath
        self.sizeBytes = sizeBytes
        self.type = type
        self.outputKind = outputKind
    }
}

/// Component-wise containment. A string prefix would admit `/sandbox/inbox-evil`.
public enum PortalPathRules {
    public static func failure(of path: String) -> PortalDropFailure? {
        if path.isEmpty { return .emptyPath }
        if path.utf8.contains(0) || path.contains("\\") { return .escapesSandbox }
        if !path.hasPrefix("/") { return .notAbsolute }
        let body = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        if body.isEmpty || body.contains("") || body.contains(".") || body.contains("..") { return .escapesSandbox }
        return nil
    }

    public static func isInside(_ path: String, root: String) -> Bool {
        guard failure(of: path) == nil, failure(of: root) == nil else { return false }
        let pathParts = path.split(separator: "/").map(String.init)
        let rootParts = root.split(separator: "/").map(String.init)
        guard pathParts.count > rootParts.count else { return false }
        return Array(pathParts.prefix(rootParts.count)) == rootParts
    }
}

public enum PortalFileGate {
    public static func decide(_ claim: PortalFileClaim) -> Result<PortalAdmittedFile, PortalDropFailure> {
        if claim.path.isEmpty || claim.sandboxRoot.isEmpty { return .failure(.emptyPath) }
        if let failure = PortalPathRules.failure(of: claim.path) { return .failure(failure) }
        if claim.canonicalPath.isEmpty { return .failure(.unresolved) }
        if let failure = PortalPathRules.failure(of: claim.canonicalPath) { return .failure(failure) }
        if !PortalPathRules.isInside(claim.path, root: claim.sandboxRoot) { return .failure(.escapesSandbox) }
        if !PortalPathRules.isInside(claim.canonicalPath, root: claim.sandboxRoot) { return .failure(.escapesSandbox) }
        if claim.isSymbolicLink || claim.hasSymbolicLinkAncestor { return .failure(.symlink) }
        if !claim.isRegularFile || claim.linkCount < 1 { return .failure(.notRegularFile) }
        if claim.linkCount != 1 { return .failure(.hardLink) }
        if !claim.ownerMatches { return .failure(.wrongOwner) }
        if claim.sizeBytes < 0 { return .failure(.unreadableSize) }
        if claim.sizeBytes == 0 { return .failure(.empty) }
        if claim.sizeBytes > Int64(PortalLimits.maxConversionBytes) { return .failure(.tooLarge) }
        if claim.declaredType == .unknown { return .failure(.typeNotAllowed) }
        let named = PortalFileTypes.fromExtension((claim.displayName as NSString).pathExtension)
        if named != claim.declaredType { return .failure(.typeMismatch) }
        if (claim.path as NSString).lastPathComponent != claim.displayName { return .failure(.unsafeName) }
        if case .failure = FlingNames.validate(claim.displayName) { return .failure(.unsafeName) }
        let kind: PortalConversionKind = claim.declaredType == .plainText ? .utf8Text : .png
        return .success(PortalAdmittedFile(
            displayName: claim.displayName,
            path: claim.path,
            canonicalPath: claim.canonicalPath,
            sizeBytes: claim.sizeBytes,
            type: claim.declaredType,
            outputKind: kind
        ))
    }
}
