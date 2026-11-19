import SwiftUI
import ZeusCore

/// What the "Displays without a notch" card shows and sends, apart from drawing it. The pure rules and the
/// calibration state live in ZeusCore and `DrawnNotchModel`; this reads them, picks the rows and forwards the
/// owner's actions as events. It is the only sender of calibration controls.
@MainActor
struct DrawnNotchCardModel {
    enum Row: Equatable {
        case shape(NotchlessStyle)
        case size(String)
        case width(Double)
        case height(Double)
        case offset(Double)
        case actions
        case notShown
        case noDisplay
    }

    static let statusSymbol = "display.trianglebadge.exclamationmark"
    static let statusButtonTitle = "Choose displays"

    static func statusText(_ availability: DrawnNotchAvailability) -> String {
        switch availability {
        case .ready: ""
        case .notShown: "Not shown on that display"
        case .noDisplay: "No display without a notch"
        }
    }

    let controller: any DrawnNotchControlling
    let navigation: GSNavigation

    /// Nil while no controller is set, which is how the card stays off the page until the app wires one in.
    init?(context: GSContext, navigation: GSNavigation) {
        guard let controller = context.drawnNotch else { return nil }
        self.controller = controller
        self.navigation = navigation
    }

    /// Row 1 is always there. Row 2 only for the Notch shape, and follows what the displays allow.
    var rows: [Row] {
        let style = controller.style
        var rows: [Row] = [.shape(style)]
        guard style == .drawn else { return rows }
        switch controller.availability {
        case .notShown:
            rows.append(.notShown)
        case .noDisplay:
            rows.append(.noDisplay)
        case .ready:
            if case .adjusting(let draft, _) = controller.state {
                rows += [.width(draft.width), .height(draft.height), .offset(draft.offset), .actions]
            } else {
                let saved = controller.saved
                rows.append(.size("\(Int(saved.width)) by \(Int(saved.height)) pt"))
            }
        }
        return rows
    }

    func choose(_ style: NotchlessStyle) { controller.setStyle(style) }
    func calibrate() { controller.send(.begin(saved: controller.saved)) }

    func setWidth(_ value: Double) {
        controller.send(.setWidth(DrawnNotchLimits.sanitized(DrawnNotchShape(width: value, height: 0, offset: 0)).width))
    }

    func setHeight(_ value: Double) {
        controller.send(.setHeight(DrawnNotchLimits.sanitized(DrawnNotchShape(width: 0, height: value, offset: 0)).height))
    }

    func setOffset(_ value: Double) {
        controller.send(.setOffset(DrawnNotchLimits.sanitized(DrawnNotchShape(width: 0, height: 0, offset: value)).offset))
    }

    func step(_ field: DrawnNotchCalibration.Field, _ direction: DrawnNotchCalibration.Direction) {
        controller.send(.step(field, direction))
    }

    func reset() { controller.send(.reset) }
    func cancel() { controller.send(.cancel) }
    func done() { controller.send(.done) }

    /// "Show the notch on" is a row of General: the one place that can make this display a target.
    func showTheNotchOnGeneral() { navigation.section = .general }

    /// The page changed, so the card is gone: whatever was being adjusted is dropped, not saved.
    func pageLeft() { controller.send(.surfaceGone(.pageLeft)) }
}

/// Appearance, after "Top bar": the shape a display without a notch draws, and the calibration of the drawn one.
struct DrawnNotchCard: View {
    let model: DrawnNotchCardModel

