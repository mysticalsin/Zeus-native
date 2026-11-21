import Foundation
import Network
import ZeusCore

/// Reads announced speaker names. It does not open a connection, and it stays idle until the section starts it.
final class AccessorySpeakerBrowser: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "zeus.accessory.speakers")
    private var browsers: [NWBrowser] = []
    private var names: [String: [NearbySpeaker]] = [:]
    private var generation = 0

    func start(onSignal: @escaping @Sendable (NearbySpeakerBrowserSignal) -> Void) {
        lock.lock()
        if !browsers.isEmpty {
            lock.unlock()
            return
        }
        generation += 1
        let token = generation
        lock.unlock()

        var started: [NWBrowser] = []
        for type in NearbySpeakerDiscovery.serviceTypes {
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: parameters)
            browser.stateUpdateHandler = { [weak self] state in
                guard self?.isCurrent(token) == true else { return }
                switch state {
                case .ready:
                    onSignal(.ready)
                case .failed:
                    onSignal(.failed)
                case .waiting(let error):
                    if case .dns(let code) = error, code == NearbySpeakerBrowserRules.deniedDNSCode {
                        onSignal(.denied)
                    }
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.publish(type: type, results: results, token: token, onSignal: onSignal)
            }
            browser.start(queue: queue)
            started.append(browser)
        }

        lock.lock()
        if generation == token {
            browsers = started
        } else {
            started.forEach { $0.cancel() }
        }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        generation += 1
        let current = browsers
        browsers = []
        names.removeAll()
        lock.unlock()
        current.forEach { $0.cancel() }
    }

    private func isCurrent(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    private func publish(
        type: String,
        results: Set<NWBrowser.Result>,
        token: Int,
        onSignal: @escaping @Sendable (NearbySpeakerBrowserSignal) -> Void
    ) {
        var found: [NearbySpeaker] = []
        for result in results {
            guard case .service(let name, let kind, let domain, _) = result.endpoint else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            found.append(NearbySpeaker(id: "\(trimmed)|\(kind)|\(domain)", name: trimmed))
        }
        lock.lock()
        guard generation == token else {
            lock.unlock()
            return
        }
        names[type] = found
        let merged = names.values.flatMap { $0 }
        lock.unlock()
        onSignal(.results(NearbySpeaker.normalize(merged)))
    }
}
