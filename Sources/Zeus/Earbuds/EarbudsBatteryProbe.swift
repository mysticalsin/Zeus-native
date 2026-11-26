/// Lowest layer of the earbuds battery read. The four key names live only here.
/// A return-type encoding and a value become closed codes. This file opens nothing,
/// keeps no device name, and does not read a part that is not an integer scalar.
public enum EarbudsBatteryProbe {
    /// Encodings longer than this are `other` and are not parsed.
    public static let maxEncodingBytes = 64

    public enum Key: String, Sendable, Equatable, CaseIterable {
        case left
        case right
        case budCase
        case single
    }

    /// Closed codes for a return-type encoding. Nil and empty are `none`.
    public enum ReturnType: Sendable, Equatable {
        case object
        case integer
        case other
        case none
    }

    /// Closed codes for the value that came back. Nil means the read was not attempted.
    public enum ValueClass: Sendable, Equatable {
        case number
        case string
        case null
        case other
        case raised
    }

    /// Closed codes for a number. Only 1 through 100 keep the value.
    public enum Level: Sendable, Equatable {
        case inRange(Int)
        case zero
        case n255
        case other

        public static func classify(_ raw: Int) -> Level {
            switch raw {
            case 1...100: return .inRange(raw)
            case 0: return .zero
            case 255: return .n255
            default: return .other
            }
        }
    }

    /// What the guarded read is allowed to see. The two closures run only when the gate says so.
    public struct Slot: Sendable {
        public var classResponds: Bool
        public var instanceResponds: Bool
        public var encoding: @Sendable () -> String?
        public var payload: @Sendable () -> Payload

        public init(
            classResponds: Bool,
            instanceResponds: Bool,
            encoding: @escaping @Sendable () -> String?,
            payload: @escaping @Sendable () -> Payload
        ) {
            self.classResponds = classResponds
            self.instanceResponds = instanceResponds
            self.encoding = encoding
            self.payload = payload
        }
    }

    public enum Payload: Sendable, Equatable {
        case raised
        case value(RawValue)
    }

    /// A value with no text kept. A number is the only case that holds a magnitude.
    public enum RawValue: Sendable, Equatable {
        case number(Int)
        case text
        case null
        case other
    }

    public struct PartAnswer: Sendable, Equatable {
        public var key: Key
        public var name: String
        public var classResponds: Bool
        public var instanceResponds: Bool
        public var answering: Bool
        public var returnType: ReturnType
        public var valueClass: ValueClass?
        public var level: Level?

        public init(
            key: Key,
            name: String,
            classResponds: Bool,
            instanceResponds: Bool,
            answering: Bool,
            returnType: ReturnType,
            valueClass: ValueClass?,
            level: Level?
        ) {
            self.key = key
            self.name = name
            self.classResponds = classResponds
            self.instanceResponds = instanceResponds
            self.answering = answering
            self.returnType = returnType
            self.valueClass = valueClass
            self.level = level
        }
    }

    public enum Read: Sendable, Equatable {
        case refused
        case parts([PartAnswer])
    }

    /// The selector name for one part. The four strings are not built anywhere else.
    public static func name(_ key: Key) -> String {
        switch key {
        case .left: return "batteryPercentLeft"
        case .right: return "batteryPercentRight"
        case .budCase: return "batteryPercentCase"
        case .single: return "batteryPercentSingle"
        }
    }

    /// Class-level check for the battery route. Left or single opens it. A refused grant asks nothing.
    public static func routeOpen(
        allowed: Bool,
        classResponds: @Sendable () -> (left: Bool, single: Bool)
    ) -> Bool {
        guard allowed else { return false }
        let flags = classResponds()
        return flags.left || flags.single
    }

    /// One pass over the four parts, in order. A refused grant does not ask for the slots.
    /// The encoding closure runs only when the class responds. The payload runs only for an integer scalar
    /// on an instance that responds. A second call starts empty.
    public static func read(allowed: Bool, slots: @Sendable () -> [Key: Slot]) -> Read {
        guard allowed else { return .refused }
        let provided = slots()
        return .parts(Key.allCases.map { answer(key: $0, slot: provided[$0]) })
    }

    /// The first type in an Objective-C encoding. Qualifiers are skipped. Integer scalars are
    /// `c i s l q` and their unsigned forms. `@` is an object, except a block `@?`, which is other.
    public static func returnType(encoding raw: String?) -> ReturnType {
        guard let raw, !raw.isEmpty else { return .none }
        if raw.utf8.count > maxEncodingBytes { return .other }
        if raw.contains("\0") || raw.contains("\n") || raw.contains("\r") { return .other }
        let scalars = Array(raw)
        var index = 0
        while index < scalars.count, qualifiers.contains(scalars[index]) {
            index += 1
        }
        guard index < scalars.count else { return .other }
        let head = scalars[index]
        if integerScalars.contains(head) { return .integer }
        if head == "@" {
            let next = index + 1
            if next < scalars.count, scalars[next] == "?" { return .other }
            return .object
        }
        return .other
    }

    private static let qualifiers: Set<Character> = ["r", "n", "N", "o", "O", "R", "V"]
    private static let integerScalars: Set<Character> = ["c", "i", "s", "l", "q", "C", "I", "S", "L", "Q"]

    private static func answer(key: Key, slot: Slot?) -> PartAnswer {
        let label = name(key)
        guard let slot, slot.classResponds else {
            return PartAnswer(
                key: key,
                name: label,
                classResponds: false,
                instanceResponds: false,
                answering: false,
                returnType: .none,
                valueClass: nil,
                level: nil
            )
        }
        let kind = returnType(encoding: slot.encoding())
        guard kind == .integer, slot.instanceResponds else {
            return PartAnswer(
                key: key,
                name: label,
                classResponds: true,
                instanceResponds: slot.instanceResponds,
                answering: false,
                returnType: kind,
                valueClass: nil,
                level: nil
            )
        }
        let classified = classify(slot.payload())
        return PartAnswer(
            key: key,
            name: label,
            classResponds: true,
            instanceResponds: true,
            answering: true,
            returnType: .integer,
            valueClass: classified.valueClass,
            level: classified.level
        )
    }

    private static func classify(_ payload: Payload) -> (valueClass: ValueClass, level: Level?) {
        switch payload {
        case .raised:
            return (.raised, nil)
        case .value(.number(let raw)):
            return (.number, Level.classify(raw))
        case .value(.text):
            return (.string, nil)
        case .value(.null):
            return (.null, nil)
        case .value(.other):
            return (.other, nil)
        }
    }
}
