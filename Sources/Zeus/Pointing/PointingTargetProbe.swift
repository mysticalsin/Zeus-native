import ApplicationServices
import CoreGraphics
import Foundation
import ZeusCore

/// What the Accessibility hit test returned. Plain values only: no `AXUIElement` ever leaves
/// this file, so nothing here crosses an actor boundary unsafely.
struct PointingRawTarget: Sendable, Equatable {
    var role: String
    var subrole: String?
    var label: String?
    /// `AXIdentifier`, used only by the self-test. It is never sent to a model.
    var identifier: String? = nil
    /// Quartz global points (top-left origin), the Accessibility coordinate space.
    var axFrame: CGRect
    var isSecure: Bool
}

/// AX element under a point: `AXUIElementCopyElementAtPosition` on the system-wide element with a
/// 0.1 s messaging timeout. Reads role, subrole, a short title/description and the frame. It never
/// reads a value, so a password field's contents cannot be collected; a secure field also drops
/// its label.
///
/// Needs Accessibility trust, which the owner grants; this never asks for it.
enum PointingTargetProbe {
    static let messagingTimeout: Float = 0.1
    /// Overall budget for one probe, including the attribute reads.
    static let budget: TimeInterval = 0.05

    /// Main actor only: AX calls from this process stay on the main thread (repo rule). Each call is
    /// bounded by the 0.1 s messaging timeout and the attribute reads by `budget`.
    /// `quartzPoint` is already in Quartz global space.
    @MainActor static func hitTest(atQuartzPoint point: CGPoint) -> PointingRawTarget? {
        guard AXIsProcessTrusted(), point.x.isFinite, point.y.isFinite else { return nil }
        let started = ProcessInfo.processInfo.systemUptime
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
              let element = found else { return nil }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        let role = string(element, kAXRoleAttribute) ?? "AXUnknown"
        let subrole = string(element, kAXSubroleAttribute)
        let secure = subrole == "AXSecureTextField" || role == "AXSecureTextField"
        var label: String?
        if !secure, ProcessInfo.processInfo.systemUptime - started < budget {
            label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                .lazy.compactMap { string(element, $0) }.first { !$0.isEmpty }
        }
        guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else { return nil }
        let identifier = secure ? nil : string(element, "AXIdentifier")
        return PointingRawTarget(role: role, subrole: subrole, label: label, identifier: identifier,
                                 axFrame: frame, isSecure: secure)
    }

    /// The focused text input's frame in Quartz global points, so the explanation card can stay clear
    /// of where the owner is typing. Reads only the role and the frame, never a value, so a secure
    /// field's contents are not collected. Nil when Accessibility is not trusted or nothing editable has focus.
    nonisolated static func focusedInputFrame() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let role = string(element, kAXRoleAttribute),
              ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role),
              let frame = frame(of: element), frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        let rect = CGRect(origin: origin, size: size)
        return [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) ? rect : nil
    }
}
