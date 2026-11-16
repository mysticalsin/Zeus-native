import AppKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// A controller that records what the card asks of it. `send` runs the real reducer so a state follows an event.
@MainActor
private final class RecordingController: DrawnNotchControlling {
    var style: NotchlessStyle
    var saved: DrawnNotchShape
    var state: DrawnNotchCalibration.State = .idle
    var availability: DrawnNotchAvailability
    private(set) var events: [DrawnNotchCalibration.Event] = []
    private(set) var styles: [NotchlessStyle] = []

    init(style: NotchlessStyle = .drawn, availability: DrawnNotchAvailability = .ready,
         saved: DrawnNotchShape = DrawnNotchLimits.defaultShape) {
        self.style = style
        self.availability = availability
        self.saved = saved
    }

    func setStyle(_ style: NotchlessStyle) {
        styles.append(style)
        self.style = style
    }

    func send(_ event: DrawnNotchCalibration.Event) {
        events.append(event)
        state = DrawnNotchCalibration.reduce(state, event).0
    }

    var touched: Bool { !events.isEmpty || !styles.isEmpty }
    /// Every event after the first one, which each test spends on Calibrate.
    var afterBegin: [DrawnNotchCalibration.Event] { Array(events.dropFirst()) }
}

@MainActor
private func context(_ controller: (any DrawnNotchControlling)? = nil) -> GSContext {
    let context = GSContext(services: OnboardingServices(permissions: PermissionsModel()))
    context.drawnNotch = controller
    return context
}

@MainActor
private func card(_ controller: RecordingController, navigation: GSNavigation = GSNavigation()) throws -> DrawnNotchCardModel {
    try #require(DrawnNotchCardModel(context: context(controller), navigation: navigation))
}

@MainActor @Suite("Drawn notch card", .serialized)
struct DrawnNotchCardTests {
    // MARK: Rows

    @Test func theCardIsAbsentWithoutAController() {
        #expect(DrawnNotchCardModel(context: context(nil), navigation: GSNavigation()) == nil)
    }

    @Test func thePillShowsOnlyTheShapeRow() throws {
        let model = try card(RecordingController(style: .pill))
        #expect(model.rows == [.shape(.pill)])
    }

    @Test func aReadyNotchShowsTheSavedSizeAndCalibrate() throws {
        let controller = RecordingController(saved: DrawnNotchShape(width: 200, height: 36, offset: 0))
        let model = try card(controller)
        #expect(model.rows == [.shape(.drawn), .size("200 by 36 pt")])
    }

    @Test func calibrateSendsBeginWithTheSavedShapeAndTheRowBecomesThree() throws {
        let saved = DrawnNotchShape(width: 200, height: 36, offset: 40)
        let controller = RecordingController(saved: saved)
        let model = try card(controller)
        model.calibrate()
        #expect(controller.events == [.begin(saved: saved)])
        #expect(model.rows == [.shape(.drawn), .width(200), .height(36), .offset(40), .actions])
    }

    @Test func theSlidersShowTheDraftNotTheSavedShape() throws {
        let controller = RecordingController()
        let model = try card(controller)
        model.calibrate()
        model.setWidth(240)
        model.setHeight(40)
        model.setOffset(-60)
        #expect(model.rows == [.shape(.drawn), .width(240), .height(40), .offset(-60), .actions])
        #expect(controller.saved == DrawnNotchLimits.defaultShape)
    }

    @Test func aDisplayThatIsNotATargetShowsTheStatusAndAButton() throws {
        let model = try card(RecordingController(availability: .notShown))
        #expect(model.rows == [.shape(.drawn), .notShown])
    }

    @Test func noDisplayShowsTheStatusAndNoButton() throws {
        let model = try card(RecordingController(availability: .noDisplay))
        #expect(model.rows == [.shape(.drawn), .noDisplay])
        #expect(!model.rows.contains(.actions))
    }

    @Test func theStatusesNameThemselvesWithASymbolAndTheCalibrateRowHasNone() {
        #expect(DrawnNotchCardModel.statusText(.notShown) == "Not shown on that display")
        #expect(DrawnNotchCardModel.statusText(.noDisplay) == "No display without a notch")
        #expect(DrawnNotchCardModel.statusSymbol == "display.trianglebadge.exclamationmark")
        #expect(DrawnNotchCardModel.statusButtonTitle == "Choose displays")
    }

