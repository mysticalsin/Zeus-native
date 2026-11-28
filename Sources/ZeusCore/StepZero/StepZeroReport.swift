import Foundation

public struct ProbeCode: Hashable, Sendable, Equatable {
    public let raw: String

    public init(_ literal: StaticString) {
        self.raw = String(cString: literal.utf8Start)
    }

    init(alphabet raw: String) {
        precondition(ProbeLexicon.alphabet.contains(raw))
        self.raw = raw
    }
}

public enum ProbeLexicon {
        public static let words: [String] = "A E F K L O P absent adHoc allowed automationMusic automationSpotify bluetooth browser canary canaryOpen children client cycles defaultOutput developerID done elected empty endedProcess fileEvent finished folderEvent fullDiskAccess go handsFree headphones headset homeUserTmp hung inPlace inRange integer listeningMode localIdentity localNetwork lockSpace n255 no noGrant none notAsked notMeasured notRun notRunning notTried nothingPlaying null number object off on open other partial pausedByOwner pausedByProbe pid playState player playerHistory poll position present prompted quiet raised registrations replaced secondMac sessionSet skipCount skipped slow started stillPlaying stop string system timedOut track unanswered unknown w10s w2s w30s w60s yes zero".split(separator: " ").map(String.init)

    public static let alphabet: Set<String> = Set(words)
}

public enum ProbeKind: String, Sendable, Equatable {
    case flag
    case count
    case milliseconds
    case code
    case codes
}

public enum ProbeValue: Sendable, Equatable {
    case flag(Bool)
    case count(Int)
    case milliseconds(Int)
    case code(ProbeCode)
    case codes([ProbeCode])
}

public struct ProbeTag: Equatable, Sendable {
    public enum Field: String, Sendable, Equatable, CaseIterable {
        case systemVersion
        case systemBuild
        case systemHardware
        case zeusVersion
        case buildStamp
    }

    public var field: Field
    public var text: String?
    public var withheld: Bool { text == nil }

    public static func withheld(_ field: Field) -> ProbeTag {
        ProbeTag(field: field, text: nil)
    }

    public static func accept(_ field: Field, _ raw: String) -> ProbeTag {
        guard shape(field, raw) else { return withheld(field) }
        return ProbeTag(field: field, text: raw)
    }

    static func shape(_ field: Field, _ raw: String) -> Bool {
        switch field {
        case .systemVersion:
            return raw.wholeMatch(of: /^[0-9]{1,2}(\.[0-9]{1,2}){0,2}$/) != nil
        case .zeusVersion:
            return raw.wholeMatch(of: /^[0-9]{1,3}(\.[0-9]{1,3}){0,2}$/) != nil
        case .systemBuild:
            return raw.wholeMatch(of: /^[0-9]{2}[A-Z][0-9]{1,4}[a-z]?$/) != nil
        case .systemHardware:
            return raw.wholeMatch(of: /^(MacBookPro|MacBookAir|Macmini|MacPro|iMacPro|VirtualMac|MacBook|iMac|Mac)[0-9]{1,2},[0-9]{1,2}$/) != nil
        case .buildStamp:
            return raw.wholeMatch(of: /^[0-9]{14}-[0-9]{1,7}$/) != nil
        }
    }
}

public struct ProbeField: Equatable, Sendable {
    public var id: String
    public var kind: ProbeKind
}

public struct StepZeroQuestion: Equatable, Sendable {
    public enum Plan: String, Sendable, Equatable, CaseIterable {
        case systemSource
        case lockScreen
        case earbuds
        case focus
        case soundOutput
        case musicPosition
    }

    public enum Who: String, Sendable, Equatable, CaseIterable {
        case auto
        case guided
        case owner
    }

    public enum Prompt: String, Sendable, Equatable, CaseIterable {
        case none
        case bluetooth
        case localNetwork
        case automation
    }

