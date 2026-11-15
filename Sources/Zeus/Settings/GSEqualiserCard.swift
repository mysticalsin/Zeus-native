import AppKit
import SwiftUI
import ZeusCore

// Settings > Sounds > "Per-app sound": the owner's switch, one line that says what the equaliser is doing, and a row
// per app with its own shape switch, volume and ten bands. The card only asks the controller; it never starts one.

/// What the card does with the controller. Every change is clamped here, so the controller only ever sees values in
/// range. Kept apart from the views so a test can drive it with a fake.
@MainActor
struct EqualiserCardActions {
    let controller: any EqualiserControlling

    static let cardTitle = "Per-app sound"
    static let switchTitle = "Shape sound per app"
    static let switchText = "Taps only the apps you shape, with System Audio Recording. Off removes every tap."
    static let playingTag = "Playing"
    static let shapeTitle = "Shape this app"
    static let resetTitle = "Reset to flat"
    static let forgetTitle = "Forget this app"
    static let tryAgainTitle = "Try again"
    static let systemSettingsTitle = "Open System Settings"

    /// Every fixed string the card draws, so a test can check them all.
    static let allWords = [
        cardTitle, switchTitle, switchText, playingTag, shapeTitle, resetTitle, forgetTitle, tryAgainTitle,
        systemSettingsTitle, EqualiserPreset.customTitle,
    ] + EqualiserPreset.allCases.map(\.title)

    /// The status to draw. A snapshot shows a fixture (the fixed sample unless a render passes its own) and never reads
    /// the controller. With no controller the card reads as off.
    static func shownStatus(
        controller: (any EqualiserControlling)?, isSnapshot: Bool, fixture: EqualiserStatus? = nil
    ) -> EqualiserStatus {
        if isSnapshot { return fixture ?? EqualiserStatus.snapshotSample }
        guard let controller else {
            return EqualiserStatus(
                line: EqualiserStatusText.line(for: .off), symbol: EqualiserStatusText.symbol(for: .off), rows: [])
        }
        return controller.status
    }

    func setSwitch(_ on: Bool) {
        controller.setSwitch(on)
    }

    func setShapes(of row: EqualiserRow, on: Bool) {
        var settings = row.settings
        settings.shapes = on
        controller.update(settings.clamped())
    }

    func setVolume(of row: EqualiserRow, percent: Double) {
        var settings = row.settings
        settings.volume = percent.isNaN ? 1 : min(max(percent, 0), 100) / 100
        controller.update(settings.clamped())
    }

    func setBand(of row: EqualiserRow, index: Int, gain: Double) {
        guard row.settings.gainsDB.indices.contains(index) else { return }
        var settings = row.settings
        settings.gainsDB[index] = EqualiserBandControl.snapped(gain)
        controller.update(settings.clamped())
    }

    func applyPreset(_ preset: EqualiserPreset, to row: EqualiserRow) {
        var settings = row.settings
        settings.gainsDB = preset.gains
        controller.update(settings.clamped())
    }

    func resetToFlat(_ row: EqualiserRow) {
        applyPreset(.flat, to: row)
    }

    func forget(_ row: EqualiserRow) {
        controller.forget(bundleID: row.bundleID)
    }
}

struct GSEqualiserCard: View {
    let controller: (any EqualiserControlling)?
    @Binding var isOn: Bool
    @State private var openID: String?
    private let fixture: EqualiserStatus?

    /// `openID` and `fixture` are for snapshot renders only: which row starts open, and what a render shows in place
    /// of the sample.
    init(
        controller: (any EqualiserControlling)?, isOn: Binding<Bool>, openID: String? = nil,
        fixture: EqualiserStatus? = nil
    ) {
        self.controller = controller
        self._isOn = isOn
        self._openID = State(initialValue: openID)
        self.fixture = fixture
    }

    private var status: EqualiserStatus {
        EqualiserCardActions.shownStatus(controller: controller, isSnapshot: TopBarStyle.isSnapshot, fixture: fixture)
    }

