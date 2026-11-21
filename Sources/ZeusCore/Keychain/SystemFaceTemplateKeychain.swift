import Foundation
import LocalAuthentication
import Security

/// The data-protection keychain item for face templates. `kSecUseDataProtectionKeychain` is set so
/// macOS stores the item where `WhenUnlockedThisDeviceOnly` and the access-control flags are
/// enforced. The file-based dev keychain cannot do that, so this item does not go there.
///
/// A read and a save both go through `SecItem` with the access control on the item. Cancelling the
/// system prompt, or any other error, returns no bytes. When the fingerprint set changes, the item
/// is deleted and the caller enrolls again. The epoch `LAContext` only notices that change.
/// The read gate is the item's `SecAccessControl`, evaluated with an `LAContext`
/// (`kSecUseAuthenticationContext`) and `kSecUseOperationPrompt`.
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
        let saved = FaceTemplateSecureSession.write(record, items: Items())
        if case .success = saved { _ = rememberEpoch() }
        return saved
    }

    public func read(account: String, requiring protection: FaceTemplateProtection) -> Result<Data, FaceTemplateFailure> {
        switch epochCheck() {
        case .changed:
            _ = remove(account: account)
            return .failure(.biometryChanged)
        case .unavailable:
            return .failure(.unavailable)
        case .same, .first:
            break
        }
        return FaceTemplateSecureSession.read(account: account, requiring: protection, items: Items())
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
        // for a fingerprint. The template read uses kSecUseOperationPrompt and an LAContext instead.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return FaceTemplateStore.protection
        }
        return nil
    }

    /// SecItem adapter. Update replaces the payload of an existing item. Add runs only when the item is missing.
    private struct Items: FaceTemplateSecureItems {
        func probe(account: String) -> FaceTemplateProbe {
            var query = SystemFaceTemplateKeychain.base(account: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return .missing }
            if status == errSecSuccess {
                return .unprotected((result as? Data) ?? Data())
            }
            return .protected
        }

        func add(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure> {
            guard authentication.presentsAccessControl else { return .failure(.unavailable) }
            guard let control = SystemFaceTemplateKeychain.accessControl(authentication.protection) else {
                return .failure(.unavailable)
            }
            var query = prompted(account: record.account, authentication: authentication)
            query[kSecValueData as String] = record.payload
            query[kSecAttrAccessControl as String] = control
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { return .failure(SystemFaceTemplateKeychain.failure(status)) }
            return .success(())
        }

        func replace(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure> {
            guard authentication.presentsAccessControl else { return .failure(.unavailable) }
            let query = prompted(account: record.account, authentication: authentication)
            let attributes = [kSecValueData as String: record.payload]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound { return .failure(.missing) }
            guard status == errSecSuccess else { return .failure(SystemFaceTemplateKeychain.failure(status)) }
            return .success(())
        }

        func read(account: String, authentication: FaceTemplateAuthentication) -> Result<Data, FaceTemplateFailure> {
            guard authentication.presentsAccessControl, !authentication.operationPrompt.isEmpty else {
                return .failure(.unavailable)
            }
            var query = prompted(account: account, authentication: authentication)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else {
                return .failure(SystemFaceTemplateKeychain.failure(status))
            }
            return .success(data)
        }

        func delete(account: String) -> Result<Void, FaceTemplateFailure> {
            let status = SystemFaceTemplateKeychain.deleteItem(account: account)
            guard status == errSecSuccess || status == errSecItemNotFound else { return .failure(.unavailable) }
            return .success(())
        }

        private func prompted(account: String, authentication: FaceTemplateAuthentication) -> [String: Any] {
            var query = SystemFaceTemplateKeychain.base(account: account)
            query[kSecUseAuthenticationContext as String] = LAContext()
            query[kSecUseOperationPrompt as String] = authentication.operationPrompt
            return query
        }
    }

    private static func base(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    private static func accessControl(_ protection: FaceTemplateProtection) -> SecAccessControl? {
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
    private static func deleteItem(account: String) -> OSStatus {
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
