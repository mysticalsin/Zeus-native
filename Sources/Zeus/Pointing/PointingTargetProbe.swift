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

    /// Runs off the main actor. `quartzPoint` is already in Quartz global space.
    /// Verify: AX client calls off the main thread are not documented as thread-safe by Apple.
    /// They are used this way by many tools, and the timeout bounds a stall; if a target app
    /// misbehaves, move this call to the main thread behind the same timeout.
    nonisolated static func hitTest(atQuartzPoint point: CGPoint) -> PointingRawTarget? {
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
        return PointingRawTarget(role: role, subrole: subrole, label: label, axFrame: frame, isSecure: secure)
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
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