    public enum Need: String, Sendable, Equatable, CaseIterable {
        case none
        case earbuds
        case secondDisplay
        case phone
        case secondAccount
        case olderMac
        case wirelessSpeaker
        case customFocus
        case fullDisk
        case song
        case viewer
    }

    public var id: String
    public var plan: Plan
    public var who: Who
    public var prompt: Prompt
    public var stops: Bool
    public var needs: Need
    public var fields: [ProbeField]
}

public struct StepZeroAnswer: Equatable, Sendable {
    public var id: String
    public var result: ProbeCode
    public var values: [String: ProbeValue]
}

public struct StepZeroSection: Equatable, Sendable {
    public var id: ProbeCode
    public var state: ProbeCode
}

public struct StepZeroRestore: Equatable, Sendable {
    public var what: ProbeCode
    public var ok: ProbeCode
}

public struct StepZeroGrantReading: Equatable, Sendable {
    public var grant: ProbeCode
    public var state: ProbeCode
}

public struct PlanSummary: Equatable, Sendable {
    public enum Word: String, Sendable, Equatable, CaseIterable {
        case go
        case stop
        case `open`
    }

    public var plan: StepZeroQuestion.Plan
    public var word: Word
    public var reasons: [ProbeCode]
}

public struct StepZeroReport: Equatable, Sendable {
    public var createdAt: Int
    public var systemVersion: ProbeTag
    public var systemBuild: ProbeTag
    public var systemHardware: ProbeTag
    public var zeusVersion: ProbeTag
    public var buildStamp: ProbeTag
    public var signing: ProbeCode
    public var hardenedRuntime: Bool
    public var sections: [StepZeroSection]
    public var answers: [StepZeroAnswer]
    public var restored: [StepZeroRestore]
    public var notPutBack: [ProbeCode]
    public var grantsAtStart: [StepZeroGrantReading]
    public var leftOn: [ProbeCode]
    public var takenOff: [ProbeCode]
    public var summary: [PlanSummary]
}

public enum StepZeroCatalogue {
    public static let questions: [StepZeroQuestion] = makeQuestions()
    public static let byID: [String: StepZeroQuestion] = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })

    public static let resultWords: Set<String> = [
        "yes", "no", "notMeasured", "skipped", "notTried", "endedProcess", "timedOut",
    ]
    public static let sectionIDs: Set<String> = ["P", "L", "K", "E", "F", "O", "A"]
    public static let sectionStates: Set<String> = ["done", "partial", "skipped", "notRun"]
    public static let signingWords: Set<String> = ["developerID", "localIdentity", "adHoc"]
    public static let grantWords: Set<String> = [
        "bluetooth", "fullDiskAccess", "automationMusic", "automationSpotify", "localNetwork",
    ]
    public static let grantStates: Set<String> = ["on", "off", "unknown"]
    public static let restoreWhats: Set<String> = [
        "playState", "track", "position", "elected", "canary", "listeningMode",
        "defaultOutput", "lockSpace", "registrations", "children",
    ]
    public static let restoreOKs: Set<String> = ["yes", "no", "unknown"]
    public static let notPutBackWords: Set<String> = ["skipCount", "playerHistory"]
}

