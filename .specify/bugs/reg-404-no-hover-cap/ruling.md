# Ruling: no hover cap on the Scribe meeting card

- **Date**: 2026-11-19 08:49
- **Reverses**: Jarvis, 2026-11-18 11:11, which kept the 30 s hover cap from `634b5b5`
- **Guard**: REG-404, `theCardNeverExpiresUnderThePointer` in `Tests/ZeusCoreTests/ScribeMeetingStartOutcomeTests.swift`

The Scribe meeting card never expires while the pointer rests on it. There is no 30 s cap. A card that disappears while it is being read is worse than one that stays until the pointer leaves, and that is what ships.

The offer and a failure both stay up under a resting pointer. Each leaves once the pointer does. The shipping path is `ScribeAutoStartMachine`, driven by `ScribeAutoStartController` and drawn by `ScribeMeetingCardPanel`. `ScribePopupLifecycle` is not called by the app. The 45 s slow-start timeout and the 20 s ask timeout are unchanged.
