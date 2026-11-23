import Foundation
import ZeusCore

/// Browses the two receiver service types while the setting is on and stops when it is off.
/// `live` is false in tests, which record names without opening a Bonjour search.
@MainActor
final class ReceiverNameBrowser: NSObject, NetServiceBrowserDelegate {
    private var browsers: [NetServiceBrowser] = []
    private var services: [ReceiverService] = []
    private let live: Bool
    private(set) var names: [String] = []

    init(live: Bool = true) {
        self.live = live
    }

    var isBrowsing: Bool { !browsers.isEmpty }

    func setEnabled(_ on: Bool) {
        stopBrowsers()
        services = []
        names = []
        guard on, live else { return }
        for type in ReceiverNames.bonjourTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            let ofType = type.hasSuffix(".") ? type : type + "."
            browser.searchForServices(ofType: ofType, inDomain: "local.")
            browsers.append(browser)
        }
    }

    func note(name: String, type: String) {
        services.append(ReceiverService(name: name, type: type))
        names = ReceiverCatalog.names(services)
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let foundName = service.name
        let foundType = service.type
        MainActor.assumeIsolated { note(name: foundName, type: foundType) }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let removedName = service.name
        let rawType = service.type
        let removedType = rawType.hasSuffix(".") ? String(rawType.dropLast()) : rawType
        MainActor.assumeIsolated {
            services.removeAll { $0.name == removedName && ($0.type == rawType || $0.type == removedType) }
            names = ReceiverCatalog.names(services)
        }
    }

    private func stopBrowsers() {
        for browser in browsers { browser.stop() }
        browsers = []
    }
}
