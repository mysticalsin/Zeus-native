import Foundation
import LocalAuthentication
import Security

/// The data-protection keychain item for face templates. `kSecUseDataProtectionKeychain` is set so
/// macOS stores the item where `WhenUnlockedThisDeviceOnly` and the access-control flags are
/// enforced. The file-based dev keychain cannot do that, so this item does not go there.
///
/// A read and a save both go through `SecItem` with the access control on the item. Cancelling the
/// system prompt, or any other error, returns no bytes. When the fingerprint set changes, the item
/// is deleted and the caller enrolls again. `LAContext` only notices that change; it is not the
/// gate that releases the template.
public struct SystemFaceTemplateKeychain: FaceTemplateKeychain {
    private static let service = "com.zeus.app"
    private static let epochAccount = "face.presence.biometryEpoch"

    public init() {}

    public func write(_ record: FaceTemplateRecord) -> Result<Void, FaceTemplateFailure> {
        switch epochCheck() {
        case .changed:
            _ = remove(account: record.account)
            return .failure(.biometryChanged)
        case .unavailable:
            return .failure(.unavailable)
        case .same, .first:
            break
        }
        guard let control = accessControl(record.protection) else { return .failure(.unavailable) }
        _ = deleteItem(account: record.account)
        var query = base(account: record.account)
        query[kSecValueData as String] = record.payload
        query[kSecAttrAccessControl as String] = control
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { return .failure(Self.failure(status)) }
        _ = rememberEpoch()
        return .success(())
    }

    public func read(account: String, requiring protection: FaceTemplateProtection) -> Result<Data, FaceTemplateFailure> {
        _ = protection
        switch epochCheck() {
        case .changed:
            _ = remove(account: account)
            return .failure(.biometryChanged)
        case .unavailable:
            return .failure(.unavailable)
        case .same, .first:
            break
        }
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return .failure(Self.failure(status)) }
        return .success(data)
    }

    @discardableResult
    public func remove(account: String) -> Result<Void, FaceTemplateFailure> {
        let status = deleteItem(account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else { return .failure(.unavailable) }
        return .success(())
    }

    public func protection(of account: String) -> FaceTemplateProtection? {
        var query = base(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Existence only. Fail the prompt instead of showing it, so a name lookup does not ask
        // for a fingerprint. A real read of the template does not set this flag.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return FaceTemplateStore.protection
        }
        return nil
    }

    private func base(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    private func accessControl(_ protection: FaceTemplateProtection) -> SecAccessControl? {
        let flags: SecAccessControlCreateFlags
        switch protection {
        case .userPresence:
            flags = .userPresence
        case .biometryCurrentSetOrDevicePasscode:
            flags = [.biometryCurrentSet, .or, .devicePasscode]
        }
        var error: Unmanaged<CFError>?
        return SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error)
    }

    @discardableResult
    private func deleteItem(account: String) -> OSStatus {
        SecItemDelete(base(account: account) as CFDictionary)
    }

    private enum Epoch { case first, same, changed, unavailable }

    /// Compares the current fingerprint set with the set stored when the template was saved.
    /// This does not evaluate a policy and does not return the template.
    private func epochCheck() -> Epoch {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        let current = context.evaluatedPolicyDomainState ?? Data()
        switch epochData() {
        case .none: return .first
        case .some(let stored) where stored == current: return .same
        case .some: return .changed
        }
    }

    private func epochData() -> Data? {
        var query = base(account: Self.epochAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func rememberEpoch() -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        let current = context.evaluatedPolicyDomainState ?? Data()
        _ = deleteItem(account: Self.epochAccount)
        var query = base(account: Self.epochAccount)
        query[kSecValueData as String] = current
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func failure(_ status: OSStatus) -> FaceTemplateFailure {
        if status == errSecUserCanceled || status == errSecAuthFailed { return .cancelled }
        if status == errSecItemNotFound { return .missing }
        return .unavailable
    }
}
