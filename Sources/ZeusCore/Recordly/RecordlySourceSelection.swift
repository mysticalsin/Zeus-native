import CoreGraphics
import Foundation

/// Pure source-selection values shared by the Recordly controller and engine.
/// Catalog contents are supplied by the caller; this type performs no listing,
/// permission checks, capture, or I/O.
public enum RecordlySourceSelection {
    public enum Kind: String, Equatable, Sendable {
        case display
        case window
        case region
    }

    /// A user's explicit choice. Window IDs are paired with an owner-bound token
    /// so a list position or a different app's window cannot replace the choice.
    public enum SelectionIntent: Equatable, Sendable {
        case display(id: UInt32)
        case window(number: Int, identityToken: String)
        case region(displayID: UInt32, x: Double, y: Double, width: Double, height: Double)

        public var kind: Kind {
            switch self {
            case .display: .display
            case .window: .window
            case .region: .region
            }
        }
    }

    public enum PermissionState: Equatable, Sendable {
        case unknown
        case denied
        case granted
    }

    /// Caller-supplied catalog values. This model performs no device listing,
    /// permission check, capture, or I/O.
    public struct CatalogSnapshot: Equatable, Sendable {
        public struct Display: Equatable, Sendable {
            public let id: UInt32
            public let frame: CGRect

            public init(id: UInt32, frame: CGRect) {
                self.id = id
                self.frame = frame
            }
        }

        public struct Window: Equatable, Sendable {
            public let number: Int
            public let identityToken: String
            public let isPresent: Bool
            public let title: String?
            public let ownerName: String?

            public init(
                number: Int,
                identityToken: String,
                isPresent: Bool,
                title: String? = nil,
                ownerName: String? = nil
            ) {
                self.number = number
                self.identityToken = identityToken
                self.isPresent = isPresent
                self.title = title
                self.ownerName = ownerName
            }
        }

        public let displays: [Display]
        public let windows: [Window]

        public init(displays: [Display] = [], windows: [Window] = []) {
            self.displays = displays
            self.windows = windows
        }
    }

    /// The single production mapping rule for an on-screen window. Keeping the
    /// identity token and visibility/size filter together prevents controller
    /// choices and the engine's fresh catalog from drifting apart.
    public static func windowBinding(
        number: Int,
        ownerProcessID: Int32?,
        title: String?,
        frame: CGRect,
        isOnScreen: Bool,
        ownerName: String? = nil
    ) -> CatalogSnapshot.Window? {
        guard let ownerProcessID, number > 0, ownerProcessID > 0, isOnScreen,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 40, frame.height > 40 else { return nil }
        let token = "\(number):\(ownerProcessID)"
        return .init(
            number: number,
            identityToken: token,
            isPresent: true,
            title: title,
            ownerName: ownerName
        )
    }

    public static func intent(for source: ResolvedSource) -> SelectionIntent? {
        switch source.kind {
        case .display:
            guard let id = source.displayID else { return nil }
            return .display(id: id)
        case .window:
            guard let number = source.windowNumber, let token = source.windowIdentityToken else { return nil }
            return .window(number: number, identityToken: token)
        case .region:
            guard let id = source.displayID, let rect = source.cropRect else { return nil }
            return .region(displayID: id, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        }
    }

    public static func hasValidExplicitIdentity(_ intent: SelectionIntent) -> Bool {
        switch intent {
        case .display(let id): id != 0
        case .window(let number, let token):
            number > 0 && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .region:
            false
        }
    }

    public struct ResolvedSource: Equatable, Sendable {
        public let kind: Kind
        public let displayID: UInt32?
        public let windowNumber: Int?
        public let windowIdentityToken: String?
        /// Non-nil for a region and exactly equal to the selected crop rect.
        public let cropRect: CGRect?

        private init(
            kind: Kind,
            displayID: UInt32? = nil,
            windowNumber: Int? = nil,
            windowIdentityToken: String? = nil,
            cropRect: CGRect? = nil
        ) {
            self.kind = kind
            self.displayID = displayID
            self.windowNumber = windowNumber
            self.windowIdentityToken = windowIdentityToken
            self.cropRect = cropRect
        }

        fileprivate static func display(_ id: UInt32) -> Self {
            Self(kind: .display, displayID: id)
        }

        fileprivate static func window(number: Int, identityToken: String) -> Self {
            Self(kind: .window, windowNumber: number, windowIdentityToken: identityToken)
        }

        fileprivate static func region(_ rect: CGRect, hostDisplayID: UInt32) -> Self {
            Self(kind: .region, displayID: hostDisplayID, cropRect: rect)
        }
    }

    /// Adapts a resolved choice to the legacy capture value. The current
    /// resolver rejects region intents until their coordinate contract is proven.
    public struct CaptureAdapter: Equatable, Sendable {
        public let source: RecordlyCaptureSource
        public let hostDisplayID: UInt32?
        public let cropRect: CGRect?

        public init(_ resolved: ResolvedSource) {
            hostDisplayID = resolved.displayID
            cropRect = resolved.cropRect
            switch resolved.kind {
            case .display:
                source = .display(id: resolved.displayID!)
            case .window:
                source = .window(number: resolved.windowNumber!)
            case .region:
                source = .region(resolved.cropRect!)
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case ready(ResolvedSource)
        case denied(reason: String)
        case lostSource(reason: String)
        case invalidIntent(reason: String)
    }

    /// Resolves only the exact identity in the supplied snapshot. There is no
    /// first-display/window fallback, including for placeholder id/number 0.
    public static func resolve(
        intent: SelectionIntent,
        in catalog: CatalogSnapshot,
        permission: PermissionState
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
            let matches = catalog.displays.filter { $0.id == id }
            guard !matches.isEmpty else {
                return .lostSource(reason: "The selected display is no longer available. Choose another display explicitly.")
            }
            guard matches.count == 1 else {
                return .invalidIntent(reason: "The display catalog contains an ambiguous identity. Refresh the display choices.")
            }
            return .ready(.display(id))

        case .window(let number, let identityToken):
            guard number > 0, !identityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .invalidIntent(reason: "Choose a window with a valid identity before starting capture.")
            }
            let bindings = catalog.windows.filter { $0.number == number }
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
