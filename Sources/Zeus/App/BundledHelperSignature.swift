import CryptoKit
import Foundation
import os
import Security
import ZeusCore

/// Reads the running app's signature and checks a helper with `SecStaticCode` against one
/// `SecRequirement`. Developer ID pins `anchor apple generic` and the team. Zeus Local Dev pins
/// the leaf certificate and has no Apple anchor. Any failure refuses.
struct SecBundledHelperSignature: BundledHelperSignatureChecking, BundledHelperAnchorChecking {
    func signingAnchor() -> HelperSigningAnchor? {
        guard let code = Self.selfStaticCode(), let facts = Self.facts(code) else { return nil }
        if let team = facts.team, BundledHelperLaunchPolicy.isToken(team, allowing: "") {
            return .developerID(teamIdentifier: team)
        }
        if !facts.isAdHoc, let leaf = facts.leafSHA1, BundledHelperLaunchPolicy.isLeafSHA1(leaf) {
            return .localDev(leafSHA1: leaf.lowercased())
        }
        return nil
    }

    func mainAppTeamIdentifier() -> String? {
        guard let code = Self.selfStaticCode() else { return nil }
        return Self.facts(code)?.team
    }

    func helperSatisfies(anchor: HelperSigningAnchor, signingIdentifier: String, at path: String) -> Bool {
        guard let text = BundledHelperLaunchPolicy.requirementText(anchor: anchor, signingIdentifier: signingIdentifier),
              let staticCode = Self.staticCode(at: path) else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement) == errSecSuccess,
              let facts = Self.facts(staticCode),
              facts.identifier == signingIdentifier else { return false }
        switch anchor {
        case .developerID(let team):
            return facts.team == team
        case .localDev(let leaf):
            return !facts.isAdHoc && facts.leafSHA1?.lowercased() == leaf.lowercased()
        }
    }

    func helperSatisfiesRequirement(at path: String, teamIdentifier: String, signingIdentifier: String) -> Bool {
        helperSatisfies(anchor: .developerID(teamIdentifier: teamIdentifier), signingIdentifier: signingIdentifier, at: path)
    }

    private static func selfStaticCode() -> SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private static func staticCode(at path: String) -> SecStaticCode? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, SecCSFlags(), &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private struct Facts {
        var team: String?
        var identifier: String?
        var leafSHA1: String?
        var isAdHoc: Bool
    }

    private static func facts(_ code: SecStaticCode) -> Facts? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let info = information as? [String: Any] else { return nil }
        let adHocFlag: UInt32 = 0x2 // kSecCodeSignatureAdhoc
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let leafData = certificates?.first.map { SecCertificateCopyData($0) as Data }
        func string(_ key: CFString) -> String? {
            guard let value = info[key as String] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return Facts(team: string(kSecCodeInfoTeamIdentifier),
                     identifier: string(kSecCodeInfoIdentifier),
                     leafSHA1: leafData.map { hex(Insecure.SHA1.hash(data: $0)) },
                     isAdHoc: codeFlags & adHocFlag != 0)
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
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
