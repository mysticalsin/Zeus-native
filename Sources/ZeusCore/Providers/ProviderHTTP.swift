import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProviderHTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String, headers: [String: String], body: Data?) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func urlRequest(timeout: TimeInterval) throws -> URLRequest {
        guard url.scheme?.lowercased() == "https" else { throw ProviderFailure.notHTTPS }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        return request
    }
}

public struct ProviderHTTPResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public enum ProviderStreamEvent: Sendable, Equatable {
    case status(Int)
    case chunk(Data)
}

public protocol ProviderHTTPTransport: Sendable {
    func send(_ request: ProviderHTTPRequest) async throws -> ProviderHTTPResponse
    func stream(_ request: ProviderHTTPRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}

/// HTTPS-only session. Timeouts are `ProviderHTTPBudget.requestTimeout` (8 s), not the existing 20 s or 45 s ceilings.
public final class URLSessionProviderTransport: ProviderHTTPTransport, @unchecked Sendable {
    public let protocolClasses: [AnyClass]
    public let timeout: TimeInterval
    public let log: ProviderLog

    public init(protocolClasses: [AnyClass] = [], timeout: TimeInterval = ProviderHTTPBudget.requestTimeout, log: ProviderLog = ProviderLog()) {
        self.protocolClasses = protocolClasses
        self.timeout = timeout
        self.log = log
    }

    public func send(_ request: ProviderHTTPRequest) async throws -> ProviderHTTPResponse {
        let urlRequest = try request.urlRequest(timeout: timeout)
        let session = makeSession(delegate: ProviderHTTPSessionDelegate())
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw ProviderFailure.invalidResponse }
            logSafe(request, status: http.statusCode)
            return ProviderHTTPResponse(status: http.statusCode, body: data)
        } catch let failure as ProviderFailure {
            throw failure
        } catch {
            let failure = ProviderFailure.wrap(error)
            logSafe(request, status: 0, failure: failure)
            throw failure
        }
    }

    public func stream(_ request: ProviderHTTPRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let urlRequest = try request.urlRequest(timeout: timeout)
                let bridge = StreamBridge(continuation: continuation, log: log, request: request)
                let session = makeSession(delegate: bridge)
                bridge.session = session
                let task = session.dataTask(with: urlRequest)
                bridge.task = task
                continuation.onTermination = { _ in task.cancel() }
                task.resume()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func makeSession(delegate: URLSessionDataDelegate?) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private func logSafe(_ request: ProviderHTTPRequest, status: Int, failure: ProviderFailure? = nil) {
        var line = "provider-http \(request.method) \(request.url.host ?? "-") \(request.url.path) status=\(status)"
        if let failure { line += " failure=\(failure.logName)" }
        log.record(line)
    }
}

private final class StreamBridge: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    let log: ProviderLog
    let request: ProviderHTTPRequest
    var session: URLSession?
    var task: URLSessionTask?
    private var status = 0

    init(continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation, log: ProviderLog, request: ProviderHTTPRequest) {
        self.continuation = continuation
        self.log = log
        self.request = request
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            status = http.statusCode
            continuation.yield(.status(http.statusCode))
            log.record("provider-http \(request.method) \(request.url.host ?? "-") \(request.url.path) status=\(http.statusCode)")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        continuation.yield(.chunk(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.finish(throwing: ProviderFailure.wrap(error))
        } else {
            continuation.finish()
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(ProviderHTTPRedirect.forwarded(request, from: self.request.url))
    }
}

/// `xi-api-key` and `X-Goog-Api-Key` are custom headers, so a redirect would replay them.
/// Both `send` and `stream` refuse every redirect, including one that stays on the same host.
enum ProviderHTTPRedirect {
    static func forwarded(_ proposed: URLRequest, from original: URL?) -> URLRequest? {
        guard proposed.url != nil, original != nil else { return nil }
        return nil
    }
}

final class ProviderHTTPSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(ProviderHTTPRedirect.forwarded(request, from: task.originalRequest?.url ?? response.url))
    }
}
