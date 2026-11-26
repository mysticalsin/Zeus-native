import Foundation

/// The step-zero sound facts. Pure: it opens no device, starts no browser,
/// and keeps no name.
///
/// The caller feeds transport codes and announcements. A code outside the
/// table becomes `other`, and the characters are dropped. A RAOP name with
/// a 12 to 16 hex prefix is counted and dropped. A record key other than
/// `model` and `am` is ignored. The browser file, the output section, and
/// the output lint stay out of this file.
public enum StepZeroSoundFacts {
    /// Devices past this count are not read.
    public static let maxDevices = 32
    /// Announcements past this count are not read.
    public static let maxSightings = 128
    /// A record key longer than this is ignored. The value is never taken.
    public static let maxRecordKeyBytes = 64

    /// The AirPlay browse type. This file does not start a browse.
    public static let airplayType = "_airplay._tcp"
    /// The RAOP browse type. This file does not start a browse.
    public static let raopType = "_raop._tcp"
    /// The two types a later browse may use. There is no third.
    public static let declaredTypes = [airplayType, raopType]

    public enum Transport: Sendable, Equatable {
        case builtIn
        case wired
        case bluetooth
        case wirelessSpeaker
        case display
        case virtual
        case other
    }

    /// One device, already read by the caller. The code is mapped and dropped.
    public struct DeviceReading: Sendable, Equatable {
        public var code: String?
        public var connectedOutput: Bool

        public init(code: String?, connectedOutput: Bool) {
            self.code = code
            self.connectedOutput = connectedOutput
        }
    }

    /// One announcement. The name is counted and dropped. Key values are not accepted.
    public struct Announcement: Sendable, Equatable {
        public var type: String
        public var name: String
        public var keys: [String]

        public init(type: String, name: String, keys: [String]) {
            self.type = type
            self.name = name
            self.keys = keys
        }
    }

    /// Counts and closed answers. No name, key, or raw code is stored.
    public struct Tally: Sendable, Equatable {
        public var transports: [Transport]
        public var airpSeen: Bool
        public var bluetoothConnected: Bool
        public var airplayCount: Int
        public var raopCount: Int
        public var hexPrefixCount: Int
        public var modelKey: Bool
        public var amKey: Bool
        public var sightingsTaken: Int

        public init() {
            transports = []
            airpSeen = false
            bluetoothConnected = false
            airplayCount = 0
            raopCount = 0
            hexPrefixCount = 0
            modelKey = false
            amKey = false
            sightingsTaken = 0
        }
    }

    /// A code the table does not name becomes `other`. Nil and `0` are `other`.
    /// The characters are not returned.
    public static func transport(code: String?) -> Transport {
        switch code {
        case "bltn":
            return .builtIn
        case "usb ", "thun", "1394", "pci ", "eavb":
            return .wired
        case "blue", "blea":
            return .bluetooth
        case "airp":
            return .wirelessSpeaker
        case "hdmi", "dprt":
            return .display
        case "virt", "grup":
            return .virtual
        default:
            return .other
        }
    }

    /// Reads at most `maxDevices` devices and `maxSightings` announcements.
    /// A device past the cap does not change the tally. An announcement past
    /// the cap does not change a count or a key flag.
    public static func read(devices: [DeviceReading], announcements: [Announcement]) -> Tally {
        var tally = Tally()
        for device in devices {
            if tally.transports.count == maxDevices { break }
            let mapped = transport(code: device.code)
            tally.transports.append(mapped)
            if mapped == .wirelessSpeaker {
                tally.airpSeen = true
            }
            if mapped == .bluetooth, device.connectedOutput {
                tally.bluetoothConnected = true
            }
        }
        for row in announcements {
            if tally.sightingsTaken == maxSightings { break }
            tally.sightingsTaken += 1
            switch row.type {
            case airplayType:
                tally.airplayCount += 1
            case raopType:
                tally.raopCount += 1
                if hasRaopHexPrefix(row.name) {
                    tally.hexPrefixCount += 1
                }
            default:
                continue
            }
            noteKeys(row.keys, &tally)
        }
        return tally
    }

    /// Twelve to sixteen hex digits, then `@`. Any other shape is not the prefix.
    private static func hasRaopHexPrefix(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        var length = 0
        while length < scalars.count, isHex(scalars[length]) {
            length += 1
            if length > 16 { return false }
        }
        guard length >= 12, length < scalars.count, scalars[length] == "@" else { return false }
        return true
    }

    private static func isHex(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "0"..."9", "a"..."f", "A"..."F":
            return true
        default:
            return false
        }
    }

    private static func noteKeys(_ keys: [String], _ tally: inout Tally) {
        for key in keys {
            guard key.utf8.count <= maxRecordKeyBytes else { continue }
            if key == "model" {
                tally.modelKey = true
            } else if key == "am" {
                tally.amKey = true
            }
        }
    }
}
