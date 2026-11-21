import Foundation

/// How a face template is protected in the data-protection keychain. Both choices use
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The keychain item itself carries the access
/// control, so a check that only runs in the app is not enough.
public enum FaceTemplateProtection: Equatable, Sendable {
    /// `SecAccessControlCreateFlags.userPresence` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    case userPresence
    /// Flags `.biometryCurrentSet`, `.or`, and `.devicePasscode`, with
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. A change of fingerprints still requires enrolling again.
    case biometryCurrentSetOrDevicePasscode
}

/// Names of the flags the keychain item must carry. The macOS keychain creates the access
/// control from this set; tests assert the set without calling Security.
public enum FaceTemplateAccessControl {
    public static func flags(for protection: FaceTemplateProtection) -> Set<String> {
        switch protection {
        case .userPresence:
            ["WhenUnlockedThisDeviceOnly", "userPresence"]
        case .biometryCurrentSetOrDevicePasscode:
            ["WhenUnlockedThisDeviceOnly", "biometryCurrentSet", "devicePasscode"]
        }
    }
}

extension Result: Equatable where Success == Void, Failure: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): true
        case (.failure(let left), .failure(let right)): left == right
        default: false
        }
    }
}

public enum FaceTemplateFailure: Equatable, Sendable, Error {
    /// The person cancelled the system prompt, or the prompt failed. Nothing is returned.
    case cancelled
    /// Fingerprints changed. The template is gone and has to be enrolled again.
    case biometryChanged
    /// The keychain refused the item, or the item is not protected as requested.
    case unavailable
    /// The new copy did not match the old one. The old copy is still there.
    case notVerified
    /// No template is stored.
    case missing
}

public struct FaceTemplateRecord: Equatable, Sendable {
    public var account: String
    public var protection: FaceTemplateProtection
    public var payload: Data

    public init(account: String, protection: FaceTemplateProtection, payload: Data) {
        self.account = account
        self.protection = protection
        self.payload = payload
    }
}

/// The keychain the face vault talks to. A save and a read both name the protection, and the
/// implementation must put that protection on the item. Tests pass `MemoryFaceTemplateKeychain`.
public protocol FaceTemplateKeychain: Sendable {
    func write(_ record: FaceTemplateRecord) -> Result<Void, FaceTemplateFailure>
    func read(account: String, requiring protection: FaceTemplateProtection) -> Result<Data, FaceTemplateFailure>
    @discardableResult func remove(account: String) -> Result<Void, FaceTemplateFailure>
    func protection(of account: String) -> FaceTemplateProtection?
}

/// Lines a face-template log may contain. A line that carries the template, or a size next to
/// whose face it is, is refused.
public enum FaceTemplateLog {
    public static func line(_ event: String) -> String { "face-template.\(event)" }

    public static func exposesPrivateMaterial(_ line: String, identity: String, payload: Data) -> Bool {
        if let text = String(data: payload, encoding: .utf8), !text.isEmpty, line.contains(text) { return true }
        if line.contains(identity), line.contains(String(payload.count)) { return true }
        return false
    }
}

/// What the Enroll row and the fingerprint-change line say. The card draws these words and no others.
public enum FaceTemplateCopy {
    public static let enroll = "Saving a face asks for Touch ID or the device passcode. Zeus does not keep the face print after it checks a match."
    public static let reenrol = "Fingerprints on this Mac changed. Enroll this face again."
}

/// Holds no template bytes. `cachedPayload` stays nil: a match reads the keychain and drops the copy.
public final class FaceTemplateStore: @unchecked Sendable {
    public static let protection = FaceTemplateProtection.biometryCurrentSetOrDevicePasscode

    private let keychain: any FaceTemplateKeychain
    private let account: String
    private let protection: FaceTemplateProtection
    private let log: @Sendable (String) -> Void

    public init(keychain: any FaceTemplateKeychain, account: String, protection: FaceTemplateProtection,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.keychain = keychain
        self.account = account
        self.protection = protection
        self.log = log
    }

    /// Always nil. The decrypted template is not kept on this store.
    public var cachedPayload: Data? { nil }

    public func save(_ payload: Data, identity: String) -> Result<Void, FaceTemplateFailure> {
        _ = identity
        log(FaceTemplateLog.line("save"))
        let record = FaceTemplateRecord(account: account, protection: protection, payload: payload)
        switch keychain.write(record) {
        case .success:
            return .success(())
        case .failure(let error):
            if error == .biometryChanged { keychain.remove(account: account) }
            return .failure(error)
        }
    }

    /// Reads once, hands the bytes to `body`, then zeroes that copy. A cancel, a failure, or a
    /// fingerprint change does not call `body`.
    public func withTemplate(identity: String, _ body: (inout Data) -> Void) -> Result<Void, FaceTemplateFailure> {
        _ = identity
        log(FaceTemplateLog.line("read"))
        switch keychain.read(account: account, requiring: protection) {
        case .failure(let error):
            if error == .biometryChanged { keychain.remove(account: account) }
            return .failure(error)
        case .success(var payload):
            body(&payload)
            if !payload.isEmpty { payload.resetBytes(in: 0..<payload.count) }
            return .success(())
        }
    }
}

