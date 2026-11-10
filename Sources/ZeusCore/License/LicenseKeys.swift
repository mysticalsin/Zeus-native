import CryptoKit
import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// The public halves ZEUS trusts. Private halves never ship: the release key lives only in the
/// ZEUS Portal's keychain item (`zeus-portal public-key` prints this value).
public enum LicenseKeys {
    public static let release = "y1iRLTTXc6YPWPXTGAiU/Hm+ivG6bcWPT3vp/3bv6b0="
    /// Old file-based dev signer (scripts/make-license.swift). Debug builds only.
    public static let legacyDev = "LS1gvx5PPhzBoRIdmKUTGFlCVuGLLKA584LvK3klzdo="

    public static func trusted(debug: Bool) -> [Curve25519.Signing.PublicKey] {
        (debug ? [release, legacyDev] : [release]).compactMap(License.publicKey(base64:))
    }

    /// This Mac's id for licenses: a hash of IOPlatformUUID, nothing personal.
    public static func thisMacDeviceID() -> String {
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return License.deviceID(hardwareUUID: value?.takeRetainedValue() as? String ?? "unknown")
        #else
        return License.deviceID(hardwareUUID: "unknown")
        #endif
    }
}