private func generatedFields() -> [String: [ProbeField]] {
    func grid(_ prefix: String, _ rows: [String], _ leaves: [(String, ProbeKind)]) -> [ProbeField] {
        rows.flatMap { row in leaves.map { ProbeField(id: "\(prefix).\(row).\($0.0)", kind: $0.1) } }
    }
    var e2: [ProbeField] = []
    for posture in ["out", "cased", "lid"] {
        for key in ["left", "right", "case", "single"] {
            let stem = "e2.\(posture).\(key)"
            e2 += [
                ProbeField(id: "\(stem).responds", kind: .flag),
                ProbeField(id: "\(stem).returnType", kind: .code),
                ProbeField(id: "\(stem).valueClass", kind: .code),
                ProbeField(id: "\(stem).level", kind: .code),
            ]
        }
    }
    e2.append(ProbeField(id: "e2.listPairedMs", kind: .milliseconds))
    var l7 = grid("l7", ["builtIn", "external1", "external2"], [("clockBandBottom", .count), ("signInBandTop", .count)])
    l7.append(ProbeField(id: "l7.signInOn", kind: .code))
    var l11 = [ProbeField(id: "l11.systemMediaControls", kind: .flag)]
    l11 += grid("l11", ["builtIn", "external1", "external2"], [("bandTop", .count), ("bandBottom", .count)])
    return [
        "p9": grid("p9", ["privateWindow", "browserCall", "inbound", "otherDevice"], [("seen", .flag), ("appClass", .code), ("hasTitle", .flag), ("playing", .flag)]),
        "l6": grid("l6", ["lock", "unlock", "switchOut", "switchBack", "saverStart", "saverStop", "displaySleep", "displayWake"], [("codes", .codes), ("ms", .milliseconds)]),
        "l7": l7,
        "l11": l11,
        "e2": e2,
    ]
}

