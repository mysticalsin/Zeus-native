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
        let evaluation = Self.evaluate()
        switch Self.decision(evaluation: evaluation, account: record.account) {
        case .denyKeep:
            return .failure(.unavailable)
        case .changedDelete:
            _ = remove(account: record.account)
            return .failure(.biometryChanged)
        case .allow(let state):
            guard let context = evaluation.context else { return .failure(.unavailable) }
            let saved = FaceTemplateSecureSession.write(record, items: Items(context: context))
            if case .success = saved { _ = Self.rememberEpoch(state) }
            return saved
        }
    }

    public func read(account: String, requiring protection: FaceTemplateProtection) -> Result<Data, FaceTemplateFailure> {
        let evaluation = Self.evaluate()
        switch Self.decision(evaluation: evaluation, account: account) {
        case .denyKeep:
            return .failure(.unavailable)
        case .changedDelete:
            _ = remove(account: account)
            return .failure(.biometryChanged)
        case .allow:
            guard let context = evaluation.context else { return .failure(.unavailable) }
            return FaceTemplateSecureSession.read(account: account, requiring: protection, items: Items(context: context))
        }
    }

    @discardableResult
    public func remove(account: String) -> Result<Void, FaceTemplateFailure> {
        let status = deleteItem(account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else { return .failure(.unavailable) }
        if account != Self.epochAccount {
            _ = deleteItem(Self.epochAccount)
        }
        return .success(())
    }

    public func protection(of account: String) -> FaceTemplateProtection? {
        guard var query = base(account: account) else { return nil }
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
        var context: LAContext

        func probe(account: String) -> FaceTemplateProbe {
            guard var query = SystemFaceTemplateKeychain.base(account: account) else { return .missing }
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
            guard let control = SystemFaceTemplateKeychain.accessControl(authentication.protection),
                  var query = prompted(account: record.account, authentication: authentication) else {
                return .failure(.unavailable)
            }
            query[kSecValueData as String] = record.payload
            query[kSecAttrAccessControl as String] = control
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { return .failure(SystemFaceTemplateKeychain.failure(status)) }
            return .success(())
        }

        func replace(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure> {
            guard authentication.presentsAccessControl,
                  let query = prompted(account: record.account, authentication: authentication) else {
                return .failure(.unavailable)
            }
            let attributes = [kSecValueData as String: record.payload]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound { return .failure(.missing) }
            guard status == errSecSuccess else { return .failure(SystemFaceTemplateKeychain.failure(status)) }
            return .success(())
        }

        func read(account: String, authentication: FaceTemplateAuthentication) -> Result<Data, FaceTemplateFailure> {
            guard authentication.presentsAccessControl, !authentication.operationPrompt.isEmpty,
                  var query = prompted(account: account, authentication: authentication) else {
                return .failure(.unavailable)
            }
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

        private func prompted(account: String, authentication: FaceTemplateAuthentication) -> [String: Any]? {
            guard var query = SystemFaceTemplateKeychain.base(account: account) else { return nil }
            query[kSecUseAuthenticationContext as String] = context
            query[kSecUseOperationPrompt as String] = authentication.operationPrompt
            return query
        }
    }

    /// The access group is `CredentialKeychainPolicy.accessGroup` from the shared keychain change.
    /// A missing Team ID fails closed and does not omit the group.
    private static func base(account: String) -> [String: Any]? {
        guard let team = DevKeychain.teamIdentifier,
              let fields = FaceTemplateKeychainAttributes.query(account: account, teamIdentifier: team),
              let group = fields["accessGroup"], let service = fields["service"] else { return nil }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group,
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
        guard let query = base(account: account) else { return errSecParam }
        return SecItemDelete(query as CFDictionary)
    }

    private struct Evaluation {
        var value: FaceTemplateEvaluation
        var context: LAContext?
    }

    /// There is no synchronous `evaluatePolicy`. The reply form is the one that sets the domain state.
    private static func evaluate() -> Evaluation {
        let context = LAContext()
        let reason = "Confirm it is you before Zeus uses the saved face."
        final class Box: @unchecked Sendable {
            var value = Evaluation(value: .failed, context: nil)
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            if success, error == nil {
                box.value = Evaluation(value: .succeeded(context.evaluatedPolicyDomainState), context: context)
            }
            done.signal()
        }
        if Thread.isMainThread {
            while done.wait(timeout: .now()) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
        } else {
            done.wait()
        }
        return box.value
    }

    private static func decision(evaluation: Evaluation, account: String) -> FaceTemplateDomainEffect {
        let read = epochRead()
        let stored: Data?
        let unreadable: Bool
        switch read {
        case .value(let data):
            stored = data
            unreadable = false
        case .missing:
            stored = nil
            unreadable = false
        case .unreadable:
            stored = nil
            unreadable = true
        }
        let enrolled = Items(context: evaluation.context ?? LAContext()).probe(account: account) != .missing
        return FaceTemplateDomainGate.effect(stored: stored, evaluation: evaluation.value, enrolled: enrolled, epochUnreadable: unreadable)
    }

    private static func usable(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        return data
    }

    private enum EpochRead { case value(Data), missing, unreadable }

    private static func epochRead() -> EpochRead {
        guard var query = base(account: epochAccount) else { return .unreadable }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = usable(result as? Data) else { return .unreadable }
        return .value(data)
    }

    /// Update the existing epoch. Add only when it is missing. A failed call does not delete it.
    private static func rememberEpoch(_ state: Data) -> Bool {
        guard !state.isEmpty, var query = base(account: epochAccount) else { return false }
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: state] as CFDictionary)
        if updated == errSecSuccess { return true }
        if updated != errSecItemNotFound { return false }
        query[kSecValueData as String] = state
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func failure(_ status: OSStatus) -> FaceTemplateFailure {
        if status == errSecUserCanceled || status == errSecAuthFailed { return .cancelled }
        if status == errSecItemNotFound { return .missing }
        return .unavailable
    }
}
