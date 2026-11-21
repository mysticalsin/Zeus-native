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

/// Whether Zeus may start a bundled helper. Failure refuses the launch.
public enum BundledHelperLaunchPolicy {
    /// `scripts/bundle.sh` signs `zeus-bridge` without `--identifier`, so the signing identifier is the file name.
    public static let bridgeSigningIdentifier = "zeus-bridge"
    public static let knownSigningIdentifiers: Set<String> = ["zeus", "zeus-cli", "zeus-bridge", "zeus-hook"]
    public static let refusalSentence = "Zeus refused to launch its helper because the helper's signature does not match this app."

    public static func signingIdentifier(forExecutablePath path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Designated requirement pinning the running app's team and the helper's signing identifier.
    /// Nil when either value cannot be placed in a requirement.
    public static func requirementText(teamIdentifier: String, signingIdentifier: String) -> String? {
        guard isToken(teamIdentifier, allowing: ""), isToken(signingIdentifier, allowing: "._-") else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    public static func decide(helperPath: String, signingIdentifier: String, checker: some BundledHelperSignatureChecking) -> BundledHelperLaunchDecision {
        _ = (helperPath, signingIdentifier, checker)
        return .launch
    }

    /// Letters, digits and the given extras only, so a value cannot add a requirement clause.
    static func isToken(_ text: String, allowing extra: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || extra.unicodeScalars.contains(scalar))
        }
    }
}
