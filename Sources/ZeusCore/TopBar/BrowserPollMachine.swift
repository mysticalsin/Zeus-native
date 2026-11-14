import Foundation

/// A word for the one hint the notch shows about browser media.
public enum BrowserMediaHint: Equatable, Sendable {
    /// The extension in Chrome is older than the app needs: reload it on Chrome's extensions page.
    case reloadExtension
    /// A tab or its page cannot do what was asked (next, previous, a refused play).
    case commandNotSupported
}

/// What the poll loop knows. Everything the loop does follows from this value and the events below.
public struct BrowserPollState: Equatable, Sendable {
    public var settingOn = false
    public var chromeRunning = false
    public var screensAwake = true
    public var followsAny = true
    public var outputRunning = false
    /// Whether the extension answered a ping with a version new enough; nil until it has.
    public var versionOK: Bool?
    /// One request, a poll or a ping, is out.
    public var inFlight = false
    /// Failures in a row: timeouts, a bridge that is not connected, and replies that were malformed.
    public var failures = 0
    /// How many back-offs in a row have been taken.
    public var backoffStep = 0
    /// After a bridge that was not connected, a ping answers before the next poll.
    public var needsPing = false
    /// The command hint was shown since Chrome last started.
    public var hinted = false

    public init() {}

    public var canPoll: Bool { settingOn && chromeRunning && screensAwake && followsAny && versionOK == true }

    /// Chrome runs, the setting is on and its extension answered with an old version.
    public var needsExtensionReload: Bool { settingOn && chromeRunning && versionOK == false }

    fileprivate mutating func resetConnection() {
        versionOK = nil
        inFlight = false
        failures = 0
        backoffStep = 0
        needsPing = false
        hinted = false
    }
}

public enum BrowserPollEvent: Equatable, Sendable {
    /// The timer ran out; the context says what the notch shows now.
    case tick(BrowserPollContext)
    /// A poll answered with a good reply.
    case reply(BrowserPollContext)
    /// A poll or a ping timed out, or a reply was malformed (a failure like a timeout).
    case timedOut
    /// The bridge refused or could not be reached. A bridge that refuses this app looks the same.
    case notConnected
    /// A command found its page changed.
    case staleTarget
    /// A command is not supported, or the page blocked it.
    case notSupported
    case chromeLaunched
    case chromeQuit
    case settingOn
    case settingOff
    case screensSlept
    case screensWoke
    case followChanged(followsAny: Bool)
    case outputActivity(Bool)
    /// A ping answered, with the extension's version if it sent one.
    case version(String?)
}

public enum BrowserPollEffect: Equatable, Sendable {
    case pingNow
    case pollNow
    /// Arms the one timer, replacing any armed.
    case schedule(TimeInterval)
    case cancelTimer
    /// Takes every browser entry off the hub.
    case dropEntries
    /// Takes the entry the failed command was for off the hub.
    case dropTarget
    case hint(BrowserMediaHint)
}

/// The poll loop for browser media as a pure reducer. `zeus-bridge` answers only a ping from Chrome, so the app
/// asks; this says when, and what to do when the asking fails. The feed carries out the effects.
public enum BrowserPollMachine {
    /// Waits after a bridge that was not connected: 5, 10, 20, 40 s, then 60 s each time.
    public static let backoff: [TimeInterval] = [5, 10, 20, 40, 60]
    /// Failures in a row before the entries are dropped.
    public static let failuresBeforeDrop = 3
    public static let retryDelay: TimeInterval = 5
    public static let resumeDelay: TimeInterval = 1
    public static let firstPollDelay: TimeInterval = 0.5

