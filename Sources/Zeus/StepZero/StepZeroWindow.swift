import Foundation

/// The one step-zero window.
///
/// The title is "Step zero" and the width is 560 points. Sharing is always none:
/// the probe does not read `general.showInScreenSharing`. An ordinary launch is an
/// accessory; this window uses the regular activation policy so it can be key.
public enum StepZeroWindow {
    public static let title = "Step zero"
    public static let width = 560

    public enum Sharing: String, Sendable, Equatable {
        case none
    }

    public static let sharingType = Sharing.none

    public enum Activation: String, Sendable, Equatable {
        case regular
    }

    public static let activation = Activation.regular

    /// The screen-sharing setting is not read.
    public static let readsScreenSharingSetting = false
}
