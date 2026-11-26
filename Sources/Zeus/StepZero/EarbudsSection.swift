import Foundation

/// The step-zero earbuds section. Pure: it reads no radio, opens no manager, and writes no mode itself.
///
/// The caller feeds access, hand answers, and the seconds it waited. The order is the class property,
/// the classic list, the manager, the battery slots, the identity compare, the sleep timeline, the mode
/// write, and the grant watch last. A denied or restricted class property touches no device. A prompt
/// on the classic step leaves the manager unmeasured and unstarted. The loader files stay out of this file.
public enum EarbudsSection {
    /// The manager must report a state inside this many seconds, or the prompt answer is unmeasured.
    public static let managerLimitSeconds = 10
    /// Classic calls stay on the main thread. The watchdog records a hang at this limit.
    public static let classicLimitSeconds = 15
    /// One audio read or write. The restore is still asked once when this expires.
    public static let audioLimitSeconds = 2
    /// The grant watch after Start.
    public static let withdrawLimitSeconds = 60
    /// A change at or before this second is the early window.
    public static let withdrawEarlySeconds = 10
    /// Classic calls are asked on this thread and on no other.
    public static let classicThread = CallThread.main

    public enum CallThread: String, Sendable, Equatable {
        case main
    }

    /// What the class property can read. `denied` and `restricted` touch no device.
    public enum Access: String, Sendable, Equatable {
        case notAsked
        case allowed
        case denied
        case restricted
    }

    public enum ClassicOutcome: String, Sendable, Equatable {
        case quiet
        case prompted
        case refused
        case endedProcess
        case hung
    }

    public enum PromptAnswer: String, Sendable, Equatable {
        case appeared
        case stayedQuiet
    }

    public enum ManagerPrompts: String, Sendable, Equatable {
        case prompted
        case quiet
        case notMeasured
    }

    public enum Posture: String, Sendable, Equatable, CaseIterable {
        case bothOut
        case oneInCase
        case lidClosed
    }

    /// Slots only. The live key names stay in the battery probe file, which this section does not own.
    public enum KeySlot: String, Sendable, Equatable, CaseIterable {
        case left
        case right
        case budCase
        case single
    }

    /// Closed codes for a return-type encoding. Anything outside the table is `other`.
    public enum ReturnType: String, Sendable, Equatable {
        case object
        case integer
        case other
        case none

        public static func decode(_ raw: String) -> ReturnType {
            switch raw {
            case "object": return .object
            case "integer": return .integer
            case "none": return .none
            default: return .other
            }
        }
    }

    public enum ValueClass: String, Sendable, Equatable {
        case number
        case string
        case null
        case other
        case raised
    }

    public enum Level: String, Sendable, Equatable {
        case inRange
        case zero
        case n255
        case other
    }

    public enum DeviceClass: String, Sendable, Equatable {
        case headphones
        case headset
        case handsFree
        case other
    }

    public enum TimelineCode: String, Sendable, Equatable {
        case sleep
        case wake
        case connect
        case disconnect
    }

    public enum Window: String, Sendable, Equatable {
        case w10s
        case w60s
        case none
    }

    public struct BatteryFact: Sendable, Equatable {
        public var posture: Posture
        public var key: KeySlot
        public var responds: Bool
        public var returnType: ReturnType
        public var valueClass: ValueClass
        public var level: Level

        public init(
            posture: Posture,
            key: KeySlot,
            responds: Bool,
            returnType: ReturnType,
            valueClass: ValueClass,
            level: Level
        ) {
            self.posture = posture
            self.key = key
            self.responds = responds
            self.returnType = returnType
            self.valueClass = valueClass
            self.level = level
        }
    }

    public struct Slot: Sendable, Equatable {
        public var posture: Posture
        public var key: KeySlot

        public init(posture: Posture, key: KeySlot) {
            self.posture = posture
            self.key = key
        }
    }

    public static let batterySlots: [Slot] = {
        var slots: [Slot] = []
        for posture in Posture.allCases {
            for key in KeySlot.allCases {
                slots.append(Slot(posture: posture, key: key))
            }
        }
        return slots
    }()

