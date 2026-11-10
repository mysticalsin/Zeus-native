import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

@Suite("Any LLM endpoint safety")
struct AnyLLMEndpointSafetyTests {
    @Test func credentialBearingURLDraftsAreNeverSerializedToPreferences() throws {
        for address in ["https://synthetic-user:synthetic-password@example.invalid/v1",
                        "synthetic-user:synthetic-password@example.invalid/v1", "https://synthetic-user:synthetic-password@"] {
            let draft = AnyLLMConfig(baseURL: address, model: "gpt-5-mini")
            let stored = draft.configurationForPreferences
            #expect(stored.baseURL.isEmpty)
            #expect(draft.baseURL == address, "The invalid visible draft must remain available to correct")
            #expect(!String(decoding: try JSONEncoder().encode(stored), as: UTF8.self).contains("synthetic-password"))
        }
        let safe = AnyLLMConfig(baseURL: "https://example.invalid/v1", model: "gpt-5-mini")
        #expect(safe.configurationForPreferences == safe)
    }

    @Test func remoteCleartextAndEmbeddedCredentialsNeverProduceRequests() {
        for address in ["http://api.example.invalid/v1", "http://10.0.0.5/v1",
                        "http://localhost.example.invalid/v1", "http://localhost@api.example.invalid/v1",
                        "https://user:password@api.example.invalid/v1"] {
            let config = AnyLLMConfig(baseURL: address, model: "gpt-5-mini")
            #expect(config.request(prompt: "Synthetic private prompt", key: "synthetic-key") == nil)
            #expect(config.streamingRequest(prompt: "Synthetic private prompt", key: "synthetic-key") == nil)
        }
    }

    @Test func secureRemoteAndExactLoopbackRequestsRemainAvailable() throws {
        for address in ["https://api.example.invalid/v1", "http://localhost:11434/v1",
                        "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1"] {
            let config = AnyLLMConfig(baseURL: address, model: "gpt-5-mini")
            let request = try #require(config.request(prompt: "Synthetic prompt", key: "synthetic-key"))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
            #expect(config.streamingRequest(prompt: "Synthetic prompt", key: nil) != nil)
        }
    }

    @Test func transportRejectsUnsafeDirectRequestsBeforeDispatch() async {
        for address in ["http://remote.example.invalid/v1/models", "https://user:password@example.invalid/v1/models"] {
            do {
                _ = try await AnyLLMHTTPTransport.data(for: URLRequest(url: URL(string: address)!))
                Issue.record("Unsafe endpoint was dispatched")
            } catch {
                #expect((error as? URLError)?.code == .unsupportedURL)
            }
        }
    }

    @Test func editsKeysDisconnectAndRejectedValidationRevokeApproval() throws {
        var state = AnyLLMEndpointValidation()
        let firstAttempt = state.begin()
        let first = try #require(firstAttempt)
        #expect(!state.isApproved)
        let duplicateAttempt = state.begin()
        #expect(duplicateAttempt == nil)
        let accepted = state.complete(.passed("Synthetic server"), generation: first)
        #expect(accepted)
        #expect(state.isApproved)
        state.invalidate()
        #expect(!state.isApproved)
        let late = state.complete(.passed("Late previous endpoint"), generation: first)
        #expect(!late)
        let secondAttempt = state.begin()
        let second = try #require(secondAttempt)
        state.invalidate(reason: "Remote cleartext refused")
        let rejected = state.complete(.passed("Late prior check"), generation: second)
        #expect(!rejected)
        #expect(state.state == .failed("Remote cleartext refused"))
        #expect(!state.isApproved)
    }

    @Test func staleResultsCannotCompleteOrDisableTheReplacementCheck() throws {
        var state = AnyLLMEndpointValidation()
        let firstAttempt = state.begin()
        let first = try #require(firstAttempt)
        state.invalidate()
        let secondAttempt = state.begin()
        let second = try #require(secondAttempt)
        let oldSuccess = state.complete(.passed("Old endpoint"), generation: first)
        #expect(!oldSuccess)
        #expect(state.state == .testing)
        let accepted = state.complete(.passed("Current endpoint"), generation: second)
        #expect(accepted)
        let oldFailure = state.complete(.failed("Old failure"), generation: first)
        #expect(!oldFailure)
        #expect(state.isApproved)
        let duplicate = state.complete(.failed("Duplicate completion"), generation: second)
        #expect(!duplicate)
        #expect(state.isApproved)
    }

    @Test func actualHTTPRedirectNeverReceivesPromptOrKeyAtItsDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-endpoint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let portFile = directory.appendingPathComponent("port")
        let destinationFile = directory.appendingPathComponent("destination-contacted")
        let stopFile = directory.appendingPathComponent("stop")
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        helper.arguments = ["-u", "-c", Self.redirectServer, portFile.path, destinationFile.path, stopFile.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        defer {
            // The disposable helper has its own five-second deadline. Swift Testing may launch
            // with SIGTERM masked, so cleanup never relies only on Process.terminate().
            try? Data().write(to: stopFile)
            helper.waitUntilExit()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: portFile.path), helper.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let port = try #require(try? String(contentsOf: portFile, encoding: .utf8))
        let config = AnyLLMConfig(baseURL: "http://127.0.0.1:\(port)", model: "gpt-5-mini")
        var request = try #require(config.request(prompt: "Synthetic private prompt", key: "synthetic-key"))
        request.timeoutInterval = 3
        let (_, response) = try await AnyLLMHTTPTransport.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 307)
        #expect(!FileManager.default.fileExists(atPath: destinationFile.path), "Redirect received the original prompt or credential")
    }

    private static let redirectServer = #"""
    import http.server, pathlib, sys, time
    port_file, destination_file, stop_file = map(pathlib.Path, sys.argv[1:])
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get('Content-Length', 0)))
            if self.path == '/destination':
                destination_file.write_text('contacted')
                self.send_response(200)
            else:
                self.send_response(307)
                self.send_header('Location', '/destination')
            self.send_header('Content-Length', '0')
            self.end_headers()
        def log_message(self, *args): pass
    server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
    server.timeout = 0.05
    port_file.write_text(str(server.server_port))
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and not stop_file.exists():
        server.handle_request()
    server.server_close()
    """#
}
