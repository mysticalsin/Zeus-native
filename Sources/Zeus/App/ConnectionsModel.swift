import Foundation
import Observation

@MainActor
@Observable
final class ConnectionsModel {
    struct Connection: Identifiable, Equatable {
        enum Status: Equatable {
            case checking
            case found(version: String?)
            case missing
        }

        let name: String
        var path: String?
        var status: Status
        var id: String { name }
    }

    private(set) var connections: [Connection] = CLILocator.tools.map {
        Connection(name: $0.name, path: nil, status: .checking)
    }
    private var isRefreshing = false

    var foundCount: Int {
        connections.filter { if case .found = $0.status { true } else { false } }.count
    }

    var foundNames: [String] {
        connections.compactMap { if case .found = $0.status { $0.name } else { nil } }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: (String, String?, String?).self) { group in
            for tool in CLILocator.tools {
                group.addTask {
                    guard let path = CLILocator.locate(tool) else { return (tool.name, nil, nil) }
                    return (tool.name, path, await CLILocator.version(at: path))
                }
            }
            for await (name, path, version) in group {
                guard let index = connections.firstIndex(where: { $0.name == name }) else { continue }
                connections[index].path = path
                connections[index].status = path == nil ? .missing : .found(version: version)
            }
        }
    }
}
