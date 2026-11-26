import Foundation

/// A settings change can turn one earbuds switch on or off.
/// The Allow button is the only door for the Bluetooth prompt, and this
/// forwarder does not call it.
@MainActor
public protocol EarbudsSwitchReceiving: AnyObject {
    func switchChanged(on: Bool)
    func ownerPressedAllow()
}

/// Maps the two earbuds setting ids onto the matching controller.
/// Any other id is ignored. The stored value is passed through as given.
@MainActor
public enum EarbudsSwitchForwarder {
    /// Appearance row "Earbuds in the notch".
    public static let presenceID = "lights.earbuds"
    /// Appearance row "Listening mode on the Music page".
    public static let modeID = "earbuds.listeningMode"

    public static func forward(
        id: String,
        value: Bool,
        presence: (any EarbudsSwitchReceiving)?,
        mode: (any EarbudsSwitchReceiving)?
    ) {
        switch id {
        case presenceID:
            presence?.switchChanged(on: value)
        case modeID:
            mode?.switchChanged(on: value)
        default:
            break
        }
    }
}
