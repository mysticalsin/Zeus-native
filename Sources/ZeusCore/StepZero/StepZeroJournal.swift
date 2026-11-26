import CoreFoundation
import Foundation

public struct StepZeroJournal: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var part: String
        public var mark: String
    }

    public var steps: [Step]
    public var childPid: Int?
    public var owedRestore: Int?
    public var grantsAtStart: [StepZeroGrantReading]
    public var bootMark: String?
}

public struct StepZeroResume: Equatable, Sendable {
    public var endedProcess: [String]
    public var putBack: Int?
    public var nextPart: String?
    public var childPid: Int?
    public var bootMark: String?
    public var grantsAtStart: [StepZeroGrantReading]
}

public enum StepZeroJournalCodec {
    public static let version = 1
    public static let marks: Set<String> = ["started", "finished", "timedOut"]

    public static func encode(_ journal: StepZeroJournal) -> Data? {
        guard let object = box(journal) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func decode(_ data: Data) -> StepZeroJournal? {
        guard data.count <= StepZeroCodec.maxBytes else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any],
              Set(object.keys) == keys else { return nil }
        guard int(object["version"]) == version,
              let steps = array(object["steps"]),
              let grants = array(object["grantsAtStart"]) else { return nil }
        guard let decodedSteps = steps.compactMap(step).nilIfShort(of: steps.count),
              let decodedGrants = grants.compactMap(grant).nilIfShort(of: grants.count) else { return nil }
        let pid = optionalInt(object["childPid"], range: 1...1_000_000)
        if object["childPid"] is NSNull == false && pid == nil { return nil }
        let restore = optionalInt(object["owedRestore"], range: 1...4)
        if object["owedRestore"] is NSNull == false && restore == nil { return nil }
        guard let boot = bootMark(object["bootMark"]) else { return nil }
        return StepZeroJournal(
            steps: decodedSteps,
            childPid: pid,
            owedRestore: restore,
            grantsAtStart: decodedGrants,
            bootMark: boot
        )
    }
}

extension StepZeroJournal {
    public func resume() -> StepZeroResume {
        var last: [String: String] = [:]
        var order: [String] = []
        for step in steps {
            if last[step.part] == nil { order.append(step.part) }
            last[step.part] = step.mark
        }
        let ended = order.filter { last[$0] == "started" }
        return StepZeroResume(
            endedProcess: ended,
            putBack: owedRestore,
            nextPart: ended.first,
            childPid: childPid,
            bootMark: bootMark,
            grantsAtStart: grantsAtStart
        )
    }
}

private let keys: Set<String> = ["version", "steps", "childPid", "owedRestore", "grantsAtStart", "bootMark"]

private func box(_ journal: StepZeroJournal) -> [String: Any]? {
    guard journal.steps.allSatisfy({ StepZeroCatalogue.byID[$0.part] != nil && StepZeroJournalCodec.marks.contains($0.mark) }) else {
        return nil
    }
    if let pid = journal.childPid, !(1...1_000_000).contains(pid) { return nil }
    if let restore = journal.owedRestore, !(1...4).contains(restore) { return nil }
    if let boot = journal.bootMark, cleanBoot(boot) != boot { return nil }
    let grants = journal.grantsAtStart.compactMap { reading -> [String: Any]? in
        guard StepZeroCatalogue.grantWords.contains(reading.grant.raw),
              StepZeroCatalogue.grantStates.contains(reading.state.raw) else { return nil }
        if reading.grant.raw == "localNetwork" && reading.state.raw != "unknown" { return nil }
        return ["grant": reading.grant.raw, "state": reading.state.raw]
    }
    guard grants.count == journal.grantsAtStart.count else { return nil }
    return [
        "version": StepZeroJournalCodec.version,
        "steps": journal.steps.map { ["part": $0.part, "mark": $0.mark] },
        "childPid": journal.childPid ?? NSNull(),
        "owedRestore": journal.owedRestore ?? NSNull(),
        "grantsAtStart": grants,
        "bootMark": journal.bootMark ?? NSNull(),
    ]
}

private func step(_ any: Any) -> StepZeroJournal.Step? {
    guard let object = any as? [String: Any], Set(object.keys) == ["part", "mark"],
          let part = object["part"] as? String, StepZeroCatalogue.byID[part] != nil,
          let mark = object["mark"] as? String, StepZeroJournalCodec.marks.contains(mark) else { return nil }
    return StepZeroJournal.Step(part: part, mark: mark)
}

private func grant(_ any: Any) -> StepZeroGrantReading? {
    guard let object = any as? [String: Any], Set(object.keys) == ["grant", "state"],
          let name = object["grant"] as? String, StepZeroCatalogue.grantWords.contains(name),
          let state = object["state"] as? String, StepZeroCatalogue.grantStates.contains(state),
          ProbeLexicon.alphabet.contains(name), ProbeLexicon.alphabet.contains(state) else { return nil }
    if name == "localNetwork" && state != "unknown" { return nil }
    return StepZeroGrantReading(grant: ProbeCode(alphabet: name), state: ProbeCode(alphabet: state))
}

private func bootMark(_ any: Any?) -> String?? {
    if any is NSNull { return .some(nil) }
    guard let text = any as? String else { return nil }
    return .some(cleanBoot(text))
}

private func cleanBoot(_ text: String) -> String? {
    guard text.count == 16 else { return nil }
    let folded = text.lowercased()
    let hex = folded.unicodeScalars.allSatisfy { scalar in
        (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
    }
    return hex ? folded : nil
}

private func optionalInt(_ any: Any?, range: ClosedRange<Int>) -> Int? {
    if any is NSNull { return nil }
    guard let object = any as? NSObject else { return nil }
    let type = CFGetTypeID(object)
    guard type == CFNumberGetTypeID(), type != CFBooleanGetTypeID() else { return nil }
    let number = (object as! NSNumber).intValue
    return range.contains(number) ? number : nil
}

private func int(_ any: Any?) -> Int? {
    guard let object = any as? NSObject else { return nil }
    let type = CFGetTypeID(object)
    guard type == CFNumberGetTypeID(), type != CFBooleanGetTypeID() else { return nil }
    return (object as! NSNumber).intValue
}

private func array(_ any: Any?) -> [Any]? {
    any as? [Any]
}

private extension Array {
    func nilIfShort(of count: Int) -> [Element]? {
        self.count == count ? self : nil
    }
}
