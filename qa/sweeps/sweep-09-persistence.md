# Sweep 09: persistence, migration, and settings data

Lens: UserDefaults keys, renamed keys, default mismatches, Codable records, corrupt data, shared defaults in tests, file containers, stale keys, import and export, and the first launch versus an upgrade.

Read first: the bug ledger on `zeus-bot/bug-ledger` at `255e52aba94234e2b194fd81b2cf4b93e628cc93` (`specs/bugs/ledger.md`, PR #54). Persistence rows already there are ZB-011, ZB-021, ZB-024, ZB-025, and ZB-030. This file marks a rediscovery as a duplicate and leaves the rest as new.

Integration head read: `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

Open heads fetched from `origin` and read at these SHAs:

| PR | Branch | SHA |
| --- | --- | --- |
| #33 | `zeus-bot/glass-settings-shell` | `d8fb8c2df661c9627cd8d9698fe669141d310b63` |
| #39 | `zeus-bot/settings-general` | `2ef01f4a543d7a91f4d995f47455ef1a8d1a8f25` |
| #40 | `zeus-bot/settings-sensory` | `267614ae2ac5103bf4b3911b1f0d73fb40d429ae` |
| #41 | `zeus-bot/settings-lockscreen` | `cf307002cd9994156cdfc831dbde434ba5822575` |
| #42 | `zeus-bot/settings-weather` | `d0a9000861a61850e8ae396c01b142cce6343748` |
| #43 | `zeus-bot/settings-media` | `a82cb9c0e51c5e2c70d515227fa22e99ef37d0fb` |
| #44 | `zeus-bot/settings-license` | `2ceeeacda7e85b5fe81307245f9bfd362642ff08` |
| #45 | `zeus-bot/settings-accessory` | `f70ea17f5d8611de96ae696687c586abffed2647` |
| #46 | `zeus-bot/settings-battery` | `f71176aff465e80e3704233ac7c032c5f5f37dba` |
| #47 | `zeus-bot/settings-focus` | `5b85d610ee578e8c2aa66760296a059f76a6b5ba` |
| #48 | `zeus-bot/settings-faceid` | `daa3f87a660fae97d9187d9aec99a4303bf6e82c` |
| #49 | `zeus-bot/settings-autoupdate` | `4ada39309d863dcc63b35241f3d77392d4ff2fcb` |
| #50 | `zeus-bot/settings-portal` | `eb977a9bd98bb89c091727c7db72036a51c2dab9` |
| #30 | `zeus-bot/local-voice-contract` | `329bfc2045ed2e7802331ef052468bfdc436f779` |
| #52 | `zeus-bot/companion-persona-orb` | `665b9167303f9596d5222b77a663e36f780d60d7` |
| #53 | `zeus-bot/voice-providers` | `16c2d697dcd479f6cbe510ad65fda731b82194fa` |
| #64 | `zeus-bot/hub-03-transcript` | `0e4111c3abf5c906db5b7aef213f1bb13cebd2cf` |

Scribe and the wiki store were read on the integration head. This VM has no Swift toolchain, so every row is a static reading plus a failing-test sketch. Nothing here was executed.

## Counts

| Kind | P1 | P2 | P3 | Total |
| --- | ---: | ---: | ---: | ---: |
| New | 2 | 8 | 3 | 13 |
| Duplicate of a ZB row | 0 | 4 | 0 | 4 |
| Total rows | 2 | 12 | 3 | 17 |

## New findings

### S09-01

| | |
| --- | --- |
| Severity | P1 |
| Area | Settings, music wings. Owning PR: #43, with the notch reader on integration |
| Where | Integration `2722dcb7` `Sources/Zeus/Settings/GlanceSettingsPages.swift:196-201` and `Sources/Zeus/TopBar/TopBarModel.swift:125-126`. #43 `a82cb9c0` `Sources/ZeusCore/Settings/Sections/Media/MediaSettings.swift:31` and `:294`, `Sources/Zeus/Settings/GlassShell/Sections/Media/MediaSettingsPage.swift:171`, `Sources/Zeus/Settings/GlassShell/Sections/MediaSettingsSection.swift:16-25` |

The notch stores the live waveform as a Boolean at `topBar.musicWings`. The comment on the appearance binding says the notch reads that key, and a plain store write would make a separate `opt.` copy. The Media page still binds the waveform row through `SettingsStore.set`, which writes the string at `opt.topBar.musicWings`.

Sketch: in a private suite, set the Boolean `topBar.musicWings` to false and leave `opt.topBar.musicWings` unset. `TopBarModel` reads false. `MediaSettings` built from `SettingsStore.string("topBar.musicWings")` reads the catalog default true. Then `store.set("topBar.musicWings", "false")` and construct `TopBarModel` again. The model is still true, because it never reads the `opt.` string.

### S09-02

| | |
| --- | --- |
| Severity | P1 |
| Area | Voice providers. Owning PR: #53 |
| Where | #53 `16c2d697` `Sources/ZeusCore/Providers/VoiceProviderSession.swift:8-9`, `:23`, `:53-68`, `:230-235` |

`voice.ttsProvider` is the existing settings key. `choice(fromTTSProvider:)` keeps only two adapter raw values. Every other `VoiceTTSProvider` raw value, including the local alternate and the cloud cases the Voice card already stores, becomes `.local`. `select` then writes that choice back with `ttsProviderRaw`, and the local case is stored as `kokoro`.

Sketch: in a private suite, set `voice.ttsProvider` to a `VoiceTTSProvider` raw value for which `choice(fromTTSProvider:)` returns `.local` and which is not `kokoro`. Read `VoiceProviderPreferences.choice` and expect `.local`. Assign `.local` back. Expect the stored string to change to `kokoro`. The previous provider is gone. There is no migration that keeps the old raw value, and the read does not leave the key untouched.

### S09-03

| | |
| --- | --- |
| Severity | P2 |
| Area | Screen sharing. Owning area: integration |
| Where | Integration `2722dcb7` `Sources/Zeus/Meeting/MeetingCopilotController.swift:30-31`, `Sources/ZeusCore/MeetingCopilot.swift:87-90`, `Sources/Zeus/App/ExtraPreferences.swift:82-83`, `Sources/ZeusCore/ScreenShare/ZeusScreenSharePolicy.swift:5-15`, `Sources/Zeus/App/ScreenShareMigration.swift:4-9`, `Sources/Zeus/App/SettingsCatalog.swift:15` |

Two keys describe the same privacy choice. The live windows follow `opt.general.showInScreenSharing` (string, default hidden). `MeetingCopilotController.hiddenFromCapture` follows the Boolean `interview.hide`, and a missing value is treated as show. `ScreenShareMigration` copies `interview.hide` into the `opt.` key once, while that key is still absent, and later edits of either key do not update the other.

The meeting panel type is not mounted in the live window graph, so the notch today follows the `opt.` key. The controller still computes capture from the old key. A fresh suite therefore hides the notch and reports the meeting surfaces as shown.

Sketch: empty suite. Expect `ZeusScreenSharePolicy.showInScreenSharing(from:)` to be false and `!ExtraPreferences.hideFromScreenShare` to be true. Set `opt.general.showInScreenSharing` to `"false"` after the migration has already run, leave `interview.hide` unset, and expect `MeetingCopilotController.hiddenFromCapture` to stay false while a meeting is active.

### S09-04

| | |
| --- | --- |
| Severity | P2 |
| Area | Router quota memory. Owning area: integration |
| Where | Integration `2722dcb7` `Sources/Zeus/Brain/Router.swift:276-284` |

`exhausted` is saved as `[String: Date]` under `router.exhausted`. The loader casts `dictionary(forKey:)` to `[String: Date]`. That cast fails: `dictionary(forKey:)` returns `[String: Any]`, and a Swift conditional cast of the whole dictionary does not succeed. The `?? [:]` then drops every saved expiry. After relaunch, an engine that was out of quota is eligible again.

Sketch: private suite, set `router.exhausted` to one engine raw value mapped to `Date().addingTimeInterval(3600)`, then run the same cast the loader uses. Expect the cast to be nil. `loadExhausted()` returns an empty map while the key is still present.

### S09-05

| | |
| --- | --- |
| Severity | P2 |
| Area | Weather. Owning PR: #42 |
| Where | #42 `d0a90008` `Sources/ZeusCore/Settings/Sections/Weather/WeatherSettingsDisk.swift:25-44`, `Sources/Zeus/Settings/GlassShell/Sections/WeatherSettingsSection.swift:287-305` and `:337-340` |

`setPreciseLocation` updates the in-memory machine and does not call `persist`. `load` always returns `preciseLocation: false`. A later launch shows the switch off. `save`, which runs for a city, a unit, or a layout change, also deletes `perm.location`.

Sketch: private suite, set `perm.location` to `"true"`, call `WeatherSettingsModel.setPreciseLocation(true)`, then `setUnit`. Expect `defaults.object(forKey: "perm.location")` to be nil. Construct a new model from the same suite and expect `editor.location.wantsPreciseLocation` to be false.

### S09-06

| | |
| --- | --- |
| Severity | P2 |
| Area | Notification mirror. Owning area: integration |
| Where | Integration `2722dcb7` `Sources/Zeus/TopBar/TodayController.swift:220-227`, `Sources/Zeus/App/SettingsCatalog.swift:89`, `Sources/Zeus/App/SettingsStore.swift:249-256` and `:348-358` |

The live switch writes the Boolean `notifications.mirror`. The catalog id is `notify.mirror`, which the settings store would keep as the string `opt.notify.mirror`. Nothing reads `opt.notify.mirror` into `NotificationsController`. `notifications.mirror` is also absent from `SettingsStore.appRules`, so export omits it and import cannot restore it.

Sketch: set `notifications.mirror` to true, export, and expect the `app` object to lack that key. Import the file into an empty suite and expect `NotificationsController` to read false. A pre-existing `opt.notify.mirror` of `"true"` likewise leaves the Boolean key unset.

### S09-07

| | |
| --- | --- |
| Severity | P2 |
| Area | To-do vault connection. Owning area: integration |
| Where | Integration `2722dcb7` `Sources/Zeus/TopBar/TodoController.swift:71-74` and `:119-122`, `Sources/ZeusCore/SecondBrain/SecondBrain.swift:50-70` |

`todo.connection` is one JSON blob of `BrainConnection` with synthesized `Codable` and no schema version. `init` uses `try?`, so a truncated blob, a missing field, or a future required field loads as no connection. The bad bytes stay in place. `connect` uses `try?` on encode and passes the result to `set`, so an encode failure removes the key.

Sketch: write `Data("{}".utf8)` to `todo.connection` and construct `TodoController`. Expect `connection` to be nil and the key to still hold the bytes. There is no corrupt-file copy and no version field a later decoder can branch on.

### S09-08

| | |
| --- | --- |
| Severity | P2 |
| Area | Hub transcript. Owning PR: #64. Related to ZB-030, which covers directory mode and write locking, and is a separate row |
| Where | #64 `0e4111c3` `Sources/ZeusCore/AgentHub/HubTranscript.swift:5-27` and `:192-216` |

`HubTranscript` and `HubTranscriptLine` use synthesized `Codable`. There is no schema version. `failed` has a default on the memberwise init and is still required in the JSON. `load` turns a missing file, a truncated file, a missing field, and an id that does not match the file name into nil. The bad file stays in the directory, so the next launch looks like a conversation that was never saved.

Sketch: write a transcript, then delete the `failed` field from the line JSON and call `load`. Expect nil. Write `{"id":"<the file uuid>"}` and expect nil. A second `HubTranscriptStore` on the same directory returns nil as well. ZB-030 still applies to the same `write`: the directory mode follows the process umask and two writes of one id are not serialized.

### S09-09

| | |
| --- | --- |
| Severity | P2 |
| Area | Tests sharing the global defaults. Owning area: integration. Distinct from ZB-011, which is the Scribe opt-in suite |
| Where | Integration `2722dcb7` `Tests/ZeusAppTests/HomeAppTests.swift:7-28` and `:52-74`, `Tests/ZeusAppTests/TalkVisualTurnTests.swift:388-401`, `Sources/Zeus/TopBar/TopBarModel.swift:277-325` |

`HomeAppTests` uses `SettingsStore.shared` and `UserDefaults.standard`. `tabEditorPersistsToTheLayoutStore` restores `topBar.tabs` and `topBar.tabs.known` only. `TopBarModel.init` also writes `topBar.row9.v1` through `topBar.row14.v1` and `topBar.layoutRepair` when the process is not a snapshot and not the QA policy. Those flags stay set. `voicedTextHasNoEllipsisForUltronAndKeepsItForPlain` sets `voice.personality` to `plain` and the deferred cleanup removes the key, including a value `asUltron` had just restored.

Sketch: parallel runs of `HomeAppTests.tabEditorPersistsToTheLayoutStore` and any other test that reads `topBar.tabs` from `.standard`. Expect an interleaved layout. For the personality test, pre-set `voice.personality` to `ultron`, run the test, and expect the key to be absent afterwards.

### S09-10

| | |
| --- | --- |
| Severity | P2 |
| Area | Saved voice record. Owning PR: #30 |
| Where | #30 `329bfc20` `Sources/ZeusCore/Voice/PersistedVoiceSettings.swift:4-33`. The live reader remains integration `2722dcb7` `Sources/Zeus/Voice/VoiceSettings.swift:114-133` |

`PersistedVoiceSettings` is a `Codable` record whose keys are the existing `voice.engine`, `voice.engine.userSelected`, `voice.ttsProvider`, and `voice.engine.auto` strings. Nothing in the app builds that record from `UserDefaults`. `VoiceSettings` still reads each key on its own. The record has no schema version. `userSelected` is decoded with `decodeIfPresent(Bool.self)`, so a string or a number at that key throws and the whole record, including a saved engine, is rejected.

Sketch: encode nothing and decode `{"voice.engine":"kokoro","voice.engine.userSelected":"true"}`. Expect a throw, so the engine string is discarded with the bad Boolean. Separately, set the four live keys on a suite the way `VoiceSettings` writes them and confirm no API on this type loads that suite.

### S09-11

| | |
| --- | --- |
| Severity | P3 |
| Area | Teleprompter slide advance. Owning area: integration |
| Where | Integration `2722dcb7` `Sources/Zeus/Prompter/PresenterNotesController.swift:68` and `:155-156`, `Sources/Zeus/Prompter/PrompterWindow.swift:643-648`, `Sources/Zeus/Settings/GSFeaturesPage.swift:11-12`, `Sources/Zeus/App/SettingsCatalog.swift:186` |

The settings toggle and the window store `prompter.followAdvances`, default false. `PresenterNotesController.advanceSlides` reads `prompter.advanceSlides`, default true, and no writer in `Sources` sets that key. `heard(wordIndex:)` uses `advanceSlides` when the caller omits `enabled`. The window omits it whenever `sync` or `model.presenter` is missing (`PrompterWindow.swift:643-644`). While a deck is loaded, that path advances slides with the default true.

Sketch: empty suite, a controller whose deck is loaded, `heard(wordIndex:)` with `enabled` nil. Expect the guard to pass `advanceSlides == true` while `prompter.followAdvances` is absent. Set `prompter.followAdvances` to false and expect the same call to still advance.

### S09-12

| | |
| --- | --- |
| Severity | P3 |
| Area | Teleprompter speed and size. Owning area: integration |
| Where | Integration `2722dcb7` `Sources/Zeus/TopBar/TopBarModel.swift:192-212` and `:333-335`, `Sources/Zeus/Prompter/PrompterWindow.swift:81-84` and `:683`, `Sources/Zeus/App/SettingsStore.swift:279` |

The notch stores `prompter.speed` (default 32) and `prompter.size` (default 22). The window stores `prompterWindow.speed` (default 40) and `prompterWindow.font` (default 32). Keyboard faster and slower call `persistSpeed`, which writes only `prompterWindow.speed`. Export lists `prompter.speed` and `prompter.size` and does not list the window keys, so a file round-trip keeps the notch numbers and drops the window numbers.

Sketch: set `prompter.speed` to 10 and `prompterWindow.speed` to 80. Open the window model and the notch model from the same suite. Expect 80 and 10. Export and expect `prompterWindow.speed` to be absent from both `options` and `app`.

### S09-13

| | |
| --- | --- |
| Severity | P3 |
| Area | Updates. Owning PR: #49 |
| Where | #49 `4ada3930` `Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdatePersistence.swift:47-61`, `Sources/ZeusCore/Settings/Sections/AutoUpdateSectionSlot.swift:19` |

`about.autoInstall` is registered as a toggle (`importCannotEnable`, default `"false"`). `load` returns `automaticInstall: false` and never reads the key. `save` writes `"false"` and ignores `state.automaticInstall`. A caller that passes true still lands on false. The policy name allows the owner to turn the switch on and blocks an import from doing so. The store blocks the owner as well.

Sketch: `UpdateSettingsStore.save` with `automaticInstall: true`, then `load`. Expect `loaded.automaticInstall == false` and the stored string `"false"`. `Tests/ZeusCoreTests/Sections/AutoUpdate/UpdatePersistenceTests.swift` already locks this discard.

## Duplicates

These match rows already in `specs/bugs/ledger.md` on `255e52ab`. They are not new work.

| ID | Duplicate of | Still where |
| --- | --- | --- |
| S09-14 | ZB-011 | Integration `2722dcb7`. The single-test helper in `Tests/ZeusCoreTests/ScribeAutoStartOptInTests.swift:11-13` now uses a private suite. The ledger row is the parallel `portable-scribe` failure, where one test observed the stamp another test had written. |
| S09-15 | ZB-024 | Integration `2722dcb7` `Sources/Zeus/App/LicenseManager.swift:163-165` and `:181-183`. Activation still writes the proof before the key, and a refused activation still keeps the refusal in defaults. |
| S09-16 | ZB-025 | Integration `2722dcb7` `Sources/ZeusCore/License/LicenseEngine.swift:69-72`. An undecodable revocation list still counts as not revoked. |
| S09-17 | ZB-030 | #64 `0e4111c3` `Sources/ZeusCore/AgentHub/HubTranscript.swift:192-195`. Directory and file mode follow the umask, and two writes of one id are unlocked. S09-08 is the schema and corrupt-read row on the same store. |

## Checked and not filed

- ZB-021 on the current #39 head `2ef01f4a`. `GeneralSettingsSection.applyReset` walks `SettingsCatalog` and `GeneralSectionSlot.keyContributions` (`Sources/Zeus/Settings/GlassShell/Sections/GeneralSettingsSection.swift:243-251`). The reset gap in the ledger was on the older SHA `4fe1e8ed`.
- #52 `665b9167` `Sources/ZeusCore/Companion/Persona.swift:63-70`. `PersonaVoiceResolver.resolve` ignores the defaults argument. The removed keys `companion.jarvisCloudVoice.enabled` and `companion.jarvisCloudVoice.id` are written only by tests. No production reader applies them. The existing `voice.personality` key is left in place (`Tests/ZeusCoreTests/PersonaSwapTests.swift:135-138`).
- Onboarding still treats `didOnboard` as completed, and `markCompleted` writes both `zeus.onboarding.completed` and `didOnboard` (`Sources/Zeus/Onboarding/OnboardingFlow.swift:189-191`, `Sources/Zeus/Onboarding/OnboardingDependencies.swift:79-82`).
- Halo still folds `topBar.halo` into `opt.halo.style` and removes the old key (`Sources/ZeusCore/TopBar/HaloKit.swift:80-88`).
- The wiki store keeps an unreadable `_state.json` by copying it aside before a reset, and a failed reset leaves learning paused (`Sources/ZeusCore/Wiki/WikiStore.swift:251-310`). Page ids are checked before they become paths (`:159-166`).
- #33 `d8fb8c2` loads section contributions into `SettingsStore.values` and puts exportable ones through `SettingsKeyLedger.exportMap`. That closes the "new section key never enters the settings file" gap for branches that contain this store. Integration `2722dcb7` does not have that loader yet, because the shell is still on #33.