    var body: some View {
        let status = status
        GSCard(EqualiserCardActions.cardTitle) {
            GSToggleRow(
                symbol: "slider.vertical.3", title: EqualiserCardActions.switchTitle,
                text: EqualiserCardActions.switchText, isOn: $isOn)
            GSDivider()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: status.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(GS.secondary)
                    .frame(width: 22).accessibilityHidden(true)
                Text(status.line).font(GS.rowText).foregroundStyle(GS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            ForEach(status.rows) { row in
                GSDivider()
                EqualiserAppRow(
                    row: row, isOpen: openID == row.bundleID, controller: controller,
                    toggleOpen: { toggleOpen(row.bundleID) })
            }
        }
    }

    private func toggleOpen(_ id: String) {
        openID = openID == id ? nil : id
    }
}

// MARK: - One app

private struct EqualiserAppRow: View {
    let row: EqualiserRow
    let isOpen: Bool
    let controller: (any EqualiserControlling)?
    let toggleOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actions: EqualiserCardActions? { controller.map(EqualiserCardActions.init) }
    private var excluded: Bool { row.exclusion != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen && !excluded {
                EqualiserBandPanel(row: row, controller: controller)
                    .padding(.bottom, 18)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: row.bundleID, name: row.displayName).frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.displayName).font(GS.rowTitle).foregroundStyle(GS.text).lineLimit(1)
                    if row.isPlaying { playingTag }
                }
                if let reason = row.exclusionLabel {
                    Text(reason).font(GS.rowText).foregroundStyle(GS.secondary)
                }
            }
            Spacer(minLength: 12)
            if !excluded {
                Text(EqualiserCardActions.shapeTitle).font(GS.rowText).foregroundStyle(GS.secondary).lineLimit(1)
                Toggle("Shape \(row.displayName)", isOn: Binding(
                    get: { row.settings.shapes }, set: { actions?.setShapes(of: row, on: $0) }))
                    .toggleStyle(GSToggleStyle()).labelsHidden()
                OBTickSlider(
                    value: Binding(
                        get: { (row.settings.clamped().volume * 100).rounded() },
                        set: { actions?.setVolume(of: row, percent: $0) }),
                    range: 0...100, step: 10)
                    .frame(width: 130).environment(\.ob, OB.Palette.settings)
                    .accessibilityLabel("Volume for \(row.displayName)")
                disclosure
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .opacity(excluded ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private var playingTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 9, weight: .bold))
            Text(EqualiserCardActions.playingTag).font(OB.font(11.5, .semibold))
        }
        .foregroundStyle(GS.selectedText)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(GS.selectedFill))
    }

    private var disclosure: some View {
        Button(action: toggleOpen) {
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(GS.controlText)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOpen)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.controlFill))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.controlStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Hide the bands for \(row.displayName)" : "Show the bands for \(row.displayName)")
    }
}

private struct AppIconView: View {
    let bundleID: String
    let name: String

    /// The app's own icon, or a tile with its first letter. A snapshot always draws the tile: a render that draws an
    /// app icon comes out washed, and a fixture should not depend on which apps this Mac has.
    var body: some View {
        if !TopBarStyle.isSnapshot, let icon = Self.icon(for: bundleID) {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Text(String(name.first.map { Character($0.uppercased()) } ?? "?"))
                .font(OB.font(15, .semibold)).foregroundStyle(GS.selectedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.selectedFill))
        }
    }

    private static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - The opened row

private struct EqualiserBandPanel: View {
    let row: EqualiserRow
    let controller: (any EqualiserControlling)?

    private var actions: EqualiserCardActions? { controller.map(EqualiserCardActions.init) }
    private var gains: [Double] { row.settings.clamped().gainsDB }

    private var presetTitle: String {
        EqualiserPreset.matching(gains)?.title ?? EqualiserPreset.customTitle
    }

    private var presetOptions: [String] {
        let titles = EqualiserPreset.allCases.map(\.title)
        return EqualiserPreset.matching(gains) == nil ? titles + [EqualiserPreset.customTitle] : titles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                GSPopup(
                    selection: Binding(
                        get: { presetTitle },
                        set: { title in
                            if let preset = EqualiserPreset.allCases.first(where: { $0.title == title }) {
                                actions?.applyPreset(preset, to: row)
                            }
                        }),
                    options: presetOptions, label: "Preset for \(row.displayName)")
                Spacer(minLength: 0)
                Button(EqualiserCardActions.resetTitle) { actions?.resetToFlat(row) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Reset \(row.displayName) to flat")
                Button(EqualiserCardActions.forgetTitle) { actions?.forget(row) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Forget \(row.displayName)")
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<EqualiserParameters.bandCount, id: \.self) { index in
                    GSBandSlider(
                        index: index,
                        gain: Binding(
                            get: { gains[index] },
                            set: { actions?.setBand(of: row, index: index, gain: $0) }))
                        .frame(maxWidth: .infinity)
                }
            }
            EqualiserCurveView(gains: gains).frame(height: 84)
        }
        .padding(.leading, 42)
        .padding(.trailing, 4)
    }
}

