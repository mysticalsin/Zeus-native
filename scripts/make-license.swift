// Dev tool: signs a ZEUS license with the dev key in ~/.zeus-dev (created on first run, never committed).
// swift scripts/make-license.swift --email you@example.com [--plan lifetime|pro] [--days 30] [--device <id>] [--public-key]
import CryptoKit
import Foundation

let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zeus-dev")
let keyFile = dir.appendingPathComponent("license-ed25519.key")
var args = CommandLine.arguments.dropFirst()
func value(_ flag: String) -> String? {
    guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else { return nil }
    return args[args.index(after: index)]
}

let signer: Curve25519.Signing.PrivateKey
if let text = try? String(contentsOf: keyFile, encoding: .utf8), let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
   let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
    signer = key
} else {
    signer = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try signer.rawRepresentation.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
    FileHandle.standardError.write(Data("Created a dev key in ~/.zeus-dev. Embed its public key (--public-key).\n".utf8))
}
if args.contains("--public-key") { print(signer.publicKey.rawRepresentation.base64EncodedString()); exit(0) }

guard let email = value("--email") else {
    FileHandle.standardError.write(Data("usage: make-license.sh --email you@example.com [--plan lifetime] [--days N] [--device ID]\n".utf8))
    exit(2)
}
let now = Int(Date().timeIntervalSince1970)
var payload: [String: Any] = ["id": "L-" + UUID().uuidString.prefix(8), "email": email, "plan": value("--plan") ?? "lifetime", "issued": now]
if let days = value("--days").flatMap(Int.init) { payload["expires"] = now + days * 86_400 }
if let device = value("--device") { payload["device"] = device }
let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
func url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
print(["ZEUS1", url(body), url(try signer.signature(for: body))].joined(separator: "."))
