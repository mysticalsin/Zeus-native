import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the bundle-id trim inside `ScribeCallProcessIdentity.isValid`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe bundle id box")
struct ScribeBundleIDBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeBundleIDBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeBundleIDBox.blankScalars.count == 5)
        #expect(ScribeBundleIDBox.blankScalars.contains(" "))
        #expect(ScribeBundleIDBox.blankScalars.contains("\t"))
        #expect(ScribeBundleIDBox.blankScalars.contains("\n"))
        #expect(ScribeBundleIDBox.blankScalars.contains("\r"))
        #expect(ScribeBundleIDBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeBundleIDBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeBundleIDBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeBundleIDBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedBundle() {
        #expect(ScribeBundleIDBox.trimmedBundle("\u{200B}") == "\u{200B}")
        #expect(ScribeBundleIDBox.trimmedBundle(" \u{200B} ") == "\u{200B}")
        #expect(ScribeBundleIDBox.trimmedBundle("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeBundleIDBox.trimmedBundle("\u{200B}com.example") == "\u{200B}com.example")
        #expect(ScribeBundleIDBox.trimmedBundle("com.example\u{200B}") == "com.example\u{200B}")
        #expect(ScribeBundleIDBox.trimmedBundle(" \t\n\r\u{00A0}") == "")
        #expect(ScribeBundleIDBox.trimmedBundle("") == "")
        #expect(ScribeBundleIDBox.trimmedBundle("\u{000B}com.example") == "\u{000B}com.example")
        #expect(ScribeBundleIDBox.trimmedBundle("\u{3000}com.example") == "\u{3000}com.example")
        #expect(ScribeBundleIDBox.trimmedBundle(" \tcom.example\r\n") == "com.example")
        #expect(ScribeBundleIDBox.trimmedBundle("\u{00A0}com.example\u{00A0}") == "com.example")
        #expect(ScribeBundleIDBox.trimmedBundle("com.example") == "com.example")
        #expect(ScribeBundleIDBox.trimmedBundle("com\u{200B}example") == "com\u{200B}example")
        #expect(ScribeBundleIDBox.trimmedBundle("\n") == "")
        #expect(ScribeBundleIDBox.trimmedBundle("\r") == "")
        #expect(ScribeBundleIDBox.trimmedBundle("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysWhenACallIdentityIsBound() {
        let session = ScribeSessionID()
        let zero = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{200B}", launchedAt: 1)
        var kept = ScribeEndWorkflow()
        kept.begin(session: session, boundCall: zero)
        #expect(kept.boundCall == zero)
        let stopped = kept.applicationTerminated(zero, session: session, now: 10)
        #expect(stopped)

        let paddedZero = ScribeCallProcessIdentity(pid: 4, bundleID: " \u{200B} ", launchedAt: 1)
        var padded = ScribeEndWorkflow()
        padded.begin(session: session, boundCall: paddedZero)
        #expect(padded.boundCall == paddedZero)

        let between = ScribeCallProcessIdentity(pid: 4, bundleID: "\n\u{200B}\r", launchedAt: 1)
        var betweenFlow = ScribeEndWorkflow()
        betweenFlow.begin(session: session, boundCall: between)
        #expect(betweenFlow.boundCall == between)

        let leading = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{200B}com.example", launchedAt: 1)
        var leadingFlow = ScribeEndWorkflow()
        leadingFlow.begin(session: session, boundCall: leading)
        #expect(leadingFlow.boundCall == leading)

        let trailing = ScribeCallProcessIdentity(pid: 4, bundleID: "com.example\u{200B}", launchedAt: 1)
        var trailingFlow = ScribeEndWorkflow()
        trailingFlow.begin(session: session, boundCall: trailing)
        #expect(trailingFlow.boundCall == trailing)

        let inside = ScribeCallProcessIdentity(pid: 4, bundleID: "com\u{200B}example", launchedAt: 1)
        var insideFlow = ScribeEndWorkflow()
        insideFlow.begin(session: session, boundCall: inside)
        #expect(insideFlow.boundCall == inside)

        let ideographic = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{3000}", launchedAt: 1)
        var ideographicFlow = ScribeEndWorkflow()
        ideographicFlow.begin(session: session, boundCall: ideographic)
        #expect(ideographicFlow.boundCall == ideographic)

        let ideographicName = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{3000}com.example", launchedAt: 1)
        var ideographicNameFlow = ScribeEndWorkflow()
        ideographicNameFlow.begin(session: session, boundCall: ideographicName)
        #expect(ideographicNameFlow.boundCall == ideographicName)

        let vertical = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{000B}", launchedAt: 1)
        var verticalFlow = ScribeEndWorkflow()
        verticalFlow.begin(session: session, boundCall: vertical)
        #expect(verticalFlow.boundCall == vertical)

        let verticalName = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{000B}com.example", launchedAt: 1)
        var verticalNameFlow = ScribeEndWorkflow()
        verticalNameFlow.begin(session: session, boundCall: verticalName)
        #expect(verticalNameFlow.boundCall == verticalName)

        let spaced = ScribeCallProcessIdentity(pid: 4, bundleID: " \tcom.example\r\n", launchedAt: 1)
        var spacedFlow = ScribeEndWorkflow()
        spacedFlow.begin(session: session, boundCall: spaced)
        #expect(spacedFlow.boundCall == spaced)

        let noBreak = ScribeCallProcessIdentity(pid: 4, bundleID: "\u{00A0}com.example\u{00A0}", launchedAt: 1)
        var noBreakFlow = ScribeEndWorkflow()
        noBreakFlow.begin(session: session, boundCall: noBreak)
        #expect(noBreakFlow.boundCall == noBreak)

        for bundle in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}"] {
            var flow = ScribeEndWorkflow()
            let identity = ScribeCallProcessIdentity(pid: 4, bundleID: bundle, launchedAt: 1)
            flow.begin(session: session, boundCall: identity)
            #expect(flow.boundCall == nil)
            let stopped = flow.applicationTerminated(identity, session: session, now: 10)
            #expect(!stopped)
        }

        let dead = ScribeCallProcessIdentity(pid: 0, bundleID: "\u{200B}", launchedAt: 1)
        var deadFlow = ScribeEndWorkflow()
        deadFlow.begin(session: session, boundCall: dead)
        #expect(deadFlow.boundCall == nil)
    }
}
