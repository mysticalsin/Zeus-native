import CoreFoundation
import Foundation

public enum StepZeroCodec {
    public static let format = "zeus.step-zero"
    public static let version = 1
    public static let maxBytes = 256 * 1024
    public static let countRange = 0...1_000_000

    public static func encode(_ report: StepZeroReport) -> Data? {
        guard report.summary == StepZeroSummary.combined([report]) else { return nil }
        guard let object = box(report) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func decode(_ data: Data) -> StepZeroReport? {
        guard data.count <= maxBytes else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any],
              Set(object.keys) == topKeys else { return nil }
        guard string(object["format"]) == format, int(object["version"]) == version else { return nil }
        guard let createdAt = int(object["createdAt"]),
              let system = jsonObject(object["system"]),
              let build = jsonObject(object["build"]),
              let sections = array(object["sections"]),
              let answers = array(object["answers"]),
              let restored = array(object["restored"]),
              let notPutBack = array(object["notPutBack"]),
              let grants = array(object["grantsAtStart"]),
              let leftOn = array(object["leftOn"]),
              let takenOff = array(object["takenOff"]),
              let summary = array(object["summary"]) else { return nil }
        guard Set(system.keys) == ["version", "build", "hardware"],
              Set(build.keys) == ["zeusVersion", "stamp", "signing", "hardenedRuntime"] else { return nil }
        guard let systemVersion = tag(.systemVersion, system["version"]),
              let systemBuild = tag(.systemBuild, system["build"]),
              let systemHardware = tag(.systemHardware, system["hardware"]),
              let zeusVersion = tag(.zeusVersion, build["zeusVersion"]),
              let buildStamp = tag(.buildStamp, build["stamp"]),
              let signing = code(build["signing"], StepZeroCatalogue.signingWords),
              let hardened = bool(build["hardenedRuntime"]),
              let decodedSections = sections.compactMap(section).nilIfShort(of: sections.count),
              let decodedAnswers = answers.compactMap(answer).nilIfShort(of: answers.count),
              let decodedRestored = restored.compactMap(restore).nilIfShort(of: restored.count),
              let decodedNotPutBack = notPutBack.compactMap({ code($0, StepZeroCatalogue.notPutBackWords) }).nilIfShort(of: notPutBack.count),
              let decodedGrants = grants.compactMap(grant).nilIfShort(of: grants.count),
              let decodedLeft = leftOn.compactMap({ code($0, StepZeroCatalogue.grantWords) }).nilIfShort(of: leftOn.count),
              let decodedTaken = takenOff.compactMap({ code($0, StepZeroCatalogue.grantWords) }).nilIfShort(of: takenOff.count),
              let decodedSummary = summary.compactMap(planSummary).nilIfShort(of: summary.count) else { return nil }
        guard Set(decodedSections.map(\.id.raw)).count == decodedSections.count,
              Set(decodedAnswers.map(\.id)).count == decodedAnswers.count else { return nil }
        let report = StepZeroReport(
            createdAt: createdAt,
            systemVersion: systemVersion,
            systemBuild: systemBuild,
            systemHardware: systemHardware,
            zeusVersion: zeusVersion,
            buildStamp: buildStamp,
            signing: signing,
            hardenedRuntime: hardened,
            sections: decodedSections,
            answers: decodedAnswers,
            restored: decodedRestored,
            notPutBack: decodedNotPutBack,
            grantsAtStart: decodedGrants,
            leftOn: decodedLeft,
            takenOff: decodedTaken,
            summary: decodedSummary
        )
        guard report.summary == StepZeroSummary.combined([report]) else { return nil }
        return report
    }
}

private let topKeys: Set<String> = [
    "format", "version", "createdAt", "system", "build", "sections", "answers",
    "restored", "notPutBack", "grantsAtStart", "leftOn", "takenOff", "summary",
]

private func box(_ report: StepZeroReport) -> [String: Any]? {
    guard StepZeroCatalogue.signingWords.contains(report.signing.raw),
          ProbeLexicon.alphabet.contains(report.signing.raw),
          let sections = report.sections.compactMap(boxSection).nilIfShort(of: report.sections.count),
          let answers = report.answers.compactMap(boxAnswer).nilIfShort(of: report.answers.count),
          let restored = report.restored.compactMap(boxRestore).nilIfShort(of: report.restored.count),
          let notPutBack = report.notPutBack.compactMap({ codeBox($0, StepZeroCatalogue.notPutBackWords) }).nilIfShort(of: report.notPutBack.count),
          let grants = report.grantsAtStart.compactMap(boxGrant).nilIfShort(of: report.grantsAtStart.count),
          let leftOn = report.leftOn.compactMap({ codeBox($0, StepZeroCatalogue.grantWords) }).nilIfShort(of: report.leftOn.count),
          let takenOff = report.takenOff.compactMap({ codeBox($0, StepZeroCatalogue.grantWords) }).nilIfShort(of: report.takenOff.count),
          let summary = report.summary.compactMap(boxSummary).nilIfShort(of: report.summary.count) else { return nil }
    return [
        "format": StepZeroCodec.format,
        "version": StepZeroCodec.version,
        "createdAt": report.createdAt,
        "system": [
            "version": tagBox(report.systemVersion),
            "build": tagBox(report.systemBuild),
            "hardware": tagBox(report.systemHardware),
        ],
        "build": [
            "zeusVersion": tagBox(report.zeusVersion),
            "stamp": tagBox(report.buildStamp),
            "signing": report.signing.raw,
            "hardenedRuntime": report.hardenedRuntime,
        ],
        "sections": sections,
        "answers": answers,
        "restored": restored,
        "notPutBack": notPutBack,
        "grantsAtStart": grants,
        "leftOn": leftOn,
        "takenOff": takenOff,
        "summary": summary,
    ]
}

