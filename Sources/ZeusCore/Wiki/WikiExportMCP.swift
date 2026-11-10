import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public protocol WikiExportToolClient: Sendable {
    func exportTools() async throws -> [MCPToolInfo]
    func exportCall(_ name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult
}

public enum WikiExportReadback: Equatable, Sendable {
    case missing
    case verified(relativePath: String, bytes: Int)
}

/// Contract shared by the real native client and the bundled, narrowly scoped MCP server.
public enum WikiExportMCP {
    public static let serverName = "zeus-memory-export"
    public static let createTool = "zeus_memory_create_export"
    public static let inspectTool = "zeus_memory_inspect_export"

    public static func discover(_ client: any WikiExportToolClient) async throws {
        let tools = try await client.exportTools()
        let requirements: [(String, Set<String>)] = [(createTool, ["export_id", "markdown"]), (inspectTool, ["export_id"])]
        for (name, fields) in requirements {
            guard let tool = tools.first(where: { $0.name == name }), Set(tool.required) == fields,
                  Set(tool.properties) == fields else { throw WikiExportError.protocolMismatch }
        }
    }

    public static func create(_ draft: WikiExportDraft, client: any WikiExportToolClient) async throws {
        try Task.checkCancellation()
        let result = try await client.exportCall(createTool, arguments: [
            "export_id": .string(draft.id.uuidString.lowercased()), "markdown": .string(draft.markdown),
        ])
        let value = try response(result)
        guard value["state"]?.stringValue == "stored", value["export_id"]?.stringValue == draft.id.uuidString.lowercased() else {
            throw WikiExportError.invalidResponse
        }
    }

    /// Independent readback, including after a timeout. This method never creates or changes a note.
    public static func inspect(_ draft: WikiExportDraft, client: any WikiExportToolClient) async throws -> WikiExportReadback {
        try Task.checkCancellation()
        let result = try await client.exportCall(inspectTool, arguments: ["export_id": .string(draft.id.uuidString.lowercased())])
        let value = try response(result)
        guard value["export_id"]?.stringValue == draft.id.uuidString.lowercased() else { throw WikiExportError.invalidResponse }
        if value["state"]?.stringValue == "missing", value["markdown"] == nil { return .missing }
        guard value["state"]?.stringValue == "present", let markdown = value["markdown"]?.stringValue,
              value["relative_path"]?.stringValue == draft.destination.relativePath(exportID: draft.id) else {
            throw WikiExportError.invalidResponse
        }
        guard Data(markdown.utf8) == Data(draft.markdown.utf8) else { throw WikiExportError.conflict }
        return .verified(relativePath: draft.destination.relativePath(exportID: draft.id), bytes: markdown.utf8.count)
    }

    private static func response(_ result: MCPToolResult) throws -> JSONValue {
        guard result.imageCount == 0, let value = try? JSONDecoder().decode(JSONValue.self, from: Data(result.text.utf8)) else {
            throw WikiExportError.invalidResponse
        }
        if result.isError {
            if value["error"]?.stringValue == "conflict" { throw WikiExportError.conflict }
            throw WikiExportError.destination(value["message"]?.stringValue ?? "The export helper could not complete the request.")
        }
        return value
    }
}

/// Standard JSON-RPC/MCP, with no general vault reads, path arguments, overwrite, delete or network.
public struct WikiExportMCPServer {
    private let vault: WikiExportVault
    private var initialized = false
    private var ready = false

    public init(vault: WikiExportVault) { self.vault = vault }

    public mutating func handle(_ line: Data) -> Data? {
        guard let request = try? JSONDecoder().decode(JSONValue.self, from: line),
              request["jsonrpc"]?.stringValue == "2.0", let method = request["method"]?.stringValue else {
            return rpcError(id: .null, code: -32_700, message: "Invalid JSON-RPC request")
        }
        let id = request["id"]
        if method == "notifications/initialized", initialized { ready = true; return nil }
        guard let id else { return nil }
        if method == "initialize" {
            initialized = true
            return response(id: id, result: .object([
                "protocolVersion": .string(MCPCodec.protocolVersion),
                "serverInfo": .object(["name": .string(WikiExportMCP.serverName), "version": .string("1")]),
                "capabilities": .object(["tools": .object([:])]),
            ]))
        }
        if method == "ping" { return response(id: id, result: .object([:])) }
        guard ready else { return rpcError(id: id, code: -32_000, message: "Initialize the connection first") }
        if method == "tools/list" { return response(id: id, result: .object(["tools": .array(Self.tools)])) }
        guard method == "tools/call" else { return rpcError(id: id, code: -32_601, message: "Method not supported") }
        let params = request["params"]
        let tool = params?["name"]?.stringValue
        let arguments = params?["arguments"]
        guard case .object(let fields)? = arguments,
              let rawID = fields["export_id"]?.stringValue, let exportID = UUID(uuidString: rawID) else {
            return rpcError(id: id, code: -32_602, message: "An export UUID is required")
        }
        do {
            let payload: JSONValue
            switch tool {
            case WikiExportMCP.createTool:
                guard Set(fields.keys) == ["export_id", "markdown"], let markdown = fields["markdown"]?.stringValue else {
                    return rpcError(id: id, code: -32_602, message: "Only export_id and markdown are accepted")
                }
                try vault.create(exportID: exportID, markdown: markdown)
                payload = .object(["state": .string("stored"), "export_id": .string(exportID.uuidString.lowercased())])
            case WikiExportMCP.inspectTool:
                guard Set(fields.keys) == ["export_id"] else {
                    return rpcError(id: id, code: -32_602, message: "Only export_id is accepted")
                }
                if let markdown = try vault.inspect(exportID: exportID) {
                    payload = .object(["state": .string("present"), "export_id": .string(exportID.uuidString.lowercased()),
                                       "relative_path": .string(vault.inbox + "/" + WikiExportVault.fileName(exportID)),
                                       "markdown": .string(markdown)])
                } else {
                    payload = .object(["state": .string("missing"), "export_id": .string(exportID.uuidString.lowercased())])
                }
            default: return rpcError(id: id, code: -32_601, message: "Tool not supported")
            }
            return response(id: id, result: toolResult(payload, isError: false))
        } catch {
            let payload: JSONValue = .object([
                "error": .string((error as? WikiExportError) == .conflict ? "conflict" : "unavailable"),
                "message": .string(error.localizedDescription),
            ])
            return response(id: id, result: toolResult(payload, isError: true))
        }
    }

    private static let tools: [JSONValue] = [
        tool(WikiExportMCP.createTool, "Create one new Memory export; identical export-ID retries do not overwrite or duplicate it.",
             fields: ["export_id", "markdown"], readOnly: false),
        tool(WikiExportMCP.inspectTool, "Read back only the UUID-named export note to verify an export or resolve an uncertain result.",
             fields: ["export_id"], readOnly: true),
    ]

    private static func tool(_ name: String, _ description: String, fields: [String], readOnly: Bool) -> JSONValue {
        .object([
            "name": .string(name), "description": .string(description),
            "inputSchema": .object(["type": .string("object"), "additionalProperties": .bool(false),
                "properties": .object(Dictionary(uniqueKeysWithValues: fields.map { ($0, JSONValue.object(["type": .string("string")])) })),
                "required": .array(fields.map(JSONValue.string))]),
            "annotations": .object(["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(false),
                                     "idempotentHint": .bool(true), "openWorldHint": .bool(false)]),
        ])
    }

    private func toolResult(_ value: JSONValue, isError: Bool) -> JSONValue {
        .object(["content": .array([.object(["type": .string("text"), "text": .string(String(decoding: encoded(value), as: UTF8.self))])]),
                 "isError": .bool(isError)])
    }

    private func response(id: JSONValue, result: JSONValue) -> Data {
        encoded(.object(["jsonrpc": .string("2.0"), "id": id, "result": result])) + Data([0x0A])
    }

    private func rpcError(id: JSONValue, code: Int, message: String) -> Data {
        encoded(.object(["jsonrpc": .string("2.0"), "id": id,
                         "error": .object(["code": .number(Double(code)), "message": .string(message)])])) + Data([0x0A])
    }

    private func encoded(_ value: JSONValue) -> Data { (try? JSONEncoder().encode(value)) ?? Data("null".utf8) }
}

/// `zeus memory-mcp --vault PATH --inbox RELATIVE --identity DEVICE:INODE`.
/// Runs only when explicitly invoked; no implicit vault discovery or app-control socket.
public enum WikiExportMCPCommand {
    public static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count == 6, arguments[0] == "--vault", arguments[2] == "--inbox", arguments[4] == "--identity" else {
            FileHandle.standardError.write(Data("Expected --vault PATH --inbox RELATIVE --identity DEVICE:INODE\n".utf8))
            return 2
        }
        do {
            let vault = try WikiExportVault(root: URL(fileURLWithPath: arguments[1]), inbox: arguments[3], expectedIdentity: arguments[5])
            var server = WikiExportMCPServer(vault: vault)
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                // POSIX read returns currently available pipe bytes. Foundation's read(upToCount:)
                // may wait to fill its buffer, deadlocking an interactive initialize request.
                let count = read(STDIN_FILENO, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { return 1 }
                if count == 0 { break }
                pending.append(contentsOf: buffer.prefix(count))
                guard pending.count <= 4 * 1024 * 1024 else { return 2 }
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    if !line.isEmpty, let reply = server.handle(line) { try FileHandle.standardOutput.write(contentsOf: reply) }
                }
            }
            return pending.isEmpty ? 0 : 2
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return 1
        }
    }
}
