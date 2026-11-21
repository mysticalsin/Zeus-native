import Foundation

public enum PortalStep: Equatable, Sendable {
    case applied
    case refused
}

/// Drop conversion. Phases are idle, received, converting, done, and failed.
/// An event that the phase does not allow is refused and changes nothing.
public struct PortalDropFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case received(PortalAdmittedFile)
        case converting(PortalAdmittedFile)
        case done(PortalConversionOutput)
        case failed(PortalDropFailure)
    }

    public private(set) var phase: Phase

    public init(_ phase: Phase = .idle) { self.phase = phase }

    public mutating func receive(_ claim: Result<PortalFileClaim, PortalDropFailure>) -> PortalStep {
        guard phase == .idle else { return .refused }
        switch claim {
        case .failure(let error):
            phase = .failed(error)
        case .success(let claim):
            switch PortalFileGate.decide(claim) {
            case .failure(let error): phase = .failed(error)
            case .success(let admitted): phase = .received(admitted)
            }
        }
        return .applied
    }

    public mutating func begin() -> PortalStep {
        guard case .received(let file) = phase else { return .refused }
        phase = .converting(file)
        return .applied
    }

    public mutating func finish(_ result: Result<PortalConversionOutput, PortalDropFailure>) -> PortalStep {
        guard case .converting(let file) = phase else { return .refused }
        switch result {
        case .failure(let error):
            phase = .failed(error)
        case .success(let output):
            if output.bytes.isEmpty { phase = .failed(.invalidContents) }
            else if output.bytes.count > PortalLimits.maxConversionBytes { phase = .failed(.outputTooLarge) }
            else if output.fileName.contains("/") || output.fileName.contains("\\") || FlingNames.validate(output.fileName).failed {
                phase = .failed(.unsafeName)
            } else if output.kind != file.outputKind {
                phase = .failed(.typeMismatch)
            } else {
                phase = .done(output)
            }
        }
        return .applied
    }

    public mutating func reset() -> PortalStep {
        switch phase {
        case .idle, .done, .failed:
            phase = .idle
            return .applied
        case .received, .converting:
            return .refused
        }
    }

    public mutating func cancel() -> PortalStep {
        switch phase {
        case .received, .converting:
            phase = .idle
            return .applied
        case .idle, .done, .failed:
            return .refused
        }
    }
}

private extension Result where Failure == FlingNameError {
    var failed: Bool {
        if case .failure = self { return true }
        return false
    }
}

public enum PortalDropCommand {
    /// A finished or failed drop clears first. A drop already in hand is left alone.
    public static func drop(_ claim: Result<PortalFileClaim, PortalDropFailure>, on flow: inout PortalDropFlow) -> PortalStep {
        switch flow.phase {
        case .received, .converting:
            return .refused
        case .done, .failed:
            _ = flow.reset()
            return flow.receive(claim)
        case .idle:
            return flow.receive(claim)
        }
    }
}

public enum PortalDropSession {
    public static func run(claim: Result<PortalFileClaim, PortalDropFailure>, bytes: Data, codecs: PortalCodecs = .standard) -> PortalDropFlow {
        var flow = PortalDropFlow()
        _ = flow.receive(claim)
        guard case .received(let file) = flow.phase else { return flow }
        _ = flow.begin()
        _ = flow.finish(PortalConverter.convert(file: file, bytes: bytes, codecs: codecs))
        return flow
    }
}

public struct PortalTrayItem: Equatable, Sendable {
    public var fileName: String
    public var byteCount: Int
    public var kind: PortalConversionKind
}

public struct PortalTray: Equatable, Sendable {
    public private(set) var items: [PortalTrayItem] = []
    public private(set) var flow = PortalDropFlow()

    public init() {}

    public mutating func receive(_ claim: Result<PortalFileClaim, PortalDropFailure>) -> PortalStep {
        if case .idle = flow.phase, items.count >= PortalLimits.maxTrayItems {
            return flow.receive(.failure(.trayFull))
        }
        return flow.receive(claim)
    }

    public mutating func begin() -> PortalStep { flow.begin() }

    public mutating func finish(_ result: Result<PortalConversionOutput, PortalDropFailure>) -> PortalStep {
        let step = flow.finish(result)
        if case .done(let output) = flow.phase {
            items.append(PortalTrayItem(fileName: output.fileName, byteCount: output.bytes.count, kind: output.kind))
        }
        return step
    }

    public mutating func reset() -> PortalStep { flow.reset() }
}

public struct PortalDragOffer: Equatable, Sendable {
    public var fileCount: Int
    public var includesNonFile: Bool
    public var sizes: [Int64]

    public init(fileCount: Int, includesNonFile: Bool, sizes: [Int64]) {
        self.fileCount = fileCount
        self.includesNonFile = includesNonFile
        self.sizes = sizes
    }
}

public enum PortalDragRefusal: Equatable, Sendable {
    case empty, notAFile, mixed, tooMany, itemTooLarge, emptyItem, unreadableSize
}

public enum PortalDragDecision: Equatable, Sendable {
    case accept(Int)
    case refuse(PortalDragRefusal)
}

public enum PortalDrag {
    public static func decide(_ offer: PortalDragOffer) -> PortalDragDecision {
        if offer.includesNonFile && offer.fileCount == 0 { return .refuse(.notAFile) }
        if offer.fileCount <= 0 { return .refuse(.empty) }
        if offer.includesNonFile { return .refuse(.mixed) }
        if offer.fileCount > PortalLimits.maxTrayItems { return .refuse(.tooMany) }
        if offer.sizes.count != offer.fileCount { return .refuse(.unreadableSize) }
        for size in offer.sizes {
            if size < 0 { return .refuse(.unreadableSize) }
            if size == 0 { return .refuse(.emptyItem) }
            if size > Int64(PortalLimits.maxConversionBytes) { return .refuse(.itemTooLarge) }
        }
        return .accept(offer.fileCount)
    }
}