private func tagBox(_ tag: ProbeTag) -> String {
    if let text = tag.text, ProbeTag.shape(tag.field, text) { return text }
    return "other"
}

private func boxSection(_ section: StepZeroSection) -> [String: Any]? {
    guard StepZeroCatalogue.sectionIDs.contains(section.id.raw),
          StepZeroCatalogue.sectionStates.contains(section.state.raw) else { return nil }
    return ["id": section.id.raw, "state": section.state.raw]
}

private func boxAnswer(_ answer: StepZeroAnswer) -> [String: Any]? {
    guard let question = StepZeroCatalogue.byID[answer.id],
          StepZeroCatalogue.resultWords.contains(answer.result.raw) else { return nil }
    let allowed = Dictionary(uniqueKeysWithValues: question.fields.map { ($0.id, $0.kind) })
    guard Set(answer.values.keys).isSubset(of: Set(allowed.keys)) else { return nil }
    var values: [String: Any] = [:]
    for (key, value) in answer.values {
        guard allowed[key] == kind(of: value), let boxed = boxValue(value) else { return nil }
        values[key] = boxed
    }
    return ["q": answer.id, "result": answer.result.raw, "values": values]
}

private func boxRestore(_ restore: StepZeroRestore) -> [String: Any]? {
    guard StepZeroCatalogue.restoreWhats.contains(restore.what.raw),
          StepZeroCatalogue.restoreOKs.contains(restore.ok.raw) else { return nil }
    return ["what": restore.what.raw, "ok": restore.ok.raw]
}

private func boxGrant(_ reading: StepZeroGrantReading) -> [String: Any]? {
    guard StepZeroCatalogue.grantWords.contains(reading.grant.raw),
          StepZeroCatalogue.grantStates.contains(reading.state.raw) else { return nil }
    if reading.grant.raw == "localNetwork" && reading.state.raw != "unknown" { return nil }
    return ["grant": reading.grant.raw, "state": reading.state.raw]
}

private func boxSummary(_ summary: PlanSummary) -> [String: Any]? {
    guard summary.reasons.allSatisfy({ ProbeLexicon.alphabet.contains($0.raw) }) else { return nil }
    return [
        "plan": summary.plan.rawValue,
        "word": summary.word.rawValue,
        "reasons": summary.reasons.map(\.raw),
    ]
}

private func boxValue(_ value: ProbeValue) -> Any? {
    switch value {
    case .flag(let flag):
        return flag
    case .count(let count), .milliseconds(let count):
        guard StepZeroCodec.countRange.contains(count) else { return nil }
        return count
    case .code(let code):
        guard ProbeLexicon.alphabet.contains(code.raw) else { return nil }
        return code.raw
    case .codes(let codes):
        guard codes.allSatisfy({ ProbeLexicon.alphabet.contains($0.raw) }) else { return nil }
        return codes.map(\.raw)
    }
}

private func kind(of value: ProbeValue) -> ProbeKind {
    switch value {
    case .flag: return .flag
    case .count: return .count
    case .milliseconds: return .milliseconds
    case .code: return .code
    case .codes: return .codes
    }
}

private func codeBox(_ code: ProbeCode, _ allowed: Set<String>) -> String? {
    guard allowed.contains(code.raw) else { return nil }
    return code.raw
}

private func section(_ any: Any) -> StepZeroSection? {
    guard let object = jsonObject(any), Set(object.keys) == ["id", "state"],
          let id = code(object["id"], StepZeroCatalogue.sectionIDs),
          let state = code(object["state"], StepZeroCatalogue.sectionStates) else { return nil }
    return StepZeroSection(id: id, state: state)
}

