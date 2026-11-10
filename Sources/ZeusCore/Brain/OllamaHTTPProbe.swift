import Foundation

/// Quick check that Ollama's HTTP server is up and has a model loaded (R24 speed).
public enum OllamaHTTPProbe {
    public static let defaultPort = 11434
    public static let timeoutSeconds: TimeInterval = 0.1

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// True when `/api/ps` lists at least one loaded model. An installed model that is not loaded
    /// is treated as down: pulling it into memory is too slow for a voice turn.
    public static func isReachable(port: Int = defaultPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/ps") else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            return hasLoadedModel(data)
        } catch {
            return false
        }
    }

    public static func hasLoadedModel(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [Any] else { return false }
        return !models.isEmpty
    }
}
