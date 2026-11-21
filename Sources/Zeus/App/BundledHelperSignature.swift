import Foundation
import os
import Security
import ZeusCore

/// Reads the running app's team identifier and checks a helper with `SecStaticCode` against a
/// `SecRequirement` that pins that team and the helper's signing identifier. Any failure refuses.
struct SecBundledHelperSignature: BundledHelperSignatureChecking {
    func mainAppTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        return Self.fact(staticCode, key: kSecCodeInfoTeamIdentifier)
    }

    func helperSatisfiesRequirement(at path: String, teamIdentifier: String, signingIdentifier: String) -> Bool {
        guard let text = BundledHelperLaunchPolicy.requirementText(teamIdentifier: teamIdentifier, signingIdentifier: signingIdentifier) else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else { return false }
        guard let flags = Self.validityFlags() else { return false }
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else { return false }
        guard Self.fact(staticCode, key: kSecCodeInfoTeamIdentifier) == teamIdentifier else { return false }
        guard Self.fact(staticCode, key: kSecCodeInfoIdentifier) == signingIdentifier else { return false }
        return true
    }

    /// Strict, nested, and every architecture. A missing or extra flag name fails closed.
    /// Revocation stays off: see `BundledHelperLaunchPolicy.omittedValidityFlags`.
    private static func validityFlags() -> SecCSFlags? {
        var mask: UInt32 = 0
        var seen = 0
        for name in BundledHelperLaunchPolicy.requiredValidityFlags {
            let bit: UInt32
            switch name {
            case "kSecCSStrictValidate": bit = UInt32(kSecCSStrictValidate)
            case "kSecCSCheckNestedCode": bit = UInt32(kSecCSCheckNestedCode)
            case "kSecCSCheckAllArchitectures": bit = UInt32(kSecCSCheckAllArchitectures)
            default: return nil
            }
            guard bit != 0 else { return nil }
            mask |= bit
            seen += 1
        }
        guard seen == BundledHelperLaunchPolicy.requiredValidityFlags.count, mask != 0 else { return nil }
        return SecCSFlags(rawValue: mask)
    }

    private static func fact(_ code: SecStaticCode, key: CFString) -> String? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let info = information as? [String: Any],
              let value = info[key as String] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum BundledHelperLaunchLog {
    private static let logger = Logger(subsystem: "app.zeus.mac", category: "bundled-helper")

    static func refused(path: String) {
        logger.error("refused bundled helper launch path=\(path, privacy: .private)")
    }
}

enum BundledHelperLaunch {
    static func decide(path: String, signingIdentifier: String) -> BundledHelperLaunchDecision {
        BundledHelperLaunchPolicy.decide(helperPath: path, signingIdentifier: signingIdentifier, checker: SecBundledHelperSignature())
    }
}
