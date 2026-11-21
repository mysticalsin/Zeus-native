import Foundation

public struct PortalPreviewTile: Equatable, Sendable {
    public var phase: String
    public var title: String
    public var detail: String
    public var animationDuration: Double
    public var pressScale: Double
}

public struct PortalControl: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case preview, status, toggle, choice, text, button
    }

    public var id: String
    public var label: String
    public var helper: String
    public var keyboardReachable: Bool
    public var kind: Kind
}

public enum PortalSectionModel {
    public static func preview(_ phase: PortalDropFlow.Phase, reduceMotion: Bool) -> PortalPreviewTile {
        let title: String
        let detail: String
        switch phase {
        case .idle:
            title = "Drop a file"
            detail = "Waiting for a file."
        case .received:
            title = "File received"
            detail = "File accepted. Conversion has not started."
        case .converting:
            title = "Converting"
            detail = "Converting on this Mac."
        case .done:
            title = "Converted"
            detail = "Converted."
        case .failed(let error):
            title = "Couldn't convert"
            detail = PortalCopy.sentence(error)
        }
        return PortalPreviewTile(
            phase: PortalPhaseName.name(phase),
            title: title,
            detail: detail,
            animationDuration: PortalSectionMetrics.animationDuration(reduceMotion: reduceMotion),
            pressScale: PortalSectionMetrics.pressScale(reduceMotion: reduceMotion)
        )
    }

    public static func controls(for board: PortalDeviceBoard, flow: PortalDropFlow) -> [PortalControl] {
        var rows: [PortalControl] = [
            row("portal.preview", "File tray", "Drop a file to convert it on this Mac. Nothing is uploaded.", .preview),
            row("portal.conversion", preview(flow.phase, reduceMotion: true).title, preview(flow.phase, reduceMotion: true).detail, .status),
        ]
        if case .done = flow.phase {
            rows.append(row("portal.reset", "Clear", "Clears the conversion and returns to waiting.", .button))
        } else if case .failed = flow.phase {
            rows.append(row("portal.reset", "Clear", "Clears the error and returns to waiting.", .button))
        }
        rows.append(row("portal.sync", "Send and receive with nearby devices", "Off until you turn it on. Nothing is advertised while it is off.", .toggle))
        rows.append(row("portal.visibility", "Who can see this Mac", "Paired only shows this Mac to devices you already paired. Off hides it.", .choice))
        rows.append(row("portal.deviceName", "Name shown to nearby devices", "Leave empty to use this Mac's name.", .text))
        switch board.phase {
        case .off:
            rows.append(row("portal.off", "Sync is off", board.status, .status))
        case .loading:
            rows.append(row("portal.loading", "Looking", board.status, .status))
        case .unavailable:
            rows.append(row("portal.error", "Nearby devices unavailable", board.status, .status))
        case .hidden:
            rows.append(row("portal.hidden", "Hidden", board.status, .status))
        case .everyone, .pairedOnly:
            if board.devices.isEmpty {
                rows.append(row("portal.empty", "No paired devices yet", board.status, .status))
            } else {
                for device in board.devices {
                    rows.append(row("portal.device.\(device.id)", device.name, "Paired with this Mac.", .status))
                    rows.append(row("portal.remove.\(device.id)", "Remove \(device.name)", "Removes the paired device. It must pair again before it can send.", .button))
                }
            }
        }
        if case .confirming(let id) = board.removal {
            rows.append(row("portal.confirmRemove", "Remove this device", "Confirms removal of \(id). This stays on the page.", .button))
            rows.append(row("portal.cancelRemove", "Cancel", "Keeps the paired device.", .button))
        }
        return rows
    }

    private static func row(_ id: String, _ label: String, _ helper: String, _ kind: PortalControl.Kind) -> PortalControl {
        PortalControl(id: id, label: label, helper: helper, keyboardReachable: true, kind: kind)
    }
}