    /// Off always agrees. Noise cancelling is bit 0, transparency is bit 1, adaptive is bit 2.
    /// A current mode of 2, 3 or 4 whose own bit is clear is not trusted.
    public static func maskAgrees(current: UInt32, mask: UInt32) -> Bool {
        switch current {
        case 1:
            return true
        case 2:
            return mask & 1 != 0
        case 3:
            return mask & 2 != 0
        case 4:
            return mask & 4 != 0
        default:
            return false
        }
    }

    /// Another allowed value to write, or nil when the mask leaves only the current value.
    /// Adaptive is never a choice.
    public static func replacement(current: UInt32, mask: UInt32) -> UInt32? {
        let candidates: [UInt32] = [1, 2, 3]
        for candidate in candidates where candidate != current {
            let allowed = candidate == 1
                || (candidate == 2 && mask & 1 != 0)
                || (candidate == 3 && mask & 2 != 0)
            if allowed { return candidate }
        }
        return nil
    }

    public enum Effect: Sendable, Equatable {
        case readAccess
        case classicList(CallThread)
        case startManager
        case abandonManager
        case readBattery(posture: Posture, key: KeySlot)
        case compareIdentity
        case readMode
        case writeMode(UInt32)
        case readModeBack
        case restoreMode(UInt32)
        case pollGrant
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case awaitAccess
        case gateClassic
        case awaitClassic
        case answerClassic
        case gateManager
        case awaitManager
        case answerManager
        case battery
        case awaitIdentity
        case timeline
        case gateMode
        case awaitMode
        case awaitWrite
        case awaitReadBack
        case awaitRestore
        case gateWithdraw
        case watchingWithdraw
        case done
    }

    public enum Event: Sendable, Equatable {
        case begin
        case access(Access)
        case continueAsked
        case classicReturned
        case classicFailed(ClassicOutcome)
        case prompt(PromptAnswer)
        case managerReported
        case waited(seconds: Int)
        case battery(
            posture: Posture,
            key: KeySlot,
            encoding: String,
            responds: Bool,
            valueClass: ValueClass,
            level: Level
        )
        case identity(uidHasAddress: Bool, namesEqual: Bool, deviceClass: DeviceClass)
        case timeline(TimelineCode)
        case timelineDone
        case mode(exists: Bool, byteSize: Int, current: UInt32, mask: UInt32, settable: Bool)
        case writeFinished(ok: Bool)
        case readBack(matched: Bool)
        case readBackFailed
        case restoreFinished
        case grant(Access)
        case appQuit
    }

    public struct State: Sendable, Equatable {
        public var phase: Phase
        public var accessBefore: Access?
        public var classicBeforeGrant: ClassicOutcome?
        public var managerPrompts: ManagerPrompts?
        public var battery: [BatteryFact]
        public var batteryCursor: Int
        public var uidHasAddress: Bool?
        public var namesEqual: Bool?
        public var deviceClass: DeviceClass?
        public var timeline: [TimelineCode]
        public var modeExists: Bool?
        public var modeSize: Int?
        public var modeCurrent: UInt32?
        public var modeMask: UInt32?
        public var maskAgrees: Bool?
        public var originalMode: UInt32?
        public var targetMode: UInt32?
        public var wrote: Bool
        public var restored: Bool
        public var restoreSent: Bool
        public var restoreTimedOut: Bool
        public var changedLive: Bool?
        public var changedWithin: Window?
        public var appQuit: Bool
        public var waited: Int

        public init() {
            phase = .idle
            accessBefore = nil
            classicBeforeGrant = nil
            managerPrompts = nil
            battery = []
            batteryCursor = 0
            uidHasAddress = nil
            namesEqual = nil
            deviceClass = nil
            timeline = []
            modeExists = nil
            modeSize = nil
            modeCurrent = nil
            modeMask = nil
            maskAgrees = nil
            originalMode = nil
            targetMode = nil
            wrote = false
            restored = false
            restoreSent = false
            restoreTimedOut = false
            changedLive = nil
            changedWithin = nil
            appQuit = false
            waited = 0
        }
    }