/// Read the old template, write the new protected item, read it back, and only then delete the
/// old copy. Any miss deletes the new item when one was written and leaves the old copy in place.
public enum FaceTemplateMigration {
    public static func run(
        readOld: () -> Result<Data, FaceTemplateFailure>,
        writeNew: (Data) -> Result<Void, FaceTemplateFailure>,
        readNew: () -> Result<Data, FaceTemplateFailure>,
        deleteNew: () -> Result<Void, FaceTemplateFailure>,
        deleteOld: () -> Result<Void, FaceTemplateFailure>
    ) -> Result<Void, FaceTemplateFailure> {
        let old: Data
        switch readOld() {
        case .success(let data): old = data
        case .failure(let error): return .failure(error)
        }
        switch writeNew(old) {
        case .success: break
        case .failure(let error):
            _ = deleteNew()
            return .failure(error)
        }
        switch readNew() {
        case .success(let copy) where copy == old: break
        case .success:
            _ = deleteNew()
            return .failure(.notVerified)
        case .failure(let error):
            _ = deleteNew()
            return .failure(error)
        }
        switch deleteOld() {
        case .success: return .success(())
        case .failure(let error): return .failure(error)
        }
    }
}

/// In-memory stand-in. An item planted without protection cannot be read as a template.
public final class MemoryFaceTemplateKeychain: FaceTemplateKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: FaceTemplateRecord] = [:]
    private var unprotected: [String: Data] = [:]
    public var failWrites: FaceTemplateFailure?
    public var failReads: FaceTemplateFailure?
    public private(set) var reads = 0
    public private(set) var writes = 0

    public init() {}

    public func plantUnprotected(account: String, payload: Data) {
        lock.lock(); defer { lock.unlock() }
        unprotected[account] = payload
        items[account] = nil
    }

    public func item(account: String) -> FaceTemplateRecord? {
        lock.lock(); defer { lock.unlock() }
        return items[account]
    }

    public func write(_ record: FaceTemplateRecord) -> Result<Void, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        writes += 1
        if let failWrites { return .failure(failWrites) }
        items[record.account] = record
        unprotected[record.account] = nil
        return .success(())
    }

    public func read(account: String, requiring protection: FaceTemplateProtection) -> Result<Data, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        if let failReads { return .failure(failReads) }
        if let item = items[account] {
            guard item.protection == protection else { return .failure(.unavailable) }
            reads += 1
            return .success(item.payload)
        }
        if unprotected[account] != nil { return .failure(.unavailable) }
        return .failure(.missing)
    }

    @discardableResult
    public func remove(account: String) -> Result<Void, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        items[account] = nil
        unprotected[account] = nil
        return .success(())
    }

    public func protection(of account: String) -> FaceTemplateProtection? {
        lock.lock(); defer { lock.unlock() }
        return items[account]?.protection
    }
}

/// What a read or save must present so the item's `SecAccessControl` is evaluated.
/// `presentsAccessControl` is true only for an `LAContext` (`kSecUseAuthenticationContext`) or
/// `kSecUseOperationPrompt` path. An empty prompt does not count.
public struct FaceTemplateAuthentication: Equatable, Sendable {
    public var protection: FaceTemplateProtection
    public var operationPrompt: String
    public var presentsAccessControl: Bool

    public init(protection: FaceTemplateProtection, operationPrompt: String, presentsAccessControl: Bool) {
        self.protection = protection
        self.operationPrompt = operationPrompt
        self.presentsAccessControl = presentsAccessControl
    }
}

/// A UI-fail probe. Unprotected bytes must be discarded by the caller.
public enum FaceTemplateProbe: Equatable, Sendable {
    case missing
    case unprotected(Data)
    case protected
}

/// The secure-item operations behind `SystemFaceTemplateKeychain`. Tests use a fake.
public protocol FaceTemplateSecureItems: Sendable {
    func probe(account: String) -> FaceTemplateProbe
    func add(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure>
    func replace(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure>
    func read(account: String, authentication: FaceTemplateAuthentication) -> Result<Data, FaceTemplateFailure>
    func delete(account: String) -> Result<Void, FaceTemplateFailure>
}

/// Save and read sequencing for a face template. An existing item is updated in place.
/// A read presents that protection's access control. Bytes that arrive with the prompt refused are discarded.
public enum FaceTemplateSecureSession {
    public static let userPresencePrompt = "Authenticate to read the face template."
    public static let biometryOrPasscodePrompt = "Authenticate with Touch ID or the device passcode to read the face template."

    public static func authentication(for protection: FaceTemplateProtection) -> FaceTemplateAuthentication {
        switch protection {
        case .userPresence:
            FaceTemplateAuthentication(protection: protection, operationPrompt: userPresencePrompt, presentsAccessControl: true)
        case .biometryCurrentSetOrDevicePasscode:
            FaceTemplateAuthentication(protection: protection, operationPrompt: biometryOrPasscodePrompt, presentsAccessControl: true)
        }
    }

    public static func write(_ record: FaceTemplateRecord, items: any FaceTemplateSecureItems) -> Result<Void, FaceTemplateFailure> {
        let authentication = authentication(for: record.protection)
        switch items.probe(account: record.account) {
        case .missing:
            return items.add(record, authentication: authentication)
        case .protected, .unprotected:
            switch items.replace(record, authentication: authentication) {
            case .success:
                return .success(())
            case .failure(let error) where error == .missing:
                return items.add(record, authentication: authentication)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public static func read(account: String, requiring protection: FaceTemplateProtection, items: any FaceTemplateSecureItems) -> Result<Data, FaceTemplateFailure> {
        let authentication = authentication(for: protection)
        guard authentication.presentsAccessControl, !authentication.operationPrompt.isEmpty else {
            return .failure(.unavailable)
        }
        switch items.probe(account: account) {
        case .missing:
            return .failure(.missing)
        case .unprotected(var data):
            if !data.isEmpty { data.resetBytes(in: 0..<data.count) }
            return .failure(.unavailable)
        case .protected:
            return items.read(account: account, authentication: authentication)
        }
    }
}
