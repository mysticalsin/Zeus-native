import Foundation

/// `todo.connection` as one JSON value. A blob that does not decode is kept; it is not treated as
/// "nothing was stored".
public enum TodoConnectionBlob {
    public enum Load: Equatable {
        case absent
        case connected(BrainConnection)
        case corrupt(Data)
    }

    public static func load(_ data: Data?) -> Load {
        guard let data, !data.isEmpty else { return .absent }
        if let connection = try? JSONDecoder().decode(BrainConnection.self, from: data) {
            return .connected(connection)
        }
        return .corrupt(data)
    }

    public static func encode(_ connection: BrainConnection) throws -> Data {
        try JSONEncoder().encode(connection)
    }

    /// `nil` means the person disconnected. A thrown error means the previous bytes must stay.
    public static func persisted(existing: Data?, connection: BrainConnection?) throws -> Data? {
        _ = existing
        guard let connection else { return nil }
        return try encode(connection)
    }
}
