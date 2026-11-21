import Foundation

/// Facts the Security framework fills in on macOS. The decision below only reads them.
public protocol BundledHelperSignatureChecking: Sendable {
    /// Team identifier of the running app, read from its own signature. Nil when it cannot be read.
    func mainAppTeamIdentifier() -> String?
    /// True only when the file at `path` passes a designated requirement that pins `teamIdentifier`
    /// and `signingIdentifier`. Any check that cannot be completed is false.
    func helperSatisfiesRequirement(at path: String, teamIdentifier: String, signingIdentifier: String) -> Bool
}

public enum BundledHelperLaunchDecision: Equatable, Sendable {
    case launch
    case refuse(String)
}

/// How the running app is signed. Developer ID has a team. Zeus Local Dev has a leaf certificate and no team.
public enum HelperSigningAnchor: Equatable, Sendable {
    case developerID(teamIdentifier: String)
    case localDev(leafSHA1: String)
}

/// The Security framework reports which anchor the running app carries, and whether a helper meets one requirement.
public protocol BundledHelperAnchorChecking: Sendable {
    func signingAnchor() -> HelperSigningAnchor?
    /// True only when `path` satisfies the requirement for `anchor` and `signingIdentifier`. Any failure is false.
    func helperSatisfies(anchor: HelperSigningAnchor, signingIdentifier: String, at path: String) -> Bool
}

/// Whether Zeus may start a bundled helper. Failure refuses the launch.
public enum BundledHelperLaunchPolicy {
    /// `scripts/bundle.sh` signs `zeus-bridge` without `--identifier`, so the signing identifier is the file name.
    public static let bridgeSigningIdentifier = "zeus-bridge"
    public static let knownSigningIdentifiers: Set<String> = ["zeus", "zeus-cli", "zeus-bridge", "zeus-hook"]
    public static let refusalSentence = "Zeus refused to launch its helper because the helper's signature does not match this app."

    /// Passed together to `SecStaticCodeCheckValidity`. An empty mask is a failed check.
    public static let requiredValidityFlags = [
        "kSecCSStrictValidate",
        "kSecCSCheckNestedCode",
        "kSecCSCheckAllArchitectures",
    ]

    /// `kSecCSEnforceRevocationChecks` forces an OCSP request. It is not offline-safe: with no
    /// network the check fails or stalls, and `kSecCSNoNetworkAccess` cancels it. No Security
    /// flag reads a local revocation cache and fails closed while offline, so the validity call
    /// does not set that flag.
    public static let omittedValidityFlags = ["kSecCSEnforceRevocationChecks"]

    public static func signingIdentifier(forExecutablePath path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Designated requirement pinning the running app's team and the helper's signing identifier.
    /// Nil when either value cannot be placed in a requirement.
    public static func requirementText(teamIdentifier: String, signingIdentifier: String) -> String? {
        guard isToken(teamIdentifier, allowing: ""), isToken(signingIdentifier, allowing: "._-") else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(signingIdentifier)\""
    }

    /// Developer ID pins the Apple anchor and the team. A local-dev leaf is a different requirement.
    public static func requirementText(anchor: HelperSigningAnchor, signingIdentifier: String) -> String? {
        switch anchor {
        case .developerID(let team):
            return requirementText(teamIdentifier: team, signingIdentifier: signingIdentifier)
        case .localDev(let leaf):
            guard isLeafSHA1(leaf), isToken(signingIdentifier, allowing: "._-") else { return nil }
            return "certificate leaf = H\"\(leaf.lowercased())\" and identifier \"\(signingIdentifier)\""
        }
    }

    /// Launch when the helper's file name is a known signing identifier and `checker` accepts the
    /// requirement for the running app's anchor. No anchor, or a failed check, refuses.
    public static func decide(helperPath: String, signingIdentifier: String, checker: some BundledHelperAnchorChecking) -> BundledHelperLaunchDecision {
        let path = helperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = signingIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, knownSigningIdentifiers.contains(identifier),
              Self.signingIdentifier(forExecutablePath: path) == identifier,
              let anchor = checker.signingAnchor(),
              requirementText(anchor: anchor, signingIdentifier: identifier) != nil,
              checker.helperSatisfies(anchor: anchor, signingIdentifier: identifier, at: path) else {
            return .refuse(refusalSentence)
        }
        return .launch
    }

    /// Launch only when the helper's file name is its signing identifier, that identifier is one of
    /// the bundled helpers, and `checker` reports that a designated requirement pinning the running
    /// app's team and that identifier succeeded. Every other case refuses.
    public static func decide(helperPath: String, signingIdentifier: String, checker: some BundledHelperSignatureChecking) -> BundledHelperLaunchDecision {
        let path = helperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = signingIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, knownSigningIdentifiers.contains(identifier),
              Self.signingIdentifier(forExecutablePath: path) == identifier,
              let team = checker.mainAppTeamIdentifier()?.trimmingCharacters(in: .whitespacesAndNewlines), !team.isEmpty,
              requirementText(teamIdentifier: team, signingIdentifier: identifier) != nil,
              checker.helperSatisfiesRequirement(at: path, teamIdentifier: team, signingIdentifier: identifier) else {
            return .refuse(refusalSentence)
        }
        return .launch
    }

    public static func isLeafSHA1(_ text: String) -> Bool {
        let leaf = text.lowercased()
        return leaf.count == 40 && leaf.allSatisfy(\.isHexDigit)
    }

    /// A copy under Application Support/Zeus/bin. The person who runs Zeus can replace that file.
    public static func isUserWritableHelperCopy(_ path: String) -> Bool {
        path.replacingOccurrences(of: "\\", with: "/").contains("/Library/Application Support/Zeus/bin")
    }

    /// The path another program may be told to run. It is the path that was checked, its file
    /// name is the helper, and it is not a user-writable support-directory copy. `zeus-cli` is
    /// the unpackaged development binary. Every other helper has to sit in Contents/Helpers.
    public static func executableToPublish(checkedPath: String, helperName: String) -> String? {
        let path = checkedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = helperName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard knownSigningIdentifiers.contains(name), signingIdentifier(forExecutablePath: path) == name,
              !isUserWritableHelperCopy(path) else { return nil }
        if name == "zeus-cli" { return path }
        let marker = "/Contents/Helpers/" + name
        guard let range = path.range(of: marker), path[range.upperBound...].isEmpty else { return nil }
        return path
    }

    /// The executable handed to another process. A refusal publishes nothing, and a launch
    /// publishes the checked path only.
    public static func publishedExecutable(checkedPath: String, helperName: String, decision: BundledHelperLaunchDecision) -> String? {
        guard case .launch = decision else { return nil }
        return executableToPublish(checkedPath: checkedPath, helperName: helperName)
    }

    /// Letters, digits and the given extras only, so a value cannot add a requirement clause.
    public static func isToken(_ text: String, allowing extra: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || extra.unicodeScalars.contains(scalar))
        }
    }
}
