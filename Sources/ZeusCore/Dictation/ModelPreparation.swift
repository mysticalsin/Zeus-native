/// Download and load of a local speech model (Parakeet), as one state instead of a `progress` optional
/// that doubled as the "already running" flag.
///
/// What that optional got wrong: progress callbacks hop to the main queue, so a late one could land
/// after the finish and leave progress non-nil for good (the bar stuck, every later download refused);
/// there was no way to cancel; and after a failure every dictation key press started the download
/// again, with no terminal state. Here only the live token may move the state, a failure waits for an
/// explicit retry, and cancel is an event.
public enum ModelPreparation {
    public enum State: Equatable, Sendable {
        /// Nothing running; the model has not been prepared this launch.
        case idle
        /// `downloading` is false when the files are already on disk and only loading remains.
        case preparing(token: UInt64, fraction: Double, downloading: Bool, announce: Bool)
        case ready
        case failed(message: String)
    }

    /// Who asked: a key press or launch retry (`automatic`) or a click on Download (`explicit`).
    public enum Trigger: Equatable, Sendable { case automatic, explicit }

    public enum Event: Equatable, Sendable {
        case startRequested(token: UInt64, trigger: Trigger, downloaded: Bool, announce: Bool)
        case progress(token: UInt64, fraction: Double)
        case succeeded(token: UInt64)
        case failed(token: UInt64, message: String)
        case cancelRequested
    }

    public enum Announcement: Equatable, Sendable {
        case downloading
        case ready
        case failed(message: String)
    }

    public enum Effect: Equatable, Sendable {
        case startWork(token: UInt64, downloading: Bool)
        case cancelWork(token: UInt64)
        case announce(Announcement)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .startRequested(let token, let trigger, let downloaded, let announce):
            switch state {
            case .preparing:
                return (state, [])
            case .failed where trigger == .automatic:
                return (state, [])
            case .ready where trigger == .automatic:
                return (state, [])
            case .idle, .ready, .failed:
                let downloading = !downloaded
                var effects: [Effect] = [.startWork(token: token, downloading: downloading)]
                if announce, downloading { effects.append(.announce(.downloading)) }
                return (.preparing(token: token, fraction: 0, downloading: downloading, announce: announce), effects)
            }

        case .progress(let token, let fraction):
            guard case .preparing(let live, _, let downloading, let announce) = state, live == token else { return (state, []) }
            return (.preparing(token: live, fraction: min(max(fraction, 0), 1), downloading: downloading, announce: announce), [])

        case .succeeded(let token):
            guard case .preparing(let live, _, let downloading, let announce) = state, live == token else { return (state, []) }
            return (.ready, announce && downloading ? [.announce(.ready)] : [])

        case .failed(let token, let message):
            guard case .preparing(let live, _, _, _) = state, live == token else { return (state, []) }
            return (.failed(message: message), [.announce(.failed(message: message))])

        case .cancelRequested:
            switch state {
            case .preparing(let token, _, _, _): return (.idle, [.cancelWork(token: token)])
            case .failed: return (.idle, [])
            case .idle, .ready: return (state, [])
            }
        }
    }

    /// 0...1 while preparing, nil otherwise: what Settings and onboarding draw as a progress bar.
    public static func progress(of state: State) -> Double? {
        if case .preparing(_, let fraction, _, _) = state { return fraction }
        return nil
    }

    /// The reason the last attempt failed, for the red line under the model row.
    public static func problem(of state: State) -> String? {
        if case .failed(let message) = state { return message }
        return nil
    }
}
