import Foundation

public enum StepZeroSummary {
    public static func combined(_ reports: [StepZeroReport]) -> [PlanSummary] {
        let pooled = pool(reports)
        return [
            systemSource(pooled),
            lockScreen(reports),
            earbuds(pooled),
            focus(pooled),
            sized(pooled, .soundOutput, ["O1", "O2", "O3", "O4"]),
            sized(pooled, .musicPosition, ["A2"]),
        ]
    }
}

private func pool(_ reports: [StepZeroReport]) -> StepZeroReport {
    var answers: [StepZeroAnswer] = []
    var seen: Set<String> = []
    for report in reports {
        for answer in report.answers where seen.insert(answer.id).inserted {
            answers.append(answer)
        }
    }
    return StepZeroReport(
        createdAt: reports.first?.createdAt ?? 0,
        systemVersion: reports.first?.systemVersion ?? .withheld(.systemVersion),
        systemBuild: reports.first?.systemBuild ?? .withheld(.systemBuild),
        systemHardware: reports.first?.systemHardware ?? .withheld(.systemHardware),
        zeusVersion: reports.first?.zeusVersion ?? .withheld(.zeusVersion),
        buildStamp: reports.first?.buildStamp ?? .withheld(.buildStamp),
        signing: reports.first?.signing ?? ProbeCode("adHoc"),
        hardenedRuntime: reports.first?.hardenedRuntime ?? false,
        sections: [],
        answers: answers,
        restored: [],
        notPutBack: [],
        grantsAtStart: [],
        leftOn: [],
        takenOff: [],
        summary: []
    )
}

private func systemSource(_ report: StepZeroReport) -> PlanSummary {
    let seen = flag(report, "P1", "p1.itemSeen")
    let owner = flag(report, "P1", "p1.ownerSaysPlaying")
    let word: PlanSummary.Word
    var reasons: [ProbeCode] = []
    if seen == true {
        word = .go
    } else if seen == false && owner == true {
        word = .stop
    } else {
        word = .open
        reasons.append(ProbeCode("unanswered"))
    }
    if result(report, "P6") == "no", code(report, "P6", "p6.precondition") == "stillPlaying" {
        reasons.append(ProbeCode("canaryOpen"))
    }
    return PlanSummary(plan: .systemSource, word: word, reasons: reasons)
}

private func lockScreen(_ reports: [StepZeroReport]) -> PlanSummary {
    if reports.isEmpty {
        return PlanSummary(plan: .lockScreen, word: .open, reasons: [ProbeCode("unanswered")])
    }
    var sawNo = false
    var sawSkip = false
    var sawMissing = false
    var shortCycles = false
    var has26 = false
    var has27 = false
    for report in reports {
        for id in ["L2", "L3", "L4"] {
            switch result(report, id) {
            case "no": sawNo = true
            case "skipped": sawSkip = true
            case "yes": break
            default: sawMissing = true
            }
        }
        if result(report, "L4") == "yes" {
            let cycles = count(report, "L4", "l4.cycles") ?? -1
            if cycles < 20 { shortCycles = true }
        }
        switch major(report.systemVersion.text) {
        case 26: has26 = true
        case 27: has27 = true
        default: break
        }
    }
    if sawNo {
        return PlanSummary(plan: .lockScreen, word: .stop, reasons: [])
    }
    var reasons: [ProbeCode] = []
    if sawSkip { reasons.append(ProbeCode("skipped")) }
    if sawMissing { reasons.append(ProbeCode("unanswered")) }
    if shortCycles { reasons.append(ProbeCode("cycles")) }
    if !(has26 && has27) { reasons.append(ProbeCode("secondMac")) }
    if reasons.isEmpty {
        return PlanSummary(plan: .lockScreen, word: .go, reasons: [])
    }
    return PlanSummary(plan: .lockScreen, word: .open, reasons: reasons)
}

