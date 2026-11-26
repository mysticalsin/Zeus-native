import Foundation

/// Which Recordly source is selected, as plain numbers. The caller supplies the catalog.
/// This type does not list devices, check a permission, capture, or read a clock.
public enum RecordlySourceSelectionBox {
    public enum Intent: Equatable, Sendable {
        case display(id: UInt32)
        case window(number: Int, identityToken: String)
        case region(displayID: UInt32, x: Double, y: Double, width: Double, height: Double)
    }

    public enum Permission: Equatable, Sendable {
        case unknown
        case denied
        case granted
    }

    public struct Window: Equatable, Sendable {
        public var number: Int
        public var identityToken: String
        public var isPresent: Bool

        public init(number: Int, identityToken: String, isPresent: Bool) {
            self.number = number
            self.identityToken = identityToken
            self.isPresent = isPresent
        }
    }

    public enum Ready: Equatable, Sendable {
        case display(id: UInt32)
        case window(number: Int, identityToken: String)
    }

    public enum Outcome: Equatable, Sendable {
        case ready(Ready)
        case denied(reason: String)
        case lostSource(reason: String)
        case invalidIntent(reason: String)
    }

    /// A window can be bound when it is on screen, owned by a positive process, numbered above
    /// zero, and its frame is finite and larger than 40 by 40 points.
    public static func acceptsWindow(
        number: Int,
        ownerProcessID: Int32?,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        isOnScreen: Bool
    ) -> Bool {
        guard let ownerProcessID, number > 0, ownerProcessID > 0, isOnScreen,
              x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 40, height > 40 else { return false }
        return true
    }

    /// The owner-bound token. A list position alone is not an identity.
    public static func identityToken(number: Int, ownerProcessID: Int32) -> String {
        "\(number):\(ownerProcessID)"
    }

    /// Display and window choices with a real identity can enable Record. A region cannot,
    /// until its coordinate contract is proven.
    public static func hasValidExplicitIdentity(_ intent: Intent) -> Bool {
        switch intent {
        case .display(let id): id != 0
        case .window(let number, let token):
            number > 0 && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .region:
            false
        }
    }

    /// Resolves only the exact identity in the supplied catalog. There is no first-display or
    /// first-window fallback, including for placeholder id or number 0.
    public static func resolve(
        intent: Intent,
        displayIDs: [UInt32],
        windows: [Window],
        permission: Permission
    ) -> Outcome {
        switch permission {
        case .unknown:
            return .denied(reason: "Screen Recording permission is unknown. Check System Settings before starting capture.")
        case .denied:
            return .denied(reason: "Screen Recording is off. Enable Zeus in System Settings → Privacy & Security → Screen Recording.")
        case .granted:
            break
        }

        switch intent {
        case .display(let id):
            guard id != 0 else {
                return .invalidIntent(reason: "Choose a specific display before starting capture.")
            }
            let matches = displayIDs.filter { $0 == id }
            guard !matches.isEmpty else {
                return .lostSource(reason: "The selected display is no longer available. Choose another display explicitly.")
            }
            guard matches.count == 1 else {
                return .invalidIntent(reason: "The display catalog contains an ambiguous identity. Refresh the display choices.")
            }
            return .ready(.display(id: id))

        case .window(let number, let identityToken):
            guard number > 0, !identityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .invalidIntent(reason: "Choose a window with a valid identity before starting capture.")
            }
            let bindings = windows.filter { $0.number == number }
            guard !bindings.isEmpty else {
                return .invalidIntent(reason: "The window choice is not bound to a known window identity. Choose a window explicitly.")
            }
            guard bindings.count == 1, let binding = bindings.first else {
                return .invalidIntent(reason: "The window catalog contains an ambiguous identity. Refresh the window choices.")
            }
            guard binding.identityToken == identityToken, binding.isPresent else {
                return .lostSource(reason: "The selected window is no longer available. Choose another window explicitly.")
            }
            return .ready(.window(number: number, identityToken: identityToken))

        case .region(let displayID, let x, let y, let width, let height):
            guard displayID != 0 else {
                return .invalidIntent(reason: "Choose a specific host display for the region before starting capture.")
            }
            guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
                  width > 0, height > 0 else {
                return .invalidIntent(reason: "Select a region with finite coordinates and positive width and height.")
            }
            guard (x + width).isFinite, (y + height).isFinite else {
                return .invalidIntent(reason: "Select a region with finite bounds.")
            }
            return .invalidIntent(reason: "Region coordinates have no verified coordinate-space source yet. Reselect after the region picker is available.")
        }
    }
}
