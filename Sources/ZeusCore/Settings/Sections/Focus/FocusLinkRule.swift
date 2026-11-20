import Foundation

/// A link that might carry a Focus name. Shared Wi-Fi needs a one-time token and TLS. A local-only link does not.
public struct FocusLink: Equatable, Sendable {
    public enum Transport: Equatable, Sendable { case plain, tls }
    public enum Scope: Equatable, Sendable { case sharedWiFi, localOnly }

    public var transport: Transport
    public var scope: Scope
    public var hasOneTimeToken: Bool
    public var name: String?

    public init(transport: Transport, scope: Scope, hasOneTimeToken: Bool, name: String?) {
        self.transport = transport
        self.scope = scope
        self.hasOneTimeToken = hasOneTimeToken
        self.name = name
    }
}

public enum FocusLinkDecision: Equatable, Sendable {
    case refused
    case accepted(label: String?)
}

public enum FocusLinkRule {
    public static func decide(_ link: FocusLink) -> FocusLinkDecision {
        if link.scope == .sharedWiFi && (link.transport != .tls || !link.hasOneTimeToken) {
            return .refused
        }
        return .accepted(label: link.name.flatMap(FocusNameText.cleanName))
    }
}
