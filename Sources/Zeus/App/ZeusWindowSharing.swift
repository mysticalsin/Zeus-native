import AppKit
import ZeusCore

/// N1-N3: one place that maps policy to `NSWindow.sharingType` for every Zeus surface.
@MainActor
enum ZeusWindowSharing {
    enum Surface {
        case zeusStandard
        case prompterOwnHide(Bool)
    }

    static func policy(showInScreenSharing: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool) -> Bool {
        ZeusScreenSharePolicy.zeusSurfacesVisible(
            showInScreenSharing: showInScreenSharing,
            meetingActive: meetingActive,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
    }

    static func sharingType(visibleInShare: Bool, surface: Surface) -> NSWindow.SharingType {
        switch surface {
        case .zeusStandard:
            return visibleInShare ? .readOnly : .none
        case .prompterOwnHide(let hidden):
            return visibleInShare && !hidden ? .readOnly : .none
        }
    }

    static func apply(to window: NSWindow, visibleInShare: Bool, surface: Surface) {
        let want = sharingType(visibleInShare: visibleInShare, surface: surface)
        if window.sharingType != want { window.sharingType = want }
    }

    static func refresh(
        showInScreenSharing: Bool,
        meetingActive: Bool,
        teleprompterSessionHidden: Bool,
        extraWindows: [NSWindow] = []
    ) {
        let visible = policy(
            showInScreenSharing: showInScreenSharing,
            meetingActive: meetingActive,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
        for window in NSApp.windows + extraWindows {
            if let prompter = window as? PrompterPanel {
                apply(to: window, visibleInShare: visible, surface: .prompterOwnHide(prompter.hiddenFromCapture))
            } else {
                apply(to: window, visibleInShare: visible, surface: .zeusStandard)
            }
        }
        NotchControllerBridge.controller?.applyScreenSharePolicy(visibleInShare: visible)
        BuddyControllerBridge.shared?.applyScreenSharePolicy(visibleInShare: visible)
        MarkOverlay.shared.applyScreenSharePolicy(visibleInShare: visible)
        ScreenEdgeGlowController.shared.applyScreenSharePolicy(visibleInShare: visible)
        EdgeWaveController.shared.applyScreenSharePolicy(visibleInShare: visible)
        PolyglotCaptionBridge.shared?.applyScreenSharePolicy(visibleInShare: visible)
    }

    static func refreshFromAppState(teleprompterSessionHidden: Bool = false) {
        let store = SettingsStore.shared
        let show = store.bool(ZeusScreenSharePolicy.showInSharingKey)
        refresh(
            showInScreenSharing: show,
            meetingActive: MeetingState.active,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
    }
}

@MainActor
enum BuddyControllerBridge {
    static weak var shared: BuddyController?
}

@MainActor
enum PolyglotCaptionBridge {
    static weak var shared: PolyglotCaptionSharing?
}

@MainActor
protocol PolyglotCaptionSharing: AnyObject {
    func applyScreenSharePolicy(visibleInShare: Bool)
}
