import SwiftUI
import ZeusCore

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
