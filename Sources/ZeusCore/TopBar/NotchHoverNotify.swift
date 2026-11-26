import Foundation

/// How a hover expand and a notification share the island.
///
/// The island's width and height are animatable. A notification that changes the
/// island in the same turn (a peek fold, a new agent card, or an alert inserted
/// into the stack) restarts that animation. These decisions keep one surface
/// change per turn. They do not pick a spring: Reduce Motion stays with the view.
public enum NotchHoverNotify {
    public enum Surface: Equatable, Sendable {
        case closed, peek, panel
    }

    /// What to do with an alert that wants to join the stack.
    public enum AlertAdmission: Equatable, Sendable {
        /// Insert it. The island is closed and no hover dwell is running.
        case post
        /// Keep it off the stack until the island is closed and idle, so `isEmpty` does not flip mid-animation.
        case hold
        /// The island is already showing something else and this alert is not asked to wait.
        case drop
    }

    /// The pointer is on the notification capsule: the dwell must not open the island out from under it.
    public static func cancelArmedHover(pointerOnNotification: Bool, hoverArmed: Bool) -> Bool {
        pointerOnNotification && hoverArmed
    }

    /// The dwell opens the island only while the pointer is still on the island and not on the capsule.
    /// A peek is not the panel: hovering promotes it, the same way a click does.
    public static func commitHover(inHotZone: Bool, pointerOnNotification: Bool, surface: Surface) -> Bool {
        inHotZone && !pointerOnNotification && surface != .panel
    }

    /// An agent card (Claude finished, failed, or needs you) must not move a closed island to peek
    /// while a dwell is running, and must not pull an open panel back to peek.
    public static func deferAgentPeek(surface: Surface, hoverArmed: Bool) -> Bool {
        hoverArmed || surface == .panel
    }

    /// The peek's own timer must not close the island while a dwell is about to open it.
    public static func deferPeekFold(surface: Surface, hoverArmed: Bool) -> Bool {
        hoverArmed && surface == .peek
    }

    public static func alertAdmission(surface: Surface, hoverArmed: Bool, whileOpen: Bool) -> AlertAdmission {
        if hoverArmed { return .hold }
        if surface == .closed { return .post }
        return whileOpen ? .hold : .drop
    }

    /// The capsule is drawn only on a resting closed island. While a dwell is armed it is already
    /// unmounted, so the later expand does not remove it inside the size transaction.
    public static func mountAlert(surface: Surface, hoverArmed: Bool, hasAlert: Bool) -> Bool {
        hasAlert && surface == .closed && !hoverArmed
    }

    /// Peek to panel removes the card without a transition. A transition would lay the card out
    /// in the panel's frame while the outline is still the in-between size.
    public static func dropPeekContent(from: Surface, to: Surface) -> Bool {
        from == .peek && to == .panel
    }
}
