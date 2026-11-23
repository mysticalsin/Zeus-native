import SwiftUI
import ZeusCore

/// Holds the click window for every top-bar summary. The decision is `TopBarWidgetClicks`. This only sleeps
/// until the date that decision returned, the same way a notch click waits out its own delay.
@MainActor
final class TopBarWidgetClickSession {
    private var clicks = TopBarWidgetClicks()
    private var wake: Task<Void, Never>?
    var now: () -> Date = { Date() }

    func tap(_ target: TopBarWidgetTarget, apply: @escaping (TopBarWidgetEffect) -> Void) {
        let step = clicks.click(target, at: now())
        for effect in step.effects { apply(effect) }
        arm(step.arm, apply: apply)
    }

    func activate(_ target: TopBarWidgetTarget, apply: (TopBarWidgetEffect) -> Void) {
        wake?.cancel()
        wake = nil
        let step = clicks.activate(target)
        for effect in step.effects { apply(effect) }
    }

    func showDetails(_ target: TopBarWidgetTarget) -> TopBarWidgetEffect? {
        wake?.cancel()
        wake = nil
        return clicks.showDetails(target)
    }

    private func arm(_ until: Date?, apply: @escaping (TopBarWidgetEffect) -> Void) {
        wake?.cancel()
        wake = nil
        guard let until else { return }
        let delay = until.timeIntervalSince(now())
        wake = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.wake = nil
            let settled = self.clicks.tick(at: self.now())
            for effect in settled.effects { apply(effect) }
            self.arm(settled.arm, apply: apply)
        }
    }
}

extension TopBarModel {
    func receiveWidgetTap(_ target: TopBarWidgetTarget) {
        widgetClicks.tap(target) { [weak self] effect in
            self?.performWidgetClick(effect)
        }
    }

    func activateWidget(_ target: TopBarWidgetTarget) {
        widgetClicks.activate(target) { [weak self] effect in
            self?.performWidgetClick(effect)
        }
    }

    func showWidgetDetails(_ target: TopBarWidgetTarget) {
        guard let effect = widgetClicks.showDetails(target) else { return }
        performWidgetClick(effect)
    }

    func performWidgetClick(_ effect: TopBarWidgetEffect) {
        switch effect {
        case .play:
            musicCommand(.play)
        case .pause:
            musicCommand(.pause)
        case .next:
            musicCommand(.next)
        case .refreshWeather:
            refreshWeather()
        case .toggleFocus:
            if focus.phase == .idle { focus.start() } else { focus.stop() }
        case .selectNextEvent:
            let moment = Date()
            if let next = events.first(where: { $0.end > moment }) {
                calendarDay = next.start
            }
        case .openDetails(let page):
            let tab: TopBarTab
            switch page {
            case .music: tab = .music
            case .calendar: tab = .calendar
            case .weather: tab = .weather
            case .focus: tab = .focus
            case .agents: tab = .agents
            }
            if TopBarWidgetClicks.detailsDuration(reduceMotion: Motion.reduced) == 0 {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.selectedTab = tab }
            } else {
                selectedTab = tab
            }
        }
    }
}

extension View {
    /// A summary chip: one click waits out the window, a second click inside it opens details.
    func topBarWidgetTap(_ target: TopBarWidgetTarget, model: TopBarModel) -> some View {
        contentShape(Rectangle())
            .onTapGesture { model.receiveWidgetTap(target) }
            .accessibilityAction { model.activateWidget(target) }
            .accessibilityAction(named: "Show details") { model.showWidgetDetails(target) }
    }
}
