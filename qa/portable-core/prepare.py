#!/usr/bin/env python3
"""Snapshot selected real Zeus sources into isolated Swift 6 validation packages.

This is a synthetic test harness, not a Linux port or a native macOS build.
The production Package.swift and source files are never changed.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parents[2]
CORE = "Sources/ZeusCore/"
TESTS = "Tests/ZeusCoreTests/"


def core(*paths):
    return [CORE + path for path in paths]


def tests(*names):
    return [TESTS + name + ".swift" for name in names]


GROUPS = {
    "explanation": (
        core("Explanation/ExplanationProtocol.swift", "Explanation/ExplanationReducer.swift",
             "Explanation/ExplanationModel3D.swift", "Explanation/ExplanationModelReducer.swift",
             "Explanation/ExplanationModelWire.swift", "Explanation/ExplanationRecipes.swift",
             "Explanation/ExplanationModelMotion.swift",
             "Explanation/ExplanationStream.swift", "Explanation/ExplanationCompletionStream.swift",
             "Explanation/ExplanationPlayback.swift", "Explanation/ExplanationCoordinates.swift",
             "Explanation/ExplanationHistory.swift", "Explanation/ExplanationDiagnostics.swift",
             "Explanation/ExplanationChartMath.swift", "Explanation/ExplanationCardPlacement.swift",
             "Explanation/ExplanationCardContentBuilder.swift"),
        tests("ExplanationProtocolTests", "ExplanationReducerTests", "ExplanationStreamTests",
              "ExplanationCompletionStreamTests", "ExplanationPlaybackTests", "ExplanationCoordinatesTests",
              "ExplanationHistoryTests", "ExplanationDiagnosticsTests", "ExplanationModelSchemaTests",
              "ExplanationRecipeTests", "ExplanationModelEditTests", "ExplanationModelMotionTests",
              "ExplanationChartMathTests", "ExplanationCardPlacementTests"),
    ),
    "socket-safety": (
        core("UnixSocket.swift", "PeerCredentials.swift", "PeerSigning.swift", "PeerBinaryRule.swift", "ZeusPaths.swift"),
        tests("UnixSocketSafetyTests", "PeerCredentialsTests", "PeerBinaryRuleTests", "PollingWait"),
    ),
    "bridge-transport": (
        core("Bridge.swift", "BridgePendingReplies.swift", "NativeMessageIO.swift", "UnixSocket.swift",
             "PeerCredentials.swift", "PeerSigning.swift", "PeerBinaryRule.swift", "JSONValue.swift", "ZeusPaths.swift",
             "Version.swift") + ["Sources/zeus-bridge/main.swift"],
        tests("NativeMessagingFrameTests", "NativeMessageIOTests", "BridgePendingRepliesTests", "NativeHostProcessTests", "PollingWait"),
    ),
    "keychain": (
        core("Keychain/KeychainStore.swift", "Connections/AIConnectionRegistry.swift",
             "Voice/VoiceTTSProvider.swift", "Voice/VoiceProviderKeychain.swift"),
        tests("KeychainStoreTests", "AIConnectionRegistryTests"),
    ),
    "wiki-export": (
        core("MeetingCopilot.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift", "Scribe/ScribeTranscript.swift", "Scribe/ScribeSpeakerBookModel.swift",
             "Wiki/WikiPage.swift", "Wiki/WikiCompiler.swift", "Wiki/WikiCompilerBox.swift", "Wiki/SensitiveInfoScanner.swift",
             "Wiki/WikiExportModels.swift", "Wiki/WikiExportVault.swift", "Wiki/WikiExportMCP.swift",
             "Wiki/WikiExportJournal.swift", "Wiki/WikiExportTransaction.swift",
             "SecondBrain/SecondBrain.swift", "SecondBrain/VaultPathBoundary.swift", "JSONValue.swift",
             "BrowserAgent/BrowserUseProtocol.swift"),
        tests("WikiExportTests"),
    ),
    "dictation-insertion": (
        core("Dictation/TextInsertionReceipt.swift", "Dictation/WarmFieldInsert.swift", "Dictation/WarmFieldInsertBox.swift",
             "Dictation/DictationWingText.swift",
             "Edit/SelectionEdit.swift", "Edit/SelectionEditBox.swift"),
        tests("TextInsertionReceiptTests", "WarmFieldInsertTests", "SelectionEditBoxTests", "DictationWingTextTests"),
    ),
    "polyglot": (
        core("Polyglot/PolyglotModels.swift", "Polyglot/PolyglotPinPolicy.swift", "Polyglot/PolyglotPipeline.swift", "Polyglot/PolyglotSegmenter.swift"),
        tests("PolyglotTests", "PolyglotPinPolicyTests", "PolyglotTargetChangeTests", "W7PolyglotTests"),
    ),
    "regressions": (
        core("Dictation/DictationCore.swift", "Dictation/SpeechEngineCatalog.swift",
             "Dictation/SpokenDictationMarkup.swift", "Dictation/TranscriptionEngine.swift", "Dictation/WhisperPromptRecovery.swift",
             "Dictation/ThinkingOrbMath.swift", "Dictation/FocusedFieldWrite.swift",
             "Voice/UltronVoiceSignal.swift", "Voice/STTLatency.swift", "Voice/STTFlushLines.swift", "Voice/CommandHotkeyAccess.swift",
             "Recordly/RecordlyCaptureTimeline.swift", "Mac/DriveTypingFlow.swift"),
        tests("DictationExplicitCorrectionTests", "DictationQAFixTests", "SpeechEngineCatalogTests",
              "UltronVoiceSignalTests", "RecordlyCaptureTimelineTests", "DriveTypingFlowTests", "WhisperPromptRecoveryTests",
              "ThinkingOrbMathTests", "STTLatencyTests", "STTFlushLinesTests", "CommandDictatePathTests"),
    ),
    "scribe": (
        core("MeetingCopilot.swift", "TopBar/RecordingMotion.swift", "TopBar/RecordingFeedback.swift",
             "Scribe/ScribeCapture.swift", "Scribe/ScribeMicGate.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribePresentation.swift", "Scribe/ScribeSession.swift", "Scribe/ScribeSpeakerStats.swift",
             "Scribe/ScribeTranscript.swift", "Scribe/ScribeMicrophoneIngress.swift", "Scribe/ScribeEndWorkflow.swift",
             "Scribe/ScribeMuteReadScheduler.swift", "Scribe/ScribeIncomingWordLayout.swift", "Scribe/MicInputOwnership.swift",
             "Scribe/ScribeMeetingCard.swift", "Scribe/ScribeAutoStart.swift",
             "Scribe/ScribeMeetingSignals.swift", "Scribe/ScribeMeetingLedger.swift", "Scribe/ScribeMeetingContext.swift",
             "Scribe/ScribeAutoStartOptIn.swift", "Scribe/ScribeDetectorPlan.swift", "Scribe/ScribeJoinApps.swift",
             "Alerts/AppBrandCatalog.swift"),
        tests("ScribeCoreTests", "ScribePresentationTests", "W7ScribeTests", "W8ScribeLookTests", "RecordingMotionTests", "ScribeCompletionTests",
              "ScribeMicrophoneIngressTests", "ScribeEndWorkflowTests", "RecordingFeedbackTests",
              "ScribeMuteReadSchedulerTests", "ScribeIncomingWordLayoutTests", "MicInputOwnershipTests",
              "ScribeMeetingCardTests", "ScribeAutoStartTests", "ScribeMeetingLedgerTests",
              "ScribeMeetingContextTests", "ScribeAutoStartOptInTests", "ScribeMeetingStartOutcomeTests",
              "ScribeDetectorPlanTests", "ScribeMeetingCardDesignTests"),
    ),
    "presentation": (
        core("JSONValue.swift", "Mac/Walkthrough.swift", "Mac/MacActionNumbers.swift", "Mac/DrivePlan.swift", "Mac/DriveStepBeat.swift",
             "Present/SpeechTimeline.swift", "Voice/AssistantBeam.swift", "Voice/MiddleBarTone.swift",
             "ThemeTokens.swift", "Performance/DisplayAnimationPolicy.swift",
             "TopBar/RecordingFeedback.swift"),
        tests("WalkthroughRevisionTests", "SpeechTimelineTests", "MacActionNumberTests", "AssistantBeamTests", "DisplayAnimationPolicyTests", "DriveStepBeatTests"),
    ),
    "explain-showcase": (
        core("Present/TalkDraw.swift", "Present/ExplainShowcase.swift", "Present/ResearchSourceDraw.swift", "Present/LocalAnswerDraw.swift",
             "Present/TodoListDraw.swift", "Present/CalendarEventDraw.swift", "Present/AgentStartDraw.swift",
             "Present/TodayBoardDraw.swift", "Present/RoutineSavedDraw.swift",              "Present/MemoryKeptDraw.swift",
             "Present/WatchDraw.swift", "Present/TimerDraw.swift",              "Present/ProjectOpenDraw.swift",
             "Present/SiteOpenDraw.swift", "Present/TranslationDraw.swift", "Present/AppLaunchDraw.swift",
             "Present/MediaDraw.swift", "Present/ResearchStartDraw.swift", "Present/AppCloseDraw.swift",
             "Present/TerminalOpenDraw.swift", "Present/SpotifyPlayDraw.swift", "Present/BeamerDraw.swift", "Present/FileFoundDraw.swift", "Present/ShortcutDraw.swift", "Present/ApprovalDraw.swift", "Present/ChoiceDraw.swift", "Present/StopAllDraw.swift", "Present/AgentNoteDraw.swift", "Present/ScreenSightDraw.swift", "Present/AnswerFailDraw.swift", "Present/HearDraw.swift", "Present/ThinkingDraw.swift", "Present/ActionMissDraw.swift", "Present/ControlOffDraw.swift", "Present/VolumeBlockDraw.swift", "Present/FullerAnswerDraw.swift", "Present/TimerFinishedDraw.swift", "Present/LockFailDraw.swift", "Present/DriveAccessDraw.swift", "Present/CalendarAccessDraw.swift", "Present/LeftAloneDraw.swift", "Present/ProjectMissDraw.swift", "Present/TourFailDraw.swift", "Present/ShellBlockDraw.swift", "Present/TodoMissDraw.swift", "Present/RunUnclearDraw.swift", "Present/LinkMissDraw.swift", "Present/StepMissDraw.swift", "Present/TypeSkipDraw.swift", "Present/SendSkipDraw.swift", "Present/PageStaleDraw.swift", "Present/StepLimitDraw.swift", "Present/LoopStopDraw.swift", "Present/UnsureStopDraw.swift", "Present/BadPlanDraw.swift", "Present/StuckDraw.swift", "Present/TourDoneDraw.swift", "Present/SecretFieldDraw.swift", "Present/VoiceOverDraw.swift", "Present/ReportSavedDraw.swift", "Present/MemoryUnchangedDraw.swift", "Present/NoAIDraw.swift", "Present/ResearchAskDraw.swift", "Present/EarlyStopDraw.swift", "Present/TourStopDraw.swift", "Present/NotReadyDraw.swift", "Present/TabOpenDraw.swift", "Present/AgentOffDraw.swift", "Present/DeclinedStopDraw.swift", "Present/MemoryUnreadDraw.swift", "Present/BrowserSetupDraw.swift", "Present/NoGoalDraw.swift", "Present/ClickLeftDraw.swift", "Present/TabHistoryDraw.swift", "Present/UnusableStepsDraw.swift", "Present/BeamerMissDraw.swift", "Present/CalendarFailDraw.swift", "Present/PageUntouchedDraw.swift", "Present/PointSecretDraw.swift", "Present/ReportMissDraw.swift", "Present/ScreenStaleDraw.swift", "Present/TodoDoneDraw.swift", "Present/VaultMissDraw.swift", "Present/EndpointMissDraw.swift", "Present/ScrollRangeDraw.swift", "Present/PageListDraw.swift", "Present/SwitchReadDraw.swift", "Present/ForgetAskDraw.swift", "Present/BrowserStoppedDraw.swift", "Present/KeyUnknownDraw.swift", "Present/FindMissDraw.swift", "Present/FolderMissDraw.swift", "Present/PolyglotOffDraw.swift", "Present/WentAwayDraw.swift", "Present/ClaudeToolDraw.swift", "Present/CantDirectDraw.swift", "Present/WindowMissDraw.swift", "Present/SpotifyPressDraw.swift", "Present/MenuMissDraw.swift", "Present/AskLeftDraw.swift", "Present/DocumentMissDraw.swift", "Present/PageBlockDraw.swift", "Present/TabMissDraw.swift", "Present/AssistantMissDraw.swift", "Present/NoTabDraw.swift", "Present/DocumentGoneDraw.swift", "Present/PageTargetDraw.swift", "Present/NoFieldDraw.swift", "Present/ClickOffDraw.swift", "Present/ClickMissDraw.swift", "Present/ElementMissDraw.swift", "Present/ChoiceMissDraw.swift", "Present/NotFieldDraw.swift", "Present/MissingPieceDraw.swift", "Present/FieldMissDraw.swift", "Present/NoTimerDraw.swift", "Present/ForgetMissDraw.swift", "Present/ForgotDraw.swift", "Present/ResearchBusyDraw.swift", "Present/DriveBusyDraw.swift", "Present/PresentStepsDraw.swift", "Present/NowPlayingDraw.swift", "Present/FocusSessionDraw.swift", "Present/WeatherDraw.swift", "Present/KeepAwakeDraw.swift", "Present/BatteryDraw.swift", "Present/ReminderDraw.swift", "Present/MeetingDraw.swift", "Present/NextEventDraw.swift", "Present/ClockDraw.swift", "Present/CityTimeDraw.swift", "Present/CountdownDraw.swift", "Present/DateDraw.swift", "Present/NoteDraw.swift", "Present/AgentStatusDraw.swift", "Present/TimerLeftDraw.swift", "Present/NextReminderDraw.swift", "Present/AlertStatusDraw.swift", "Present/TodoCountDraw.swift", "Present/VolumeLevelDraw.swift", "Present/BrightnessLevelDraw.swift", "Present/AgendaDraw.swift", "Present/ShelfDraw.swift", "Present/RainDraw.swift", "Present/WeekDraw.swift", "Present/ClipboardCountDraw.swift", "Present/FrontAppDraw.swift", "Present/CapsLockDraw.swift", "Present/FocusRoundsDraw.swift", "Present/DictationWordsDraw.swift", "Present/RecordingStatusDraw.swift", "Present/DarkModeDraw.swift", "Present/TilingStatusDraw.swift", "Present/ScreenCountDraw.swift", "Present/EarbudsStatusDraw.swift", "Present/UsageTodayDraw.swift", "Present/PrompterDraw.swift", "Present/LidStatusDraw.swift", "Present/OutputDraw.swift", "Present/DictationLiveDraw.swift", "Present/PolyglotStatusDraw.swift", "Present/ChatCountDraw.swift", "Present/HeatDraw.swift", "Present/HeyZeusDraw.swift", "Present/FaceDraw.swift", "Present/BeamerPlaceDraw.swift", "Present/VoiceChoiceDraw.swift", "Present/LicenseDraw.swift", "Present/ScreenRecordingDraw.swift", "Present/DriveAutonomyDraw.swift", "Present/NotchPlaceDraw.swift", "Present/PointingKeysDraw.swift", "Present/ChatShortcutDraw.swift", "Present/ProviderDraw.swift", "Present/MusicSourceDraw.swift",
             "Explanation/ExplanationEquationGeometryBox.swift", "Explanation/ExplanationEquationGeometry.swift"),
        tests("ExplainShowcaseTests", "ResearchSourceDrawTests", "LocalAnswerDrawTests", "TodoListDrawTests",
              "CalendarEventDrawTests", "AgentStartDrawTests", "TodayBoardDrawTests", "RoutineSavedDrawTests",
              "MemoryKeptDrawTests", "WatchDrawTests", "TimerDrawTests", "ProjectOpenDrawTests",
              "SiteOpenDrawTests", "TranslationDrawTests", "AppLaunchDrawTests", "MediaDrawTests",
              "ResearchStartDrawTests", "AppCloseDrawTests", "TerminalOpenDrawTests", "SpotifyPlayDrawTests", "BeamerDrawTests", "FileFoundDrawTests", "ShortcutDrawTests", "ApprovalDrawTests", "ChoiceDrawTests", "StopAllDrawTests", "AgentNoteDrawTests", "ScreenSightDrawTests", "AnswerFailDrawTests", "HearDrawTests", "ThinkingDrawTests", "ActionMissDrawTests", "ControlOffDrawTests", "VolumeBlockDrawTests", "FullerAnswerDrawTests", "TimerFinishedDrawTests", "LockFailDrawTests", "DriveAccessDrawTests", "CalendarAccessDrawTests", "LeftAloneDrawTests", "ProjectMissDrawTests", "TourFailDrawTests", "ShellBlockDrawTests", "TodoMissDrawTests", "RunUnclearDrawTests", "LinkMissDrawTests", "StepMissDrawTests", "TypeSkipDrawTests", "SendSkipDrawTests", "PageStaleDrawTests", "StepLimitDrawTests", "LoopStopDrawTests", "UnsureStopDrawTests", "BadPlanDrawTests", "StuckDrawTests", "TourDoneDrawTests", "SecretFieldDrawTests", "VoiceOverDrawTests", "ReportSavedDrawTests", "MemoryUnchangedDrawTests", "NoAIDrawTests", "ResearchAskDrawTests", "EarlyStopDrawTests", "TourStopDrawTests", "NotReadyDrawTests", "TabOpenDrawTests", "AgentOffDrawTests", "DeclinedStopDrawTests", "MemoryUnreadDrawTests", "BrowserSetupDrawTests", "NoGoalDrawTests", "ClickLeftDrawTests", "TabHistoryDrawTests", "UnusableStepsDrawTests", "BeamerMissDrawTests", "CalendarFailDrawTests", "PageUntouchedDrawTests", "PointSecretDrawTests", "ReportMissDrawTests", "ScreenStaleDrawTests", "TodoDoneDrawTests", "VaultMissDrawTests", "EndpointMissDrawTests", "ScrollRangeDrawTests", "PageListDrawTests", "SwitchReadDrawTests", "ForgetAskDrawTests", "BrowserStoppedDrawTests", "KeyUnknownDrawTests", "FindMissDrawTests", "FolderMissDrawTests", "PolyglotOffDrawTests", "WentAwayDrawTests", "ClaudeToolDrawTests", "CantDirectDrawTests", "WindowMissDrawTests", "SpotifyPressDrawTests", "MenuMissDrawTests", "AskLeftDrawTests", "DocumentMissDrawTests", "PageBlockDrawTests", "TabMissDrawTests", "AssistantMissDrawTests", "NoTabDrawTests", "DocumentGoneDrawTests", "PageTargetDrawTests", "NoFieldDrawTests", "ClickOffDrawTests", "ClickMissDrawTests", "ElementMissDrawTests", "ChoiceMissDrawTests", "NotFieldDrawTests", "MissingPieceDrawTests", "FieldMissDrawTests", "NoTimerDrawTests", "ForgetMissDrawTests", "ForgotDrawTests", "ResearchBusyDrawTests", "DriveBusyDrawTests", "PresentStepsDrawTests", "NowPlayingDrawTests", "FocusSessionDrawTests", "WeatherDrawTests", "KeepAwakeDrawTests", "BatteryDrawTests", "ReminderDrawTests", "MeetingDrawTests", "NextEventDrawTests", "ClockDrawTests", "CityTimeDrawTests", "CountdownDrawTests", "DateDrawTests", "NoteDrawTests", "AgentStatusDrawTests", "TimerLeftDrawTests", "NextReminderDrawTests", "AlertStatusDrawTests", "TodoCountDrawTests", "VolumeLevelDrawTests", "BrightnessLevelDrawTests", "AgendaDrawTests", "ShelfDrawTests", "RainDrawTests", "WeekDrawTests", "ClipboardCountDrawTests", "FrontAppDrawTests", "CapsLockDrawTests", "FocusRoundsDrawTests", "DictationWordsDrawTests", "RecordingStatusDrawTests", "DarkModeDrawTests", "TilingStatusDrawTests", "ScreenCountDrawTests", "EarbudsStatusDrawTests", "UsageTodayDrawTests", "PrompterDrawTests", "LidStatusDrawTests", "OutputDrawTests", "DictationLiveDrawTests", "PolyglotStatusDrawTests", "ChatCountDrawTests", "HeatDrawTests", "HeyZeusDrawTests", "FaceDrawTests", "BeamerPlaceDrawTests", "VoiceChoiceDrawTests", "LicenseDrawTests", "ScreenRecordingDrawTests", "DriveAutonomyDrawTests", "NotchPlaceDrawTests", "PointingKeysDrawTests", "ChatShortcutDrawTests", "ProviderDrawTests", "MusicSourceDrawTests"),
    ),
    "recordly-geometry": (
        core("BuddyVisibility.swift", "Present/CompanionMotionBox.swift", "Recordly/RecordlyCursorFollowPath.swift", "Recordly/RecordlyCursorSmoother.swift",
             "Recordly/RecordlyCursorLog.swift", "Recordly/RecordlyZoomRegions.swift", "Recordly/RecordlyExportPlan.swift",
             "Recordly/RecordlyExportSettings.swift"),
        tests("RecordlyCursorFollowTests", "RecordlyExportPlanTests"),
    ),
    "pointing": (
        core("Explanation/ExplanationProtocol.swift", "Explanation/ExplanationReducer.swift",
             "Explanation/ExplanationModel3D.swift", "Explanation/ExplanationModelReducer.swift",
             "Explanation/ExplanationModelWire.swift", "Explanation/ExplanationRecipes.swift",
             "Explanation/ExplanationModelMotion.swift",
             "Explanation/ExplanationStream.swift", "Explanation/ExplanationCompletionStream.swift",
             "Explanation/ExplanationAnthropicStream.swift", "Explanation/ExplanationCoordinates.swift",
             "Explanation/ExplanationChartMath.swift", "Pointing/PointingCardAnchors.swift", "Shortcut.swift", "Present/SpatialTrail.swift", "Present/CoordinateMapper.swift",
             "BuddyVisibility.swift", "Present/CompanionMotion.swift", "Present/CompanionMotionBox.swift",
             "Present/CompanionPointing.swift",
             "KeyFacts.swift", "Pointing/PointingKeyGesture.swift", "Pointing/PointingSession.swift",
             "Pointing/PointerGuidePlan.swift", "Pointing/PointerGuideCaption.swift",
             "Pointing/PointingProposal.swift", "Pointing/PointingActionTools.swift",
             "Pointing/PointingActionToolsBox.swift", "Mac/DrivePlan.swift", "Mac/MacActionNumbers.swift",
             "Mac/AXSnapshot.swift", "Mac/AXSnapshotBox.swift", "JSONValue.swift", "Pointing/PointingTrace.swift",
             "Pointing/PointingContext.swift", "Pointing/PointingSceneResolver.swift",
             "Pointing/PointingProviderSelection.swift", "Pointing/PointingSpeechAlignment.swift",
             "ChatHotkey.swift", "Pointing/PointingStrokeTargeting.swift", "Pointing/PointingDeixis.swift",
             "Pointing/PointingStaleTarget.swift", "Pointing/PointingShortcutConflicts.swift", "Pointing/ShowMeKey.swift",
             "Pointing/PointingInkTrail.swift", "Pointing/PointingInkTrailBox.swift", "Pointing/PointingInkVariant.swift", "Pointing/PointingTraceSpans.swift",
             "Pointing/MarkLayout.swift", "Present/PlayDemoScript.swift", "Present/PresentCard.swift",
             "Pointing/SpokenPointingAsk.swift"),
        tests("PointingKeyGestureTests", "PointingSessionTests", "PointerGuidePlanTests",
              "PointerGuideCaptionTests", "PointingProposalValidationTests", "PointingProposalOfferTests",
              "PointingTraceTests", "PointingCoordinateTests",
              "ExplanationProtocolV2Tests", "ExplanationProtocolV3Tests", "PointingCardAnchorsTests", "PointingProviderTests", "PointingStrokeTargetingTests", "PointingDeixisTests",
              "PointingStaleTargetTests", "ShortcutConflictsPointingTests", "PointingInkTrailTests", "PointingInkVariantTests",
              "PointingTraceSpansTests", "PointingRobustnessTests", "PointingOverlayGeometryTests", "ShowMeKeyTests",
              "MarkLayoutTests", "PlayDemoScriptTests", "PresentCardShownTests", "SpokenPointingAskTests"),
    ),
    "right-option-hold": (
        core("Shortcut.swift", "ChatHotkey.swift", "VoiceKey.swift", "Voice/RightOptionHold.swift"),
        tests("RightOptionHoldTests"),
    ),
    "buddy": (
        core("BuddyVisibility.swift", "Present/CompanionPointing.swift", "Present/CompanionMotion.swift", "Present/CompanionMotionBox.swift", "Present/CoordinateMapper.swift"),
        tests("CompanionPointingTests", "CompanionMotionTests"),
    ),
    "agent-choice-dismiss": (
        core("AgentChoiceDismiss.swift", "JSONValue.swift", "FacePresence/FaceTemplateProof.swift",
             "Earbuds/EarbudsCuePolicy.swift", "Earbuds/EarbudsCuePolicyBox.swift",
             "Earbuds/EarbudsBattery.swift", "Earbuds/EarbudsDisplay.swift", "Earbuds/EarbudsNotchCue.swift",
             "BrowserAgent/WebAddress.swift", "BrowserAgent/BrowserAgentStepBeat.swift",
             "FacePresence/SpoofCuesBox.swift", "FacePresence/SpoofCues.swift", "FacePresence/FaceMatch.swift",
             "FacePresence/EnrollmentPlan.swift", "FacePresence/EnrollmentCoach.swift"),
        tests("AgentChoiceDismissTests", "FaceTemplateProofTests", "EarbudsCuePolicyTests", "EarbudsCuePolicyBoxTests",
              "EarbudsModeSpeechTests", "BrowserWebURLTests", "BrowserAgentStepBeatTests", "EarbudsNotchCueTests", "FaceMatchCeilingTests",
              "EnrollmentCoachTests"),
    ),
    "wiki-relationships": (
        core("MeetingCopilot.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribeTranscript.swift", "Scribe/ScribeSpeakerBookModel.swift", "Scribe/ScribeSession.swift", "Scribe/ScribeRecapNavigation.swift",
             "Wiki/WikiPage.swift", "Wiki/WikiCompiler.swift", "Wiki/WikiCompilerBox.swift", "Wiki/SensitiveInfoScanner.swift", "Wiki/WikiRelationships.swift", "Wiki/WikiGraph.swift"),
        tests("WikiRelationshipsTests", "ScribeRecapNavigationTests", "WikiGraphTests"),
    ),
    # The filter maths takes its lock from the Apple SDK, so this group runs on an Apple platform only.
    "equaliser": (
        core("Audio/EqualiserTypes.swift", "Audio/EqualiserModel.swift", "Audio/EqualiserDSP.swift",
             "Audio/EqualiserCardRules.swift", "Audio/EqualiserPolicy.swift", "Audio/EqualiserLifecycle.swift", "Audio/Spectrum.swift",
             "MeetingCopilot.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribeTranscript.swift", "Scribe/ScribeSpeakerBookModel.swift", "Scribe/ScribeSession.swift",
             "Scribe/ScribeLiveLogic.swift", "Intent/WakePhrase.swift",
             "Intent/Utterance.swift", "Dictation/TranscriptionEngine.swift", "ZeusPaths.swift"),
        tests("EqualiserTypesTests", "EqualiserModelTests", "EqualiserDSPTests", "EqualiserCardRulesTests",
              "EqualiserPolicyTests", "EqualiserLifecycleTests", "EqualiserConsentTests"),
    ),
    "chimes": (
        core("Chime/ChimeSession.swift", "Chime/ChimeSettings.swift", "Chime/ChimeSoundResolver.swift",
             "Chime/ChimeTone.swift", "Chime/ChimeFileAccess.swift"),
        tests("ChimeTests"),
    ),
    # Optional: the Linux Foundation replaceItemAt limitation affects persistence tests here.
    "wiki": (
        core("MeetingCopilot.swift", "ZeusPaths.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribeTranscript.swift", "Scribe/ScribeSpeakerBookModel.swift", "Wiki/WikiPage.swift", "Wiki/WikiCompiler.swift", "Wiki/WikiCompilerBox.swift",
             "Wiki/WikiStore.swift", "Wiki/SensitiveInfoScanner.swift"),
        tests("WikiTests"),
    ),
}

# Darwin only, and not default groups: these files use CoreGraphics transforms and CryptoKit, which a Linux host does
# not have, so the feature map's portable checks (which list GROUPS only) never select them. On a Mac they run the pure
# face presence rules in a small package of their own, without the app, a camera or the Keychain.
DARWIN_GROUPS = {
    "face-presence": (
        core("FacePresence/LandmarkMath.swift", "FacePresence/FaceSelection.swift", "FacePresence/SpoofCues.swift",
             "FacePresence/FaceMatch.swift", "FacePresence/EnrollmentPlan.swift", "FacePresence/PresenceSampler.swift",
             "FacePresence/FaceVault.swift", "FacePresence/FacePresenceMachine.swift", "FacePresence/FacePresenceStatus.swift"),
        tests("LandmarkMathTests", "FaceSelectionTests", "SpoofCuesTests", "FaceMatchTests", "EnrollmentPlanTests",
              "PresenceSamplerTests", "FaceVaultTests", "FacePresenceMachineTests", "FacePresenceStatusTests"),
    ),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def section(path, start, end=None):
    """Copy exact declaration bytes; fail visibly if a boundary becomes ambiguous."""
    data = (REPO / path).read_bytes()
    text = data.decode("utf-8")
    if text.count(start) != 1 or (end is not None and text.count(end) != 1):
        raise ValueError(f"Extraction boundary missing or ambiguous in {path}")
    first = text.index(start)
    last = text.index(end, first) if end else len(text)
    content = text[first:last]
    evidence = {"source": path, "source_sha256": digest(data), "start": start,
                "end_exclusive": end or "EOF", "excerpt_sha256": digest(content.encode())}
    return content, evidence


def write_excerpts(root, group, manifest):
    pieces = []
    if group == "scribe":
        path = CORE + "Scribe/ScribeLiveLogic.swift"
        for start, end in [
            ("public enum ScribeAudioMath {", "// MARK: - Streaming resampler"),
            ("// MARK: - Call-app identification", "// MARK: - Recap notes, cloud disclosure, system-audio stall"),
            ("// MARK: - Mute evidence (fail closed)", "// MARK: - Mute evidence timeline"),
        ]:
            text, evidence = section(path, start, end)
            pieces.append(text)
            manifest["excerpts"].append(evidence)
        # The meeting-start rules read two Settings helpers; the whole file needs types this group does not carry.
        text, evidence = section(CORE + "FeatureSettings.swift", "public enum FeatureSettings {", "    // MARK: Fast path")
        pieces.append(text + "}\n")
        manifest["excerpts"].append(evidence)
        text, evidence = section(TESTS + "ScribeLiveLogicTests.swift",
                                 "    @Test func freshEvidenceIsServedAndExpiredEvidenceIsUnknown()",
                                 "    // MARK: Evidence coverage")
        manifest["excerpts"].append(evidence)
        (root / TESTS / "PortableMuteTests.swift").write_text(
            'import Foundation\nimport Testing\n@testable import ZeusCore\n'
            '@Suite("Scribe mute portable excerpts")\nstruct PortableMuteTests {\n' + text + "\n}\n")
    elif group in ("wiki", "wiki-relationships", "wiki-export"):
        text, evidence = section(CORE + "Scribe/ScribeLiveLogic.swift", "public struct ScribeMeetingRecord:",
                                 "public enum ScribeMeetingStoreError:")
        pieces.append(text)
        manifest["excerpts"].append(evidence)
        if group == "wiki-export":
            text, evidence = section(CORE + "Research/ResearchReport.swift", '    public static let vaultFolder = "ZEUS/Research"',
                                    '    /// Where the report goes:')
            pieces.append("public enum ResearchReport {\n" + text + "\n}")
            manifest["excerpts"].append(evidence)
            text, evidence = section("Sources/Zeus/Wiki/WikiMCPExport.swift",
                                     "extension MCPStdioClient: WikiExportToolClient {", "/// One user-opened selection/review transaction.")
            target = root / "Sources/MCPTransportValidation/MemoryMCPConformance.swift"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("import Foundation\nimport ZeusCore\n" + text)
            manifest["excerpts"].append(evidence)
    elif group == "presentation":
        for path, start, end in [
            (CORE + "ZeusTag.swift", "public struct PointTarget:", "public struct HighlightTarget:"),
            (CORE + "Present/DrawingScene.swift", "public struct MathLayout:", None),
            (CORE + "Mac/AXSnapshot.swift", "public struct AXRef:", "/// What the frontmost window looked like"),
        ]:
            text, evidence = section(path, start, end)
            pieces.append(text)
            manifest["excerpts"].append(evidence)
    elif group == "recordly-geometry":
        text, evidence = section(CORE + "Present/CompanionMotion.swift", "public struct CompanionSpring:",
                                 "/// One frame of a flight.")
        pieces.append(text)
        manifest["excerpts"].append(evidence)
        text, evidence = section(CORE + "Present/CompanionMotion.swift", "private extension CGPoint {",
                                 "private extension CompanionFlight {")
        pieces.append(text)
        manifest["excerpts"].append(evidence)
    if pieces:
        imports = ["Foundation"]
        # These exact declarations use CoreGraphics extensions on Apple SDKs.
        # Linux Foundation provides the geometry values without that module.
        if group in {"presentation", "recordly-geometry"} and manifest["platform"] == "darwin":
            imports.append("CoreGraphics")
        manifest["excerpt_imports"] = imports
        (root / CORE / "PortableExcerpts.swift").write_text("".join(f"import {name}\n" for name in imports) + "\n" + "\n".join(pieces))


def prepare(output, group, *, platform_name=None):
    platform_name = platform_name or ("linux" if sys.platform.startswith("linux") else sys.platform)
    if platform_name not in {"linux", "darwin"}:
        raise ValueError("Portable recipe supports only linux or darwin")
    if group in DARWIN_GROUPS and platform_name != "darwin":
        raise ValueError(f"The {group} group uses CoreGraphics and CryptoKit and runs on darwin only")
    definition = GROUPS[group] if group in GROUPS else DARWIN_GROUPS[group]
    root = output / group
    (root / CORE).mkdir(parents=True)
    (root / TESTS).mkdir(parents=True)
    manifest = {"group": group, "repository": str(REPO), "platform": platform_name, "scope": "Synthetic portable subset; no native app validation",
                "files": [], "excerpts": []}
    for source in sum(definition, []):
        data = (REPO / source).read_bytes()
        target = root / source
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest["files"].append({"source": source, "sha256": digest(data)})
    write_excerpts(root, group, manifest)
    compatibility = group in ("recordly-geometry", "buddy", "pointing", "scribe", "agent-choice-dismiss") and platform_name == "linux"
    extra_target = ''
    products = ''
    core_dependencies = '[]'
    test_dependencies = '["ZeusCore"]'
    test_settings = ''
    if group == "bridge-transport":
        products = 'products: [.executable(name: "zeus-bridge", targets: ["zeus-bridge"])], '
        extra_target = '    .executableTarget(name: "zeus-bridge", dependencies: ["ZeusCore"]),\n'
    elif group == "wiki-export":
        wrapper = root / "Sources/zeus-memory-helper/main.swift"
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text('import Foundation\nimport ZeusCore\nexit(WikiExportMCPCommand.run(Array(CommandLine.arguments.dropFirst())))\n')
        extra_target = ('    .executableTarget(name: "zeus-memory-helper", dependencies: ["ZeusCore"]),\n'
                        '    .target(name: "MCPTransportValidation", dependencies: ["ZeusCore"]),\n')
        for source, target in [
            ("Sources/Zeus/BrowserAgent/MCPStdioClient.swift", "Sources/MCPTransportValidation/MCPStdioClient.swift"),
            ("Sources/Zeus/BrowserAgent/MCPPipeIO.swift", "Sources/MCPTransportValidation/MCPPipeIO.swift"),
            ("Tests/ZeusAppTests/MemoryMCPTransportTests.swift", TESTS + "MemoryMCPTransportTests.swift"),
        ]:
            data = (REPO / source).read_bytes()
            destination = root / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            manifest["files"].append({"source": source, "sha256": digest(data), "target": target})
        test_dependencies = '["ZeusCore", "MCPTransportValidation"]'
        test_settings = ', swiftSettings: [.define("ZEUS_PORTABLE_MCP")]'
        manifest["executable_wrapper"] = "Exact production WikiExportMCPCommand.run; wrapper only forwards arguments. No app control, capture or vault discovery."
    if compatibility:
        # Linux Foundation exports these value types; this supplies the import name only.
        # It supplies no capture, drawing, coordinate conversion, or business implementation.
        shim = root / "Sources/CoreGraphics/FoundationGeometry.swift"
        shim.parent.mkdir(parents=True)
        shim.write_text("@_exported import Foundation\n")
        manifest["compatibility"] = "Linux-only CoreGraphics module reexports Foundation geometry value types. Not Apple CoreGraphics validation."
        extra_target = '    .target(name: "CoreGraphics"),\n'
        core_dependencies = '["CoreGraphics"]'
    (root / "Package.swift").write_text(
        '// swift-tools-version: 6.0\nimport PackageDescription\n'
        'let package = Package(name: "ZeusPortableValidation", platforms: [.macOS("14.2")], '
        + products + 'targets: [\n'
        + extra_target + f'    .target(name: "ZeusCore", dependencies: {core_dependencies}),\n'
        +
        f'    .testTarget(name: "ZeusCoreTests", dependencies: {test_dependencies}{test_settings})\n])\n')
    (root / "validation-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", action="append", choices=[*GROUPS, *DARWIN_GROUPS],
                        help="Repeat to select groups. Default: all except wiki and the darwin-only groups.")
    parser.add_argument("--output", type=Path, help="New output directory; existing paths are never overwritten.")
    parser.add_argument("--run", action="store_true", help="Run swift test in each generated package and retain logs.")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.output:
        output = args.output.expanduser().absolute()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix="zeus-portable-"))
    groups = list(dict.fromkeys(args.group or [name for name in GROUPS if name != "wiki"]))
    results = []
    for group in groups:
        root = prepare(output, group)
        print(f"Prepared {group}: {root}", flush=True)
        if args.run:
            sys.path.insert(0, str(REPO / "qa/closed-loop"))
            from contracts import Invalid, read_swift_testing_xunit, swift_structured_results, swift_testing_xunit_path
            xunit = root / "results.xml"
            command = ["swift", "test", "--package-path", str(root), "--jobs", str(args.jobs),
                       "--xunit-output", str(xunit)]
            log = root / "test.log"
            with log.open("w") as stream:
                result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=False)
            structured = swift_testing_xunit_path(xunit)
            row = {"group": group, "command": command, "exit_code": result.returncode, "log": str(log),
                   "results": str(structured)}
            try:
                count, suites, functions = swift_structured_results(
                    read_swift_testing_xunit(structured), result.returncode, log.read_text())
                row.update(tests=count, suites=suites, passed_functions=functions)
            except (Invalid, OSError) as error:
                row["structured_error"] = str(error)
                if row["exit_code"] == 0:
                    row["exit_code"] = 1
            results.append(row)
            print(f"{group}: exit {row['exit_code']}; {log}", flush=True)
    if results:
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    raise SystemExit(1 if any(row["exit_code"] for row in results) else 0)


if __name__ == "__main__":
    main()
