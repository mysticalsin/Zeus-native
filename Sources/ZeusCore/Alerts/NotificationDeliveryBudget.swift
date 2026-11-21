import Foundation

/// How many outgoing banners this process keeps. A new identifier past the cap
/// returns the oldest one so the caller can remove that banner.
public struct NotificationDeliveryBudget: Equatable, Sendable {
    public static let maxOutstanding = 40
    public private(set) var identifiers: [String] = []

    public init() {}

    public mutating func admit(_ identifier: String) -> String? {
        if let index = identifiers.firstIndex(of: identifier) {
            identifiers.remove(at: index)
        }
        identifiers.append(identifier)
        guard identifiers.count > Self.maxOutstanding else { return nil }
        return identifiers.removeFirst()
    }
}
