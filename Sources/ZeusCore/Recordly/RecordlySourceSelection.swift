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
            /// Global desktop frame in points, origin at the top left of the main display (CGDisplayBounds).
            public let frame: CGRect
            /// CGDisplayCreateUUIDFromDisplayID text. Unlike `id` it survives unplug and replug. Nil when unknown.
            public let stableID: String?
            /// NSScreen.localizedName, for example "Built-in Retina Display". Nil when unknown.
            public let name: String?
            /// True for the display that carries the menu bar.
            public let isMain: Bool

            public init(id: UInt32, frame: CGRect, stableID: String? = nil, name: String? = nil, isMain: Bool = false) {
                self.id = id
                self.frame = frame
                self.stableID = stableID
                self.name = name
                self.isMain = isMain
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
        guard let ownerProcessID,
              RecordlySourceSelectionBox.acceptsWindow(
                number: number,
                ownerProcessID: ownerProcessID,
                x: Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(frame.width),
                height: Double(frame.height),
                isOnScreen: isOnScreen)
        else { return nil }
        return .init(
            number: number,
            identityToken: RecordlySourceSelectionBox.identityToken(number: number, ownerProcessID: ownerProcessID),
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
        RecordlySourceSelectionBox.hasValidExplicitIdentity(boxIntent(intent))
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
        switch RecordlySourceSelectionBox.resolve(
            intent: boxIntent(intent),
            displayIDs: catalog.displays.map(\.id),
            windows: catalog.windows.map { window in
                RecordlySourceSelectionBox.Window(
                    number: window.number,
                    identityToken: window.identityToken,
                    isPresent: window.isPresent)
            },
            permission: boxPermission(permission)
        ) {
        case .ready(let ready):
            return .ready(readySource(ready))
        case .denied(let reason):
            return .denied(reason: reason)
        case .lostSource(let reason):
            return .lostSource(reason: reason)
        case .invalidIntent(let reason):
            return .invalidIntent(reason: reason)
        }
    }

    private static func boxPermission(_ permission: PermissionState) -> RecordlySourceSelectionBox.Permission {
        switch permission {
        case .unknown: .unknown
        case .denied: .denied
        case .granted: .granted
        }
    }

    private static func boxIntent(_ intent: SelectionIntent) -> RecordlySourceSelectionBox.Intent {
        switch intent {
        case .display(let id):
            .display(id: id)
        case .window(let number, let identityToken):
            .window(number: number, identityToken: identityToken)
        case .region(let displayID, let x, let y, let width, let height):
            .region(displayID: displayID, x: x, y: y, width: width, height: height)
        }
    }

    private static func readySource(_ ready: RecordlySourceSelectionBox.Ready) -> ResolvedSource {
        switch ready {
        case .display(let id):
            .display(id)
        case .window(let number, let identityToken):
            .window(number: number, identityToken: identityToken)
        }
    }
}