// MARK: - One band

/// A vertical slider from -12 to +12 dB. The fill grows from the 0 dB centre, ticks mark minus 12, minus 6, 0, plus 6
/// and plus 12, a drag snaps to half a decibel, and VoiceOver adjusts one step at a time.
struct GSBandSlider: View {
    let index: Int
    @Binding var gain: Double

    private let trackHeight: CGFloat = 132
    private let thumb: CGFloat = 16

    var body: some View {
        VStack(spacing: 6) {
            Text(valueText).font(OB.font(11.5, .semibold)).foregroundStyle(gain == 0 ? GS.secondary : GS.text)
                .monospacedDigit().lineLimit(1).frame(height: 14)
            track
            Text(EqualiserBandControl.label(at: index)).font(OB.font(11.5, .medium)).foregroundStyle(GS.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EqualiserBandControl.spokenName(at: index))
        .accessibilityValue(EqualiserGain.spokenValue(gain))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: gain = EqualiserBandControl.adjusted(gain, steps: 1)
            case .decrement: gain = EqualiserBandControl.adjusted(gain, steps: -1)
            @unknown default: break
            }
        }
    }

    private var valueText: String {
        let rounded = EqualiserBandControl.snapped(gain)
        let magnitude = abs(rounded)
        let number = magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(magnitude)
        return rounded > 0 ? "+\(number)" : (rounded < 0 ? "-\(number)" : "0")
    }

    private var track: some View {
        let fraction = CGFloat(EqualiserBandControl.fraction(for: gain))
        let centre = trackHeight / 2
        let thumbY = trackHeight * (1 - fraction)
        return ZStack(alignment: .top) {
            // Tick marks, left of the track.
            ForEach(EqualiserBandControl.ticks, id: \.self) { tick in
                Rectangle().fill(GS.secondary.opacity(tick == 0 ? 0.7 : 0.35))
                    .frame(width: tick == 0 ? 12 : 8, height: 1)
                    .offset(x: -(tick == 0 ? 11 : 13),
                            y: trackHeight * (1 - CGFloat(EqualiserBandControl.fraction(for: tick))))
            }
            Capsule().fill(OB.Palette.settings.track).frame(width: 6, height: trackHeight)
            // The fill runs from the centre to the thumb.
            Capsule().fill(OB.toggleOn)
                .frame(width: 6, height: max(abs(thumbY - centre), 0.5))
                .offset(y: min(thumbY, centre))
            Circle().fill(Color(rgb: 223, 224, 224)).frame(width: thumb, height: thumb)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                .offset(y: thumbY - thumb / 2)
        }
        .frame(width: 36, height: trackHeight, alignment: .top)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            gain = EqualiserBandControl.gain(atFraction: 1 - Double(drag.location.y / trackHeight))
        })
    }
}

// MARK: - The curve

/// The response of the ten bands together, drawn from the filter maths and never from audio.
private struct EqualiserCurveView: View {
    let gains: [Double]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = EqualiserCurve.points(gainsDB: gains)
            let range = EqualiserCurve.displayRange
            let span = range.upperBound - range.lowerBound
            let logSpan = log(EqualiserCurve.highFrequency / EqualiserCurve.lowFrequency)
            let positions: [CGPoint] = points.map { point in
                let x = log(point.frequency / EqualiserCurve.lowFrequency) / logSpan
                let db = min(max(point.decibels, range.lowerBound), range.upperBound)
                return CGPoint(x: size.width * x, y: size.height * (1 - (db - range.lowerBound) / span))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GS.window)
                Path { path in
                    for tick in [-6.0, 0.0, 6.0] {
                        let y = size.height * (1 - (tick - range.lowerBound) / span)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(GS.separator, lineWidth: 1)
                Path { path in
                    guard let first = positions.first else { return }
                    path.move(to: first)
                    positions.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(GS.selectedText, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        }
        .accessibilityHidden(true)
    }
}
