import Foundation

public enum ZeusWatchVoice {
    /// Exit 0 when no compiler build is running. The runner only trusts it after it has seen
    /// a build running once, so "finished" means running, then not.
    public static let buildFinishedTest = "! pgrep -x xcodebuild >/dev/null && ! pgrep -x swift-build >/dev/null"

    /// The runner executes only this test; any other shell trigger is never run.
    public static func isRunnableTest(_ command: String) -> Bool { command == buildFinishedTest }

    public static func parse(_ text: String) -> ZeusWatch? {
        var utterance = Utterance(text)
        utterance.stripFiller()
        let joined = utterance.words.joined(separator: " ")
        if joined.hasPrefix("stop watching") || joined == "stop watch" {
            return nil
        }
        if joined.contains("when the build finishes") || joined.contains("when build finishes") {
            return ZeusWatch(label: "build", trigger: .shellTest(exitZeroWhen: buildFinishedTest))
        }
        if let range = joined.range(of: "when ") {
            let rest = String(joined[range.upperBound...])
            if rest.hasSuffix(" is gone") || rest.hasSuffix(" goes away") {
                let title = rest.replacingOccurrences(of: " is gone", with: "").replacingOccurrences(of: " goes away", with: "")
                return ZeusWatch(label: title, trigger: .windowGone(titleContains: title))
            }
            if rest.hasSuffix(" appears") || rest.hasSuffix(" shows up") {
                let title = rest.replacingOccurrences(of: " appears", with: "").replacingOccurrences(of: " shows up", with: "")
                return ZeusWatch(label: title, trigger: .windowShows(titleContains: title))
            }
        }
        return nil
    }
}
