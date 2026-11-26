/// Lowest layer of the listening-mode device check. The two selectors live only here.
/// A read asks whether the property exists, asks its size, and then reads four bytes.
/// A write asks those same existence and size checks, asks whether the property is settable,
/// and sends one four-byte write. This file opens nothing, keeps no device name, and installs no listener.
public enum ListeningModeDevice {
    /// The only two selectors. Mode is written. The mask is read.
    public enum Selector: UInt32, Sendable, Equatable, CaseIterable {
        case mode = 0x6c73_746d
        case mask = 0x6c73_6d73
    }

    public static let modeSelector = Selector.mode.rawValue
    public static let maskSelector = Selector.mask.rawValue

    /// Global scope, main element, four bytes. A size other than four is not used.
    public static let scopeGlobal: UInt32 = 0x676c_6f62
    public static let elementMain: UInt32 = 0
    public static let byteCount = 4

    public struct Address: Sendable, Equatable {
        public var selector: UInt32
        public var scope: UInt32
        public var element: UInt32

        public init(selector: UInt32, scope: UInt32, element: UInt32) {
            self.selector = selector
            self.scope = scope
            self.element = element
        }
    }

    public struct SizeAnswer: Sendable, Equatable {
        public var status: Int32
        public var bytes: Int

        public init(status: Int32, bytes: Int) {
            self.status = status
            self.bytes = bytes
        }
    }

    public struct FlagAnswer: Sendable, Equatable {
        public var status: Int32
        public var settable: Bool

        public init(status: Int32, settable: Bool) {
            self.status = status
            self.settable = settable
        }
    }

    public struct BytesAnswer: Sendable, Equatable {
        public var status: Int32
        public var bytes: [UInt8]

        public init(status: Int32, bytes: [UInt8]) {
            self.status = status
            self.bytes = bytes
        }
    }

    /// What a read is allowed to ask. The later closures run only after the earlier check passes.
    public struct ReadGate: Sendable {
        public var hasProperty: @Sendable (Address) -> Bool
        public var dataSize: @Sendable (Address) -> SizeAnswer
        public var readBytes: @Sendable (Address) -> BytesAnswer

        public init(
            hasProperty: @escaping @Sendable (Address) -> Bool,
            dataSize: @escaping @Sendable (Address) -> SizeAnswer,
            readBytes: @escaping @Sendable (Address) -> BytesAnswer
        ) {
            self.hasProperty = hasProperty
            self.dataSize = dataSize
            self.readBytes = readBytes
        }
    }

    /// What a write is allowed to ask. `writeBytes` runs once, and only after every check passes.
    public struct WriteGate: Sendable {
        public var isDefault: @Sendable () -> Bool
        public var transportBluetooth: @Sendable () -> Bool
        public var hasProperty: @Sendable (Address) -> Bool
        public var dataSize: @Sendable (Address) -> SizeAnswer
        public var isSettable: @Sendable (Address) -> FlagAnswer
        public var writeBytes: @Sendable (Address, [UInt8]) -> Int32

        public init(
            isDefault: @escaping @Sendable () -> Bool,
            transportBluetooth: @escaping @Sendable () -> Bool,
            hasProperty: @escaping @Sendable (Address) -> Bool,
            dataSize: @escaping @Sendable (Address) -> SizeAnswer,
            isSettable: @escaping @Sendable (Address) -> FlagAnswer,
            writeBytes: @escaping @Sendable (Address, [UInt8]) -> Int32
        ) {
            self.isDefault = isDefault
            self.transportBluetooth = transportBluetooth
            self.hasProperty = hasProperty
            self.dataSize = dataSize
            self.isSettable = isSettable
            self.writeBytes = writeBytes
        }
    }

    public enum ReadStop: Sendable, Equatable {
        case missingMode
        case modeSizeStatus
        case modeSize
        case modeReadStatus
        case modeBytes
        case missingMask
        case maskSizeStatus
        case maskSize
        case maskReadStatus
        case maskBytes
    }

    public enum Read: Sendable, Equatable {
        case unbound(ReadStop)
        case values(mode: UInt32, mask: UInt32)
    }

    public enum WriteStop: Sendable, Equatable {
        case notDefault
        case notBluetooth
        case missing
        case sizeStatus
        case size
        case settableStatus
        case notSettable
    }

    public enum Write: Sendable, Equatable {
        case notWritten(WriteStop)
        case wrote(Bool)
    }

    public static func address(for selector: Selector) -> Address {
        Address(selector: selector.rawValue, scope: scopeGlobal, element: elementMain)
    }

    /// Least-significant byte first. A count other than four is nil and the bytes are not kept.
    public static func integer(from bytes: [UInt8]) -> UInt32? {
        guard bytes.count == byteCount else { return nil }
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    /// Four bytes, least-significant byte first.
    public static func bytes(of code: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: code),
            UInt8(truncatingIfNeeded: code >> 8),
            UInt8(truncatingIfNeeded: code >> 16),
            UInt8(truncatingIfNeeded: code >> 24),
        ]
    }

    /// Mode, then mask. A failed check does not ask the next question. A second call starts empty.
    public static func read(_ gate: ReadGate) -> Read {
        let mode = address(for: .mode)
        guard gate.hasProperty(mode) else { return .unbound(.missingMode) }
        let modeSize = gate.dataSize(mode)
        guard modeSize.status == 0 else { return .unbound(.modeSizeStatus) }
        guard modeSize.bytes == byteCount else { return .unbound(.modeSize) }
        let modeBytes = gate.readBytes(mode)
        guard modeBytes.status == 0 else { return .unbound(.modeReadStatus) }
        guard let modeValue = integer(from: modeBytes.bytes) else { return .unbound(.modeBytes) }

        let mask = address(for: .mask)
        guard gate.hasProperty(mask) else { return .unbound(.missingMask) }
        let maskSize = gate.dataSize(mask)
        guard maskSize.status == 0 else { return .unbound(.maskSizeStatus) }
        guard maskSize.bytes == byteCount else { return .unbound(.maskSize) }
        let maskBytes = gate.readBytes(mask)
        guard maskBytes.status == 0 else { return .unbound(.maskReadStatus) }
        guard let maskValue = integer(from: maskBytes.bytes) else { return .unbound(.maskBytes) }
        return .values(mode: modeValue, mask: maskValue)
    }

    /// One write of the mode selector. A device that is not the default, or is not Bluetooth,
    /// is not asked about the property. A failed check does not write. A failed write is not repeated.
    public static func write(_ code: UInt32, gate: WriteGate) -> Write {
        guard gate.isDefault() else { return .notWritten(.notDefault) }
        guard gate.transportBluetooth() else { return .notWritten(.notBluetooth) }
        let mode = address(for: .mode)
        guard gate.hasProperty(mode) else { return .notWritten(.missing) }
        let size = gate.dataSize(mode)
        guard size.status == 0 else { return .notWritten(.sizeStatus) }
        guard size.bytes == byteCount else { return .notWritten(.size) }
        let flag = gate.isSettable(mode)
        guard flag.status == 0 else { return .notWritten(.settableStatus) }
        guard flag.settable else { return .notWritten(.notSettable) }
        let status = gate.writeBytes(mode, bytes(of: code))
        return .wrote(status == 0)
    }
}