private func earbuds(_ report: StepZeroReport) -> PlanSummary {
    let battery = route(report, "E2")
    let mode = route(report, "E5")
    if battery == .stop || mode == .stop {
        return PlanSummary(plan: .earbuds, word: .stop, reasons: [])
    }
    if battery == .go && mode == .go {
        return PlanSummary(plan: .earbuds, word: .go, reasons: [])
    }
    var reasons: [ProbeCode] = []
    if result(report, "E2") == "skipped" || result(report, "E5") == "skipped" {
        reasons.append(ProbeCode("skipped"))
    }
    if result(report, "E2") == nil || result(report, "E5") == nil {
        reasons.append(ProbeCode("unanswered"))
    }
    if reasons.isEmpty { reasons.append(ProbeCode("unanswered")) }
    return PlanSummary(plan: .earbuds, word: .open, reasons: reasons)
}

private func route(_ report: StepZeroReport, _ id: String) -> PlanSummary.Word {
    switch result(report, id) {
    case "no": return .stop
    case "yes": return .go
    default: return .open
    }
}

private func focus(_ report: StepZeroReport) -> PlanSummary {
    if result(report, "F2") == nil {
        return PlanSummary(plan: .focus, word: .open, reasons: [ProbeCode("unanswered")])
    }
    if result(report, "F2") == "skipped" {
        return PlanSummary(plan: .focus, word: .open, reasons: [ProbeCode("skipped")])
    }
    let seen = flag(report, "F2", "f2.changeSeen")
    let modeKey = flag(report, "F2", "f2.hasModeIdKey")
    let configKey = flag(report, "F2", "f2.idIsConfigKey")
    let timing = flag(report, "F2", "f2.withinASecond")
    if seen == false || modeKey == false || configKey == false {
        return PlanSummary(plan: .focus, word: .stop, reasons: [])
    }
    if seen == true && modeKey == true && configKey == true && timing == true {
        return PlanSummary(plan: .focus, word: .go, reasons: [])
    }
    if seen == true && modeKey == true && configKey == true && timing == false {
        return PlanSummary(plan: .focus, word: .open, reasons: [ProbeCode("slow")])
    }
    return PlanSummary(plan: .focus, word: .open, reasons: [ProbeCode("unanswered")])
}

private func sized(_ report: StepZeroReport, _ plan: StepZeroQuestion.Plan, _ ids: [String]) -> PlanSummary {
    if ids.contains(where: { result(report, $0) == "skipped" }) {
        return PlanSummary(plan: plan, word: .open, reasons: [ProbeCode("skipped")])
    }
    let answered: Set<String> = ["yes", "no", "notMeasured", "notTried", "endedProcess", "timedOut"]
    if ids.allSatisfy({ answered.contains(result(report, $0) ?? "") }) {
        return PlanSummary(plan: plan, word: .go, reasons: [])
    }
    return PlanSummary(plan: plan, word: .open, reasons: [ProbeCode("unanswered")])
}

private func result(_ report: StepZeroReport, _ id: String) -> String? {
    report.answers.first { $0.id == id }?.result.raw
}

private func flag(_ report: StepZeroReport, _ id: String, _ field: String) -> Bool? {
    guard let value = report.answers.first(where: { $0.id == id })?.values[field] else { return nil }
    if case .flag(let flag) = value { return flag }
    return nil
}

private func code(_ report: StepZeroReport, _ id: String, _ field: String) -> String? {
    guard let value = report.answers.first(where: { $0.id == id })?.values[field] else { return nil }
    if case .code(let code) = value { return code.raw }
    return nil
}

private func count(_ report: StepZeroReport, _ id: String, _ field: String) -> Int? {
    guard let value = report.answers.first(where: { $0.id == id })?.values[field] else { return nil }
    if case .count(let count) = value { return count }
    return nil
}

private func major(_ text: String?) -> Int? {
    guard let text, let head = text.split(separator: ".").first else { return nil }
    return Int(head)
}