    // MARK: Events

    @Test func aSliderSendsAClampedSnappedSet() throws {
        let controller = RecordingController()
        let model = try card(controller)
        model.calibrate()
        model.setWidth(999)
        model.setWidth(10)
        model.setWidth(187)
        model.setHeight(99)
        model.setHeight(1)
        model.setOffset(999)
        model.setOffset(-999)
        model.setOffset(42)
        #expect(controller.afterBegin == [.setWidth(280), .setWidth(140), .setWidth(185), .setHeight(44), .setHeight(30),
                                         .setOffset(400), .setOffset(-400), .setOffset(40)])
    }

    @Test func aNonFiniteSliderValueSendsTheDefault() throws {
        let controller = RecordingController()
        let model = try card(controller)
        model.calibrate()
        model.setWidth(.nan)
        model.setHeight(.infinity)
        model.setOffset(-.infinity)
        #expect(controller.afterBegin == [.setWidth(185), .setHeight(32), .setOffset(0)])
    }

    @Test func arrowStepsSendOneStepEach() throws {
        let controller = RecordingController()
        let model = try card(controller)
        model.calibrate()
        model.step(.width, .up)
        model.step(.height, .down)
        model.step(.offset, .up)
        #expect(controller.afterBegin == [.step(.width, .up), .step(.height, .down), .step(.offset, .up)])
    }

    @Test func resetCancelAndDoneSendTheirEvents() throws {
        let controller = RecordingController()
        let model = try card(controller)
        model.calibrate()
        model.reset()
        model.cancel()
        model.calibrate()
        model.done()
        #expect(controller.afterBegin == [.reset, .cancel, .begin(saved: DrawnNotchLimits.defaultShape), .done])
        #expect(controller.state == .idle)
    }

    @Test func choosingTheStyleGoesThroughTheController() throws {
        let controller = RecordingController(style: .pill)
        let model = try card(controller)
        model.choose(.drawn)
        model.choose(.pill)
        #expect(controller.styles == [.drawn, .pill])
    }

    @Test func leavingThePageSendsPageLeftAndNothingElse() throws {
        let controller = RecordingController()
        let model = try card(controller)
        model.calibrate()
        model.pageLeft()
        #expect(controller.afterBegin == [.surfaceGone(.pageLeft)])
        #expect(controller.state == .idle)
    }

    @Test func theNotShownButtonOpensGeneral() throws {
        let navigation = GSNavigation()
        navigation.section = .appearance
        let model = try card(RecordingController(availability: .notShown), navigation: navigation)
        model.showTheNotchOnGeneral()
        #expect(navigation.section == .general)
    }

    // MARK: The window sends its losses

    @Test func closingAndMinimisingTheWindowSendTheirLosses() {
        let controller = RecordingController()
        let windowController = GlanceSettingsWindowController(context: context(controller))
        windowController.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        windowController.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
        #expect(controller.events == [.surfaceGone(.settingsClosed), .surfaceGone(.settingsMinimised)])
    }

    @Test func withoutAControllerTheWindowMethodsDoNothing() {
        let windowController = GlanceSettingsWindowController(context: context(nil))
        windowController.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        windowController.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
        #expect(windowController.debugWindow == nil)
    }

    // MARK: The settings rows and the import

    @Test func theCatalogHoldsTheShapeAndSizeRowsWithTheirDefaults() throws {
        let shape = try #require(SettingsCatalog.option(DrawnNotchModel.Row.style))
        #expect(shape.section == .appearance)
        #expect(shape.kind == .choice)
        #expect(shape.state == .live)
        #expect(shape.choices == ["Pill", "Notch"])
        #expect(shape.defaultValue == "Pill")
        let width = try #require(SettingsCatalog.option(DrawnNotchModel.Row.width))
        #expect(width.kind == .slider)
        #expect(width.range?.min == DrawnNotchLimits.widthRange.lowerBound)
        #expect(width.range?.max == DrawnNotchLimits.widthRange.upperBound)
        #expect(width.range?.step == DrawnNotchLimits.widthStep)
        #expect(width.defaultValue == "185")
        let height = try #require(SettingsCatalog.option(DrawnNotchModel.Row.height))
        #expect(height.kind == .slider)
        #expect(height.range?.min == DrawnNotchLimits.heightRange.lowerBound)
        #expect(height.range?.max == DrawnNotchLimits.heightRange.upperBound)
        #expect(height.range?.step == DrawnNotchLimits.heightStep)
        #expect(height.defaultValue == "32")
    }

    @Test func theCatalogHoldsThePositionRowCentredByDefault() throws {
        let position = try #require(SettingsCatalog.option(DrawnNotchModel.Row.offset))
        #expect(position.section == .appearance)
        #expect(position.group == "Displays without a notch")
        #expect(position.title == "Position")
        #expect(position.kind == .slider)
        #expect(position.state == .live)
        #expect(position.range?.min == DrawnNotchLimits.offsetRange.lowerBound)
        #expect(position.range?.max == DrawnNotchLimits.offsetRange.upperBound)
        #expect(position.range?.step == DrawnNotchLimits.offsetStep)
        #expect(position.defaultValue == "0")
    }

    private func importing(_ options: [String: String], over start: [String: String] = [:]) throws -> SettingsStore {
        let suite = NSTemporaryDirectory() + "zeus.drawn.card.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        for (id, value) in start { store.set(id, value) }
        let file: [String: Any] = ["format": "zeus.settings", "version": 1, "options": options, "app": [String: String]()]
        try store.importJSON(JSONSerialization.data(withJSONObject: file))
        defaults.removePersistentDomain(forName: suite)
        return store
    }

    @Test func anImportHoldingNotchLeavesThePillInPlace() throws {
        let store = try importing([DrawnNotchModel.Row.style: "Notch"])
        #expect(store.string(DrawnNotchModel.Row.style) == "Pill")
        #expect(SettingsStore.importWouldSelectDrawnNotch(id: DrawnNotchModel.Row.style, value: "Notch"))
    }

    @Test func anImportHoldingPillOverNotchIsApplied() throws {
        let store = try importing([DrawnNotchModel.Row.style: "Pill"], over: [DrawnNotchModel.Row.style: "Notch"])
        #expect(store.string(DrawnNotchModel.Row.style) == "Pill")
        #expect(!SettingsStore.importWouldSelectDrawnNotch(id: DrawnNotchModel.Row.style, value: "Pill"))
    }

    @Test func anImportAppliesTheSizesAndRejectsOnesOutsideTheirRange() throws {
        let store = try importing([DrawnNotchModel.Row.width: "220", DrawnNotchModel.Row.height: "99"])
        #expect(store.string(DrawnNotchModel.Row.width) == "220")
        #expect(store.string(DrawnNotchModel.Row.height) == "32")
    }

    @Test func anImportAppliesAPositionInsideTheRangeAndRejectsOneOutsideIt() throws {
        let inside = try importing([DrawnNotchModel.Row.offset: "-120"])
        #expect(inside.string(DrawnNotchModel.Row.offset) == "-120")
        let outside = try importing([DrawnNotchModel.Row.offset: "900"])
        #expect(outside.string(DrawnNotchModel.Row.offset) == "0")
        #expect(!SettingsStore.importWouldSelectDrawnNotch(id: DrawnNotchModel.Row.offset, value: "Notch"))
    }

    @Test func onlyTheStyleRowIsGuarded() {
        #expect(!SettingsStore.importWouldSelectDrawnNotch(id: DrawnNotchModel.Row.width, value: "Notch"))
        #expect(!SettingsStore.importWouldSelectDrawnNotch(id: "notch.openTrigger", value: "Notch"))
    }

    // MARK: Snapshots

    @Test func renderingTheCardNeverTouchesTheController() throws {
        for (style, availability) in [(NotchlessStyle.pill, DrawnNotchAvailability.ready), (.drawn, .ready),
                                      (.drawn, .notShown), (.drawn, .noDisplay)] {
            let controller = RecordingController(style: style, availability: availability)
            let model = try card(controller)
            let renderer = ImageRenderer(content: DrawnNotchCard(model: model).frame(width: 760))
            renderer.scale = 1
            #expect(renderer.nsImage != nil)
            #expect(!controller.touched)
        }
    }
}