private let questionRows = """
P1 systemSource auto none 1 none | p1.itemSeen:flag p1.fields:codes p1.ownerSaysPlaying:flag
P2 systemSource auto none 0 none | p2.plainSeen:flag p2.gate:code
P3 systemSource owner none 0 none | build.signing:code p1.itemSeen:flag
P4 systemSource auto none 0 none | p4.missing:codes p4.bundleIdCall:code p4.notifyInChild:flag p4.pollCpuMs:milliseconds
P5 systemSource auto none 0 none | p5.emptyEnvOK:flag p5.needs:code
P6 systemSource guided none 0 none | p6.precondition:code p6.seenByProbe:flag p6.msToSeen:milliseconds p6.clearedSeen:flag p6.sameAppAfter:flag p6.shownInSystem:flag p6.keysReturn:flag restored.elected:code restored.playState:code
P7 systemSource auto none 0 none | p7.electedClass:code p7.pause:flag p7.play:flag p7.seek:code p7.next:flag p7.previous:flag restored.playState:code restored.position:code restored.elected:code
P8 systemSource guided none 0 none | p8.msExitAfterInputClosed:milliseconds p8.orphanAfterKill:flag
P9 systemSource guided none 0 none | *p9
P10 systemSource owner none 0 olderMac | p10.interpreterImage:code
P11 systemSource guided none 0 none | p11.artFormats:codes p11.mimeKeyPresent:flag
L1 lockScreen auto none 0 none | l1.missing:codes l1.removalCandidate:code
L2 lockScreen guided none 1 none | l2.makeSpace:flag l2.attach:flag l2.show:flag l2.seenAboveLock:flag
L3 lockScreen guided none 1 none | l3.firstClickFired:flag l3.keyEventsReached:count l3.becameKey:flag
L4 lockScreen guided none 1 none | l4.cycles:count l4.callFailures:count l4.censusLeftover:count l4.strayClicks:count l4.desktopClicksOK:flag
L5 lockScreen guided none 0 none | l5.closeIsEnough:flag l5.leftoverSeen:flag
L6 lockScreen guided none 0 secondAccount | *l6
L7 lockScreen owner none 0 none | *l7
L8 lockScreen guided automation 0 none | l8.automation.music:code l8.automation.spotify:code l8.noticesWhileLocked:count l8.playpause:flag l8.playpauseBack:flag l8.nextTrack:flag l8.previousTrack:flag
L9 lockScreen owner none 0 none | l9.sharingNoneSet:flag l9.hiddenFromRecording:flag
L10 lockScreen owner none 0 none | l10.voiceOverReaches:flag l10.touchIDWorks:flag l10.passwordWorks:flag
L11 lockScreen owner none 0 none | *l11
L12 lockScreen guided none 0 none | l12.bootIDReads:flag l12.bootChangedAcrossRestart:flag l12.windowGoneAfterKill:flag l12.censusAfterRelaunch:count l12.forceQuitTried:flag l12.goneAfterForceQuit:flag
E1 earbuds guided bluetooth 0 earbuds | e1.accessBefore:code e1.classicBeforeGrant:code e1.managerPrompts:code e1.connectDelivered:flag e1.disconnectDelivered:flag
E2 earbuds guided bluetooth 1 earbuds | *e2
E3 earbuds guided none 0 earbuds | e3.changedLive:flag e3.changedWithin:code e3.appQuit:flag
E4 earbuds guided none 0 earbuds | e4.timeline:codes
E5 earbuds guided none 1 earbuds | e5.exists:flag e5.scope:code e5.size:count e5.mask:count e5.current:count e5.listenerFired:flag e5.writeTook:flag e5.msToReadBack:milliseconds restored.listeningMode:code
E6 earbuds auto bluetooth 0 earbuds | e6.uidHasAddress:flag e6.nameEqualsBluetoothName:flag e6.deviceClass:code
E7 earbuds owner none 0 olderMac |
F1 focus auto none 0 fullDisk | f1.assertionsExists:flag f1.configExists:flag f1.errno:count
F2 focus guided none 1 none | f2.changeSeen:flag f2.seenBy:code f2.changedWithin:code f2.withinASecond:flag f2.hasModeIdKey:flag f2.idIsConfigKey:flag f2.offShape:code f2.fileExistsWhileOff:flag
F3 focus guided none 0 phone | f3.schedule:flag f3.phone:flag
F4 focus auto none 0 customFocus | f4.modes:count f4.withName:count f4.withSymbol:count f4.symbolsResolve:count
F5 focus guided none 0 none | f5.write:code
F6 focus guided none 0 fullDisk | f6.errno:count f6.promptSeen:flag f6.listedInPane:flag
F7 focus guided none 0 fullDisk | f7.grantLive:flag f7.revokeLive:flag
F8 focus auto none 0 fullDisk | f8.selfCanRead:flag f8.childCanRead:code
F9 focus guided none 0 secondDisplay | f9.recordWhileNoFocus:flag f9.carriesModeId:flag
F10 focus owner none 0 olderMac |
O1 soundOutput guided none 0 wirelessSpeaker | o1.transports:codes o1.airpSeen:flag
O2 soundOutput auto localNetwork 0 wirelessSpeaker | o2.states:codes o2.waitingBeforeAnswer:flag o2.airplayCount:count o2.raopCount:count o2.raopHexPrefixCount:count o2.modelKey:flag o2.amKey:flag
O3 soundOutput auto none 0 earbuds | o3.msToReadBack:milliseconds o3.movedBack:flag restored.defaultOutput:code
O4 soundOutput owner none 0 viewer | o4.menuVisibleToViewer:flag
A2 musicPosition guided none 0 song | a2.play:flag a2.pause:flag a2.trackChange:flag a2.scrub:flag
"""

private func makeQuestions() -> [StepZeroQuestion] {
    let generated = generatedFields()
    return questionRows.split(separator: "\n").map { line in
        let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let head = parts[0].split(separator: " ")
        let body = parts.count > 1 ? StepZeroFieldBodyBox.trimmedBody(String(parts[1])) : ""
        let fields: [ProbeField]
        if body.isEmpty {
            fields = []
        } else if body.hasPrefix("*") {
            fields = generated[String(body.dropFirst())] ?? []
        } else {
            fields = body.split(separator: " ").map { token in
                let bits = token.split(separator: ":")
                return ProbeField(id: String(bits[0]), kind: ProbeKind(rawValue: String(bits[1]))!)
            }
        }
        return StepZeroQuestion(
            id: String(head[0]),
            plan: StepZeroQuestion.Plan(rawValue: String(head[1]))!,
            who: StepZeroQuestion.Who(rawValue: String(head[2]))!,
            prompt: StepZeroQuestion.Prompt(rawValue: String(head[3]))!,
            stops: head[4] == "1",
            needs: StepZeroQuestion.Need(rawValue: String(head[5]))!,
            fields: fields
        )
    }
}