    public static func fresh() -> State { State() }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin:
            begin(&state, &effects)
        case .access(let access):
            accessRead(access, &state)
        case .continueAsked:
            continueAsked(&state, &effects)
        case .classicReturned:
            classicReturned(&state)
        case .classicFailed(let outcome):
            classicFailed(outcome, &state)
        case .prompt(let answer):
            prompt(answer, &state, &effects)
        case .managerReported:
            managerReported(&state)
        case .waited(let seconds):
            waited(seconds, &state, &effects)
        case .battery(let posture, let key, let encoding, let responds, let valueClass, let level):
            battery(
                posture: posture,
                key: key,
                encoding: encoding,
                responds: responds,
                valueClass: valueClass,
                level: level,
                &state,
                &effects
            )
        case .identity(let uidHasAddress, let namesEqual, let deviceClass):
            identity(uidHasAddress, namesEqual, deviceClass, &state)
        case .timeline(let code):
            if state.phase == .timeline { state.timeline.append(code) }
        case .timelineDone:
            if state.phase == .timeline { state.phase = .gateMode }
        case .mode(let exists, let byteSize, let current, let mask, let settable):
            mode(exists, byteSize, current, mask, settable, &state, &effects)
        case .writeFinished:
            writeFinished(&state, &effects)
        case .readBack:
            if state.phase == .awaitReadBack { beginRestore(&state, &effects) }
        case .readBackFailed:
            if state.phase == .awaitReadBack { beginRestore(&state, &effects) }
        case .restoreFinished:
            restoreFinished(&state)
        case .grant(let access):
            grant(access, &state)
        case .appQuit:
            if state.phase == .watchingWithdraw {
                state.appQuit = true
                state.phase = .done
            }
        }
        return (state, effects)
    }

    private static func begin(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .idle else { return }
        state.phase = .awaitAccess
        effects.append(.readAccess)
    }

    private static func accessRead(_ access: Access, _ state: inout State) {
        guard state.phase == .awaitAccess else { return }
        state.accessBefore = access
        switch access {
        case .denied, .restricted:
            state.phase = .done
        case .notAsked, .allowed:
            state.phase = .gateClassic
        }
    }

    private static func continueAsked(_ state: inout State, _ effects: inout [Effect]) {
        switch state.phase {
        case .gateClassic:
            state.phase = .awaitClassic
            state.waited = 0
            effects.append(.classicList(classicThread))
        case .gateManager:
            state.phase = .awaitManager
            state.waited = 0
            effects.append(.startManager)
        case .gateMode:
            state.phase = .awaitMode
            effects.append(.readMode)
        case .gateWithdraw:
            state.phase = .watchingWithdraw
            state.waited = 0
            effects.append(.pollGrant)
        default:
            break
        }
    }

    private static func classicReturned(_ state: inout State) {
        guard state.phase == .awaitClassic else { return }
        state.phase = .answerClassic
        state.waited = 0
    }

    private static func classicFailed(_ outcome: ClassicOutcome, _ state: inout State) {
        guard state.phase == .awaitClassic else { return }
        switch outcome {
        case .refused, .endedProcess, .hung:
            state.classicBeforeGrant = outcome
            state.phase = .done
        case .quiet, .prompted:
            break
        }
    }

    private static func prompt(_ answer: PromptAnswer, _ state: inout State, _ effects: inout [Effect]) {
        switch state.phase {
        case .answerClassic:
            switch answer {
            case .appeared:
                state.classicBeforeGrant = .prompted
                state.managerPrompts = .notMeasured
                state.phase = .done
            case .stayedQuiet:
                state.classicBeforeGrant = .quiet
                state.phase = .gateManager
            }
        case .answerManager:
            switch answer {
            case .appeared:
                state.managerPrompts = .prompted
            case .stayedQuiet:
                state.managerPrompts = .quiet
            }
            effects.append(.abandonManager)
            enterBattery(&state, &effects)
        default:
            break
        }
    }

    private static func managerReported(_ state: inout State) {
        guard state.phase == .awaitManager else { return }
        state.phase = .answerManager
        state.waited = 0
    }

    private static func waited(_ seconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard seconds > 0 else { return }
        switch state.phase {
        case .awaitClassic, .awaitManager, .awaitWrite, .awaitReadBack, .awaitRestore, .watchingWithdraw:
            state.waited += seconds
            applyClock(&state, &effects)
        default:
            break
        }
    }

    private static func applyClock(_ state: inout State, _ effects: inout [Effect]) {
        switch state.phase {
        case .awaitClassic:
            if state.waited >= classicLimitSeconds {
                state.classicBeforeGrant = .hung
                state.phase = .done
            }
        case .awaitManager:
            if state.waited >= managerLimitSeconds {
                state.managerPrompts = .notMeasured
                effects.append(.abandonManager)
                enterBattery(&state, &effects)
            }
        case .awaitWrite, .awaitReadBack:
            if state.waited >= audioLimitSeconds {
                beginRestore(&state, &effects)
            }
        case .awaitRestore:
            if state.waited >= audioLimitSeconds {
                state.restoreTimedOut = true
                state.phase = .gateWithdraw
            }
        case .watchingWithdraw:
            if state.waited >= withdrawLimitSeconds, state.changedLive != true {
                state.changedLive = false
                state.changedWithin = Window.none
                state.phase = .done
            }
        default:
            break
        }
    }

    private static func enterBattery(_ state: inout State, _ effects: inout [Effect]) {
        state.phase = .battery
        state.batteryCursor = 0
        state.waited = 0
        emitBattery(&state, &effects)
    }

    private static func emitBattery(_ state: inout State, _ effects: inout [Effect]) {
        if state.batteryCursor < batterySlots.count {
            let slot = batterySlots[state.batteryCursor]
            effects.append(.readBattery(posture: slot.posture, key: slot.key))
        } else {
            state.phase = .awaitIdentity
            effects.append(.compareIdentity)
        }
    }

    private static func battery(
        posture: Posture,
        key: KeySlot,
        encoding: String,
        responds: Bool,
        valueClass: ValueClass,
        level: Level,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .battery, state.batteryCursor < batterySlots.count else { return }
        let expected = batterySlots[state.batteryCursor]
        guard posture == expected.posture, key == expected.key else { return }
        state.battery.append(
            BatteryFact(
                posture: posture,
                key: key,
                responds: responds,
                returnType: ReturnType.decode(encoding),
                valueClass: valueClass,
                level: level
            )
        )
        state.batteryCursor += 1
        emitBattery(&state, &effects)
    }

    private static func identity(
        _ uidHasAddress: Bool,
        _ namesEqual: Bool,
        _ deviceClass: DeviceClass,
        _ state: inout State
    ) {
        guard state.phase == .awaitIdentity else { return }
        state.uidHasAddress = uidHasAddress
        state.namesEqual = namesEqual
        state.deviceClass = deviceClass
        state.phase = .timeline
    }

    private static func mode(
        _ exists: Bool,
        _ byteSize: Int,
        _ current: UInt32,
        _ mask: UInt32,
        _ settable: Bool,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .awaitMode else { return }
        let agrees = maskAgrees(current: current, mask: mask)
        state.modeExists = exists
        state.modeSize = byteSize
        state.modeCurrent = current
        state.modeMask = mask
        state.maskAgrees = agrees
        state.originalMode = current
        let canWrite = exists && byteSize == 4 && settable && agrees
        guard canWrite, let next = replacement(current: current, mask: mask) else {
            state.phase = .gateWithdraw
            return
        }
        state.targetMode = next
        state.wrote = true
        state.phase = .awaitWrite
        state.waited = 0
        effects.append(.writeMode(next))
    }

    private static func writeFinished(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitWrite else { return }
        state.phase = .awaitReadBack
        state.waited = 0
        effects.append(.readModeBack)
    }

    private static func beginRestore(_ state: inout State, _ effects: inout [Effect]) {
        guard state.restoreSent == false, let original = state.originalMode else {
            state.phase = .gateWithdraw
            return
        }
        state.restoreSent = true
        state.phase = .awaitRestore
        state.waited = 0
        effects.append(.restoreMode(original))
    }

    private static func restoreFinished(_ state: inout State) {
        guard state.phase == .awaitRestore else { return }
        state.restored = true
        state.phase = .gateWithdraw
        state.waited = 0
    }

    private static func grant(_ access: Access, _ state: inout State) {
        guard state.phase == .watchingWithdraw, access != .allowed else { return }
        state.changedLive = true
        state.changedWithin = state.waited <= withdrawEarlySeconds ? .w10s : .w60s
        state.phase = .done
    }
}