    public static func next(_ state: BrowserPollState, _ event: BrowserPollEvent) -> (BrowserPollState, [BrowserPollEffect]) {
        var state = state
        switch event {
        case .settingOn:
            guard !state.settingOn else { return (state, []) }
            state.settingOn = true
            state.resetConnection()
            return pingIfChromeRuns(&state)

        case .settingOff:
            state.settingOn = false
            state.resetConnection()
            return (state, [.cancelTimer, .dropEntries])

        case .chromeLaunched:
            state.chromeRunning = true
            state.resetConnection()
            return pingIfChromeRuns(&state)

        case .chromeQuit:
            state.chromeRunning = false
            state.resetConnection()
            return (state, [.cancelTimer, .dropEntries])

        case .screensSlept:
            state.screensAwake = false
            return (state, [.cancelTimer])

        case .screensWoke:
            state.screensAwake = true
            return (state, state.canPoll ? [.schedule(resumeDelay)] : [])

        case .followChanged(let followsAny):
            state.followsAny = followsAny
            if !followsAny { return (state, [.cancelTimer, .dropEntries]) }
            return (state, state.canPoll ? [.schedule(resumeDelay)] : [])

        case .outputActivity(let running):
            state.outputRunning = running
            // A back-off is not cut short by sound starting.
            guard running, state.canPoll, !state.inFlight, state.failures == 0, !state.needsPing else { return (state, []) }
            return (state, [.schedule(resumeDelay)])

        case .version(let version):
            state.inFlight = false
            guard state.settingOn, state.chromeRunning else { return (state, []) }
            guard BrowserMediaRules.extensionSupportsMedia(version: version) else {
                state.versionOK = false
                return (state, [.cancelTimer, .dropEntries, .hint(.reloadExtension)])
            }
            state.versionOK = true
            state.failures = 0
            state.backoffStep = 0
            state.needsPing = false
            return (state, state.canPoll ? [.schedule(firstPollDelay)] : [])

        case .tick(let context):
            guard !state.inFlight, state.settingOn, state.chromeRunning, state.screensAwake, state.followsAny else { return (state, []) }
            // A version not yet known to be new enough is asked for with a ping, never a poll.
            if state.versionOK != true {
                state.inFlight = true
                return (state, [.pingNow])
            }
            guard state.canPoll else { return (state, []) }
            // So is a bridge that was not connected: it answers a ping before the next poll.
            if state.needsPing {
                state.inFlight = true
                return (state, [.pingNow])
            }
            guard BrowserMediaRules.pollDelay(context) != nil else { return (state, []) }
            state.inFlight = true
            return (state, [.pollNow])

        case .reply(let context):
            state.inFlight = false
            guard state.canPoll else { return (state, []) }
            state.failures = 0
            state.backoffStep = 0
            state.needsPing = false
            guard let delay = BrowserMediaRules.pollDelay(context) else { return (state, [.cancelTimer]) }
            return (state, [.schedule(delay)])

        case .timedOut:
            state.inFlight = false
            guard asking(state) else { return (state, []) }
            state.failures += 1
            return (state, drops(state) + [.schedule(retryDelay)])

        case .notConnected:
            state.inFlight = false
            guard asking(state) else { return (state, []) }
            state.failures += 1
            state.needsPing = true
            let delay = backoff[min(state.backoffStep, backoff.count - 1)]
            state.backoffStep += 1
            return (state, drops(state) + [.schedule(delay)])

        case .staleTarget:
            return (state, [.dropTarget])

        case .notSupported:
            guard !state.hinted else { return (state, []) }
            state.hinted = true
            return (state, [.hint(.commandNotSupported)])
        }
    }

    /// Whether the loop is the one asking: a failure while it is stopped or paused is a late answer and changes nothing.
    private static func asking(_ state: BrowserPollState) -> Bool {
        state.settingOn && state.chromeRunning && state.screensAwake && state.followsAny
    }

    private static func pingIfChromeRuns(_ state: inout BrowserPollState) -> (BrowserPollState, [BrowserPollEffect]) {
        guard state.settingOn, state.chromeRunning else { return (state, []) }
        state.inFlight = true
        return (state, [.pingNow])
    }

    /// The entries are dropped on the failure that makes three in a row, once.
    private static func drops(_ state: BrowserPollState) -> [BrowserPollEffect] {
        state.failures == failuresBeforeDrop ? [.dropEntries] : []
    }
}
