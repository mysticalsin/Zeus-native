import CryptoKit
import Foundation
import ZeusCore

/// `zeus license ...`: check a key against this Mac without touching the app's Keychain.
/// Stateless on purpose: the app owns the stored key, so the CLI never writes one.
enum LicenseCommand {
    static let usage = """
    zeus license verify <key>                  Check a key offline on this Mac.
    zeus license activate <key> --server URL   Check it, then claim a seat on a license server.
    zeus license deactivate <key> --server URL Free this Mac's seat.
    zeus license device                        Print this Mac's device id.
    A key can also come from stdin with "-" so it stays out of shell history.
    """

    static func run(_ args: [String]) async -> Int32 {
        var rest = args
        var server: URL?
        if let index = rest.firstIndex(of: "--server"), index + 1 < rest.count {
            server = URL(string: rest[index + 1])
            rest.removeSubrange(index...(index + 1))
        }
        guard let sub = rest.first else { print(usage); return 0 }
        let device = LicenseKeys.thisMacDeviceID()
        if sub == "device" { print(device); return 0 }
        guard rest.count >= 2 else { return fail("zeus license \(sub): give a key, or - to read it from stdin.\n\n\(usage)", 2) }
        var key = rest[1]
        if key == "-" { key = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "" }
        key = key.filter { !$0.isWhitespace }
        #if DEBUG
        let evaluator = LicenseEvaluator(publicKeys: LicenseKeys.trusted(debug: true), deviceID: device)
        #else
        let evaluator = LicenseEvaluator(publicKeys: LicenseKeys.trusted(debug: false), deviceID: device)
        #endif

        let payload: LicensePayload
        switch License.verify(key, publicKeys: evaluator.publicKeys, deviceID: device) {
        case .success(let p): payload = p
        case .failure(let error): return fail("Not valid: \(error.message)", 1)
        }

        switch sub {
        case "verify":
            print(describe(evaluator.evaluate(.init(key: key, trialStart: Date())), device: device))
            return 0
        case "activate":
            guard let server else { return fail("zeus license activate needs --server URL", 2) }
            let client = LicenseServerClient(base: server)
            switch await client.activate(key: key, device: device, name: Host.current().localizedName ?? "Mac") {
            case .failure(let error): return fail("Activation refused: \(error.message)", 1)
            case .success(let token):
                guard case .success(let proof) = evaluator.checkActivation(token, licenseID: payload.id) else {
                    return fail("The server's activation proof did not verify.", 1)
                }
                let revocations: String? = if case .success(let list) = await client.revocations() { list } else { nil }
                let status = evaluator.evaluate(.init(key: key, activation: token, revocations: revocations, trialStart: Date()))
                print(describe(status, device: device))
                print("Seat: Mac \(proof.seat) of \(proof.seats) (activation proof verified)")
                return status.isLicensed ? 0 : 1
            }
        case "deactivate":
            guard let server else { return fail("zeus license deactivate needs --server URL", 2) }
            switch await LicenseServerClient(base: server).deactivate(key: key, device: device) {
            case .success: print("Seat freed for \(payload.id) on \(device)"); return 0
            case .failure(let error): return fail("Deactivate failed: \(error.message)", 1)
            }
        default:
            return fail("zeus license: unknown command \(sub)\n\n\(usage)", 2)
        }
    }

    static func describe(_ status: LicenseStatus, device: String) -> String {
        switch status {
        case .licensed(let p, let left):
            let term = left.map { "\($0) days left" } ?? "never expires"
            return "Licensed: ZEUS \(p.kind.title) \(p.id) to \(p.name.map { "\($0) <\(p.email)>" } ?? p.email), \(p.seatCount) seat(s), \(term). Mac \(device)"
        case .expired(let p): return "Expired: \(p.id)"
        case .revoked(let p): return "Turned off: \(p.id)"
        case .trial(let left): return "Trial: \(left) days left"
        case .trialEnded: return "Trial ended"
        }
    }

    static func fail(_ message: String, _ code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return code
    }
}