    var body: some View {
        GSCard("Displays without a notch") {
            let rows = model.rows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { GSDivider() }
                view(for: row)
            }
        }
        // The rows swap with no animation, so Reduce Motion needs no second path.
        .transaction { $0.animation = nil }
        .onDisappear { model.pageLeft() }
    }

    @ViewBuilder private func view(for row: DrawnNotchCardModel.Row) -> some View {
        switch row {
        case .shape(let style):
            GSRow(symbol: "rectangle.topthird.inset.filled", title: "Shape") {
                GSSegmentedChoice(label: "Shape", options: [("Pill", NotchlessStyle.pill), ("Notch", .drawn)],
                                  selection: style, onSelect: model.choose)
            }
        case .size(let text):
            GSRow(symbol: "arrow.up.left.and.arrow.down.right", title: "Size") {
                HStack(spacing: 12) {
                    Text(text).font(GS.rowText).foregroundStyle(GS.secondary).monospacedDigit()
                    Button("Calibrate", action: model.calibrate)
                        .buttonStyle(GSButtonStyle())
                        .accessibilityIdentifier("settings.appearance.drawnNotchCalibrate")
                }
            }
        case .width(let value):
            sliderRow(symbol: "arrow.left.and.right", label: "Width", value: value,
                      range: DrawnNotchLimits.widthRange, step: DrawnNotchLimits.widthStep,
                      onSet: model.setWidth, onStep: { model.step(.width, $0) })
        case .height(let value):
            sliderRow(symbol: "arrow.up.and.down", label: "Height", value: value,
                      range: DrawnNotchLimits.heightRange, step: DrawnNotchLimits.heightStep,
                      onSet: model.setHeight, onStep: { model.step(.height, $0) })
        case .offset(let value):
            sliderRow(symbol: "arrow.left.arrow.right", label: "Position", value: value,
                      range: DrawnNotchLimits.offsetRange, step: DrawnNotchLimits.offsetStep,
                      shown: DrawnNotchLimits.positionText(value), spoken: DrawnNotchLimits.positionText(value, unit: "points"),
                      onSet: model.setOffset, onStep: { model.step(.offset, $0) })
        case .actions:
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Reset", action: model.reset).buttonStyle(GSButtonStyle())
                Button("Cancel", action: model.cancel).buttonStyle(GSButtonStyle())
                Button("Done", action: model.done).buttonStyle(GSButtonStyle(prominent: true))
                    .accessibilityIdentifier("settings.appearance.drawnNotchDone")
            }
            .padding(.vertical, 14)
        case .notShown:
            GSRow(symbol: DrawnNotchCardModel.statusSymbol, title: DrawnNotchCardModel.statusText(.notShown)) {
                Button(DrawnNotchCardModel.statusButtonTitle, action: model.showTheNotchOnGeneral)
                    .buttonStyle(GSButtonStyle())
            }
        case .noDisplay:
            GSRow(symbol: DrawnNotchCardModel.statusSymbol, title: DrawnNotchCardModel.statusText(.noDisplay))
        }
    }

    /// `shown` and `spoken` default to the value in points; Position reads "Centre" or a side instead. The value
    /// column is wide enough for "400 pt right" in every row, so the three tracks line up.
    private func sliderRow(symbol: String, label: String, value: Double, range: ClosedRange<Double>, step: Double,
                           shown: String? = nil, spoken: String? = nil,
                           onSet: @escaping (Double) -> Void,
                           onStep: @escaping (DrawnNotchCalibration.Direction) -> Void) -> some View {
        GSRow(symbol: symbol, title: label) {
            HStack(spacing: 12) {
                GSPointSlider(label: label, value: value, range: range, step: step, spokenValue: spoken,
                              onSet: onSet, onStep: onStep)
                    .frame(width: 200)
                Text(shown ?? "\(Int(value)) pt").font(GS.rowText).foregroundStyle(GS.secondary).monospacedDigit()
                    .frame(width: 88, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A slider in points that takes the keyboard: focus it, then each arrow key is one step. VoiceOver speaks its
/// label and the value, such as "Width, 185 points" or "Position, 40 points left", and adjusts by one step. `OBTickSlider` speaks percent and
/// takes no focus, so it is left as it is.
struct GSPointSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// What VoiceOver says for the value; nil is the number and "points".
    var spokenValue: String? = nil
    let onSet: (Double) -> Void
    let onStep: (DrawnNotchCalibration.Direction) -> Void
    @FocusState private var focused: Bool

    private let thumb: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(GS.toggleOff).frame(height: 6)
                Capsule().fill(OB.toggleOn).frame(width: max(6, width * fraction), height: 6)
                Circle().fill(GS.knob).frame(width: thumb, height: thumb)
                    .overlay(Circle().strokeBorder(GS.selectedText, lineWidth: focused ? 2 : 0))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: (width - thumb) * fraction)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                focused = true
                let place = min(max((drag.location.x - thumb / 2) / max(width - thumb, 1), 0), 1)
                onSet(range.lowerBound + place * (range.upperBound - range.lowerBound))
            })
        }
        .frame(height: 22)
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) { onStep(.down); return .handled }
        .onKeyPress(.downArrow) { onStep(.down); return .handled }
        .onKeyPress(.rightArrow) { onStep(.up); return .handled }
        .onKeyPress(.upArrow) { onStep(.up); return .handled }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? "\(Int(value)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(.up)
            case .decrement: onStep(.down)
            @unknown default: break
            }
        }
    }
}

/// Two or three named choices side by side. The chosen one has a fill, a mark and the selected trait, so it is
/// never told apart by colour alone.
struct GSSegmentedChoice<Value: Equatable>: View {
    let label: String
    let options: [(title: String, value: Value)]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let chosen = option.value == selection
                Button { onSelect(option.value) } label: {
                    HStack(spacing: 5) {
                        if chosen { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).accessibilityHidden(true) }
                        Text(option.title).font(OB.font(13.5, chosen ? .semibold : .regular))
                    }
                    .foregroundStyle(chosen ? GS.selectedText : GS.text)
                    .frame(minWidth: 72, minHeight: 28)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(chosen ? GS.selectedFill : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GS.buttonFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GS.controlStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