private func answer(_ any: Any) -> StepZeroAnswer? {
    guard let object = jsonObject(any), Set(object.keys) == ["q", "result", "values"],
          let id = string(object["q"]), let question = StepZeroCatalogue.byID[id],
          let result = code(object["result"], StepZeroCatalogue.resultWords),
          let values = jsonObject(object["values"]) else { return nil }
    let allowed = Dictionary(uniqueKeysWithValues: question.fields.map { ($0.id, $0.kind) })
    guard Set(values.keys).isSubset(of: Set(allowed.keys)) else { return nil }
    var decoded: [String: ProbeValue] = [:]
    for (key, raw) in values {
        guard let kind = allowed[key], let value = value(raw, kind) else { return nil }
        decoded[key] = value
    }
    return StepZeroAnswer(id: id, result: result, values: decoded)
}

private func restore(_ any: Any) -> StepZeroRestore? {
    guard let object = jsonObject(any), Set(object.keys) == ["what", "ok"],
          let what = code(object["what"], StepZeroCatalogue.restoreWhats),
          let ok = code(object["ok"], StepZeroCatalogue.restoreOKs) else { return nil }
    return StepZeroRestore(what: what, ok: ok)
}

private func grant(_ any: Any) -> StepZeroGrantReading? {
    guard let object = jsonObject(any), Set(object.keys) == ["grant", "state"],
          let name = code(object["grant"], StepZeroCatalogue.grantWords),
          let state = code(object["state"], StepZeroCatalogue.grantStates) else { return nil }
    if name.raw == "localNetwork" && state.raw != "unknown" { return nil }
    return StepZeroGrantReading(grant: name, state: state)
}

private func planSummary(_ any: Any) -> PlanSummary? {
    guard let object = jsonObject(any), Set(object.keys) == ["plan", "word", "reasons"],
          let planRaw = string(object["plan"]), let plan = StepZeroQuestion.Plan(rawValue: planRaw),
          let wordRaw = string(object["word"]), let word = PlanSummary.Word(rawValue: wordRaw),
          let reasons = array(object["reasons"]) else { return nil }
    guard let codes = reasons.compactMap({ code($0, ProbeLexicon.alphabet) }).nilIfShort(of: reasons.count) else { return nil }
    return PlanSummary(plan: plan, word: word, reasons: codes)
}

private func value(_ any: Any, _ kind: ProbeKind) -> ProbeValue? {
    switch kind {
    case .flag:
        guard let flag = bool(any) else { return nil }
        return .flag(flag)
    case .count:
        guard let count = bounded(any) else { return nil }
        return .count(count)
    case .milliseconds:
        guard let count = bounded(any) else { return nil }
        return .milliseconds(count)
    case .code:
        guard let code = code(any, ProbeLexicon.alphabet) else { return nil }
        return .code(code)
    case .codes:
        guard let items = array(any),
              let codes = items.compactMap({ code($0, ProbeLexicon.alphabet) }).nilIfShort(of: items.count) else { return nil }
        return .codes(codes)
    }
}

private func tag(_ field: ProbeTag.Field, _ any: Any?) -> ProbeTag? {
    guard let raw = string(any) else { return nil }
    if raw == "other" { return .withheld(field) }
    let accepted = ProbeTag.accept(field, raw)
    guard !accepted.withheld else { return nil }
    return accepted
}

private func code(_ any: Any?, _ allowed: Set<String>) -> ProbeCode? {
    guard let raw = string(any), allowed.contains(raw), ProbeLexicon.alphabet.contains(raw) else { return nil }
    return ProbeCode(alphabet: raw)
}

private func bounded(_ any: Any?) -> Int? {
    guard let value = int(any), StepZeroCodec.countRange.contains(value) else { return nil }
    return value
}

private func jsonObject(_ any: Any?) -> [String: Any]? {
    guard let any, cfType(any) == CFDictionaryGetTypeID() else { return nil }
    return any as? [String: Any]
}

private func array(_ any: Any?) -> [Any]? {
    guard let any, cfType(any) == CFArrayGetTypeID() else { return nil }
    return any as? [Any]
}

private func string(_ any: Any?) -> String? {
    guard let any, cfType(any) == CFStringGetTypeID() else { return nil }
    return any as? String
}

private func bool(_ any: Any?) -> Bool? {
    guard let number = any as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func int(_ any: Any?) -> Int? {
    guard let any, let object = any as? NSObject else { return nil }
    let type = CFGetTypeID(object)
    guard type == CFNumberGetTypeID(), type != CFBooleanGetTypeID() else { return nil }
    let number = object as! NSNumber
    let double = number.doubleValue
    guard double.rounded(.towardZero) == double, double <= Double(Int.max), double >= Double(Int.min) else { return nil }
    return Int(double)
}

private func cfType(_ any: Any) -> CFTypeID? {
    guard let object = any as? NSObject else { return nil }
    return CFGetTypeID(object)
}

private extension Array {
    func nilIfShort(of count: Int) -> [Element]? {
        self.count == count ? self : nil
    }
}
