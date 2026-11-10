import Foundation
import ZeusCore

// zeus: talk to the running ZEUS app from the terminal (installed as `zeus`).
// Sends one ZeusCommand line over ZEUS's Unix socket and prints the reply.

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

if CommandLine.arguments.dropFirst().first == "memory-mcp" {
    exit(WikiExportMCPCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

if CommandLine.arguments.dropFirst().first == "insomnia-guard" {
    exit(InsomniaGuardCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

if CommandLine.arguments.dropFirst().first == "license" {
    exit(await LicenseCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

let invocation: ZeusCLIInvocation
do {
    invocation = try ZeusCLI.parse(Array(CommandLine.arguments.dropFirst()))
} catch let error as ZeusCLIError {
    fail("zeus: \(error.message)\n\n\(ZeusCLI.usage)", code: 2)
} catch {
    fail("zeus: \(error)", code: 2)
}

guard let command = invocation.command else {
    print(ZeusCLI.usage)
    exit(0)
}
guard let payload = try? JSONEncoder().encode(command) else { fail("zeus: could not encode the request", code: 1) }

let socket = ZeusPaths.socket.path
guard let data = UnixSocket.request(path: socket, payload: payload, expectReply: true, timeout: invocation.timeout),
      !data.isEmpty else {
    fail("zeus: ZEUS isn't answering on \(socket). Open ZEUS and try again.", code: 3)
}
guard let reply = try? JSONDecoder().decode(ZeusCommandReply.self, from: data) else {
    fail("zeus: ZEUS sent a reply this version can't read. Update the zeus CLI.", code: 1)
}
if !reply.ok, reply.text.contains("Allow command-line control") {
    if invocation.json { print(String(decoding: data, as: UTF8.self)) }
    fail("zeus: \(reply.text)", code: 1)
}
if invocation.json {
    print(String(decoding: data, as: UTF8.self))
} else {
    let text = ZeusCLI.render(reply, op: command.op)
    if !text.isEmpty { print(text) }
}
exit(reply.ok ? 0 : 1)
