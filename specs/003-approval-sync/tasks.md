# Tasks: Approval sync

Red first. The live command-line event is not pinned until a Mac log exists.

- [ ] T001 Write `aTerminalAnswerWithdrawsTheCardWithThatToolUseID` in `Tests/ZeusCoreTests/ApprovalSyncTests.swift`. It fails because `HookEvent` has no tool-use id and `AgentEventServer` does not withdraw on a terminal answer.
- [ ] T002 Write `aPeerHangupWithdrawsTheWaitingCard` in the same file. It fails because `UnixSocket.Connection.receive` calls `finish()` on a failed read and emits no hangup.
- [ ] T003 Make T001 and T002 pass. Do not invent a tool-use id when the fixture omits one. Mark the fixture field as unconfirmed against the live tool.
- [ ] T004 Attach a Mac log of Tony answering in the terminal before renaming the fixture field. Until that log exists, T003 stays on the fixture only.
