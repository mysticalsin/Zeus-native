# Sweep 05 — UX coherence

Lens: things that do not make sense. Inconsistent names, contradictory defaults, states with no way out, unclear or internal error text, missing confirms, hotkey clashes, codenames in copy, token drift, behaviour that disagrees with the specs, missing empty or error states, and the same feature in two places.

Scope read: `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`, plus the open `zeus-bot/*` heads named below. Docs only. Nothing here is wired into `Package.swift` or CI.

The bug ledger on `zeus-bot/bug-ledger` (PR #54, `255e52aba94234e2b194fd81b2cf4b93e628cc93`) was read first. Rows already there are listed at the end and are not given a new id.

## What this pass could check

This VM is Linux. The Mac app was not launched, so none of these rows are a clicked journey. Each citation is the source a person would meet. Evidence is static.

Heads opened for this lens:

| Head | SHA | Why it was opened |
| --- | --- | --- |
| integration | `2722dcb7497d5415fbc1fcb1f65c49629966a281` | Settings, top bar, Scribe, Murmur, voice, music |
| #54 `zeus-bot/bug-ledger` | `255e52aba942` | Ledger, so this sweep does not re-file those rows |
| #81 `zeus-bot/right-command-toggle` | `817c4219cf7c` | Right Command tap beside the dictation key |
| #67 `zeus-bot/hub-05-screen` | `8babfef2818d` | Hub status words |
| #65 `zeus-bot/hub-07-experience` | `48b32bfef8e7` | Hub labels and focus order |
| #22 `zeus-bot/settings-plain` | `ff33ee3d9ea7` | Settings sentences after the copy pass |
| #52 `zeus-bot/companion-persona-orb` | `665b9167303f` | Orb persona. No new row. The ledger already notes the spawn arrays are trimmed on this head |
| #21 `zeus-bot/murmur-mic-first` | `49db259e4549` | Dictation start order. No new row |

The open pull list against integration was enumerated (56 pulls at the time of the read). #22 targets `main` and was read because its branch is `zeus-bot/settings-plain`. Surfaces with no row were read and did not yield a separate defect: the orb contract on #52, the dictation-start order on #21, and the hub focus labels on #65 (the vocabulary clash is filed on #67, where the words are defined).

## Findings

### S05-01

| | |
| --- | --- |
| Severity | P1 |
| Where | `zeus-bot/right-command-toggle` `817c4219cf7c`. `Sources/Zeus/Voice/HotkeyMonitor.swift:83-85` and `:273-303`. `Sources/Zeus/App/AppDelegate.swift:328-330` and `:678`. The settings sentence is unchanged from integration: `Sources/Zeus/Settings/GlanceSettingsPages.swift:875-878` |
| Why it confuses | A short tap of Right Command starts Talk to Zeus. The Shortcuts page still calls that key Dictation and says to hold it and let go to write. The recovery hint on this head only says to hold Control and Option again, so a person who just used Right Command is sent to the other key. A hold of Right Command is still the dictation key, so one physical key is two features and only one of them is labeled. |
| Fix | Tell the Shortcuts and Murmure pages that a tap of Right Command talks and a hold dictates, or stop the tap from starting a talk turn while Right Command is the dictation key. Name Right Command in the "you can hear me now" hint when that tap was the press. |
| Owner | #81, top bar / voice |

### S05-02

| | |
| --- | --- |
| Severity | P1 |
| Where | integration `2722dcb7`. `Sources/Zeus/Polyglot/PolyglotSettings.swift:12-13` and `:30` (on by default, Control-Option-T). `Sources/Zeus/App/ExtraPreferences.swift:78-79` (Quick to-do defaults to the same chord). `Sources/Zeus/App/AppDelegate.swift:1133-1141` registers Quick to-do. `Sources/Zeus/Settings/GlanceSettingsPages.swift:881-886` lists the agent picker and has no Quick to-do row. `Sources/Zeus/Settings/GSPolyglotPage.swift:51-54` compares the recorder only with Talk to Zeus |
| Why it confuses | Polyglot is on from the first launch and advertises Control-Option-T as "Start or stop Polyglot". The same chord opens the To-do tab, and the settings window the person can open never shows that shortcut, so they cannot see the clash or move it. The Polyglot default comment still says the chord avoids the old talk pair. Talk has since moved onto Control and Option, and the clash that remains is with Quick to-do. |
| Fix | Show Quick to-do on the Shortcuts page. Refuse or warn when Polyglot is recorded onto a chord another Zeus shortcut already holds. Pick a default that is free of Control-Option-T. |
| Owner | integration, Shortcuts and Polyglot |

### S05-03

| | |
| --- | --- |
| Severity | P1 |
| Where | integration `2722dcb7`. `Sources/Zeus/App/SettingsCatalog.swift:163-164` (pointing on, default Control-Option, and the note that says to pick Right Option for a separate pointing turn). `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift:2-4` and `:34-38`. `Sources/ZeusCore/VoiceKey.swift:62-70` (an unrecorded second talk key gives way when it matches pointing). `Sources/Zeus/Settings/GlanceSettingsWindow.swift:6-12` (no pointing section) |
| Why it confuses | Pointing is on by default on the same chord as Talk to Zeus, so one hold is one talk turn and the pointing trail does not get its own press. The catalog tells the person to pick Right Option to split them. Right Option is already the second talk key. The settings window has no page for the pointing key, so the choice the note describes cannot be made. `docs/FIRST-RUN-DEFAULTS.md` describes the same overlap as intended, and the window still does not show it. |
| Fix | Put the pointing key on the Shortcuts page, next to Talk to Zeus and the second talk key. If Right Option is chosen for pointing, say that the second talk key turned off, and offer a free key. |
| Owner | integration, pointing and Shortcuts |

### S05-04

| | |
| --- | --- |
| Severity | P1 |
| Where | integration `2722dcb7`. `Sources/Zeus/App/SettingsCatalog.swift:180` (default on: each talk question can send a screenshot of every display). `Sources/ZeusCore/FeatureSettings.swift:48`. `Sources/Zeus/App/VoiceTurnController.swift:102` and `:842`. The Voice page (`Sources/Zeus/Settings/GlanceSettingsPages.swift:1006-1034`) has the talk key, the microphone, and keywords, and does not draw this switch. Pointing's screenshot switch defaults off at `SettingsCatalog.swift:166` and is also absent from that window |
| Why it confuses | Talk sends screen images unless the person turns a switch off, and the Voice page has no such switch. Pointing's matching switch defaults off. A person who looked through Settings and left screenshots off has only seen the pointing row in the catalog, which the window does not show, while talk is already on. |
| Fix | Draw both switches on the Voice page, default the talk switch off until the person opts in, and use one sentence for both. |
| Owner | integration, voice |

### S05-05

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Sidebar titles `Sources/Zeus/Settings/GlanceSettingsWindow.swift:69-71`. Murmure page `Sources/Zeus/Settings/GlanceSettingsPages.swift:969-990`. Dictation page `Sources/Zeus/Settings/GSDictationPage.swift:42-62` and `:75-78`. Notch tab `Sources/ZeusCore/TopBar/TopBarLayout.swift:26` |
| Why it confuses | The notch tab, onboarding, and one sidebar item say Murmure. The shortcut, the enable switch, and a second sidebar item say Dictation. Both pages edit the same enable switch, the same shortcut, and the same language. Turning dictation off on one page turns it off on the other, under a different name. |
| Fix | One sidebar item. Use Murmure as the name and "dictation" only as the verb, or the reverse, on the tab, the shortcut, and the page. |
| Owner | integration, Murmure |

### S05-06

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Menu-bar panel `Sources/Zeus/App/PanelView.swift:98-100` (`presence.nearCursor`, default on, moves the dictation pill). Orb choices `Sources/ZeusCore/BuddyVisibility.swift:10-14` ("When I call him", default). Settings and the notch More menu `Sources/Zeus/Settings/GlanceSettingsPages.swift:295-302` and `Sources/Zeus/TopBar/TopBarViews.swift:417-420`. On #22 `ff33ee3d9ea7` the same card's sentence is `GlanceSettingsPages.swift:296-297` |
| Why it confuses | Two controls use nearly the same words and do different jobs. The panel switch follows the pointer with the dictation pill and starts on. The settings popup and the notch menu place the orb, and the default is only while Zeus is called. The option title calls Zeus "him". On #22 the helper always says he stays out of the way until called, which is false when the popup is Always or Never. |
| Fix | Name the pill and the orb in the control titles. Drop "him". On #22, change the helper when the popup changes, or describe all three choices in one sentence. |
| Owner | integration for the two controls. #22 for the helper that describes only one choice |

### S05-07

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. `Sources/Zeus/Settings/GlanceSettingsPages.swift:242-244` (Top bar position, "closed notch"), `:275` (Open the notch), `:289` (Hide the notch), `:339-341` (Island background) |
| Why it confuses | One Appearance page uses three names for the strip at the top of the screen. The position row says it lowers the closed notch. The background row is an island. The behavior rows say notch. A person cannot tell whether the island background is the thing the position slider moves. |
| Fix | Pick one name for the closed strip and use it on the position row, the background row, and the open and hide rows. |
| Owner | integration, top bar |

### S05-08

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. `Sources/Zeus/Settings/GSVoiceCards.swift:41` and `:45-58`. `Sources/ZeusCore/Voice/UltronVoicePlan.swift:6` ("Ultron voice (default)"). `Sources/ZeusCore/Persona/ZeusVoiceLines.swift:12-16` (personality titles Ultron and Plain). `Sources/Zeus/Brain/ZeusPrompt.swift:33` tells the model never to claim that name |
| Why it confuses | Voice settings present Ultron as the personality, the default voice, and an effect with a robotic edge. The prompt the voice speaks from says Zeus must never claim that name. The person is asked to pick a codename the product then refuses to say. |
| Fix | Show the manner in the words already used for it ("Calm, precise and a little wry") and name the effect for what it does. Keep the codename out of the popup and the row title. |
| Owner | integration, voice |

### S05-09

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Style names `Sources/ZeusCore/Sound/SoundCatalog.swift:27-38` ("Spaceship Futuristic", "Mystery Game", "Weard Permission", "Weard 2 Permission"). Card style `Sources/Zeus/Settings/GlanceSettingsPages.swift:229` ("Dashboard B"). Run-start picker `GlanceSettingsPages.swift:595`. Chime default off `Sources/Zeus/App/SettingsCatalog.swift:102` (`sound.agentStart`, default false) |
| Why it confuses | The sound and look pickers offer internal names. "Weard Permission" and "Dashboard B" do not say what the person will hear or see. The Run start picker sits next to "Chime when an agent starts working", which is off by default, so a chosen start sound stays silent. |
| Fix | Rename each style for the sound or the look. Grey the Run start picker, or hide it, while the chime is off, and say that the chime is the switch. |
| Owner | integration, Sounds and Appearance |

### S05-10

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. `Sources/Zeus/Settings/GlanceSettingsPages.swift:888-889` ("a key", no chord). The chords are registered at `Sources/Zeus/App/AppDelegate.swift:1144-1151` (Control-Option with Y, N, and O). The agent-picker row at `GlanceSettingsPages.swift:881-886` has no mention of arrows, Return, or Esc, which the catalog note at `SettingsCatalog.swift:120` does describe |
| Why it confuses | The answer switch is on by default and never names the keys. Those keys use Control and Option, the same modifiers as Talk to Zeus, so a chord that answers a card is also a spoiled talk hold. The agent picker is described in the catalog as arrows, Return, and Esc, and the row the person sees is only the popup. |
| Fix | Put the three chords on the answer row, and say they are live only while a card is waiting. Put "arrows, Return, Esc" on the agent-picker row. |
| Owner | integration, Shortcuts |

### S05-11

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Dictation check card `Sources/Zeus/Dictation/DictationPreviewCard.swift:7-8`, `:41-46`, and `:67-71` (Return inserts, Escape drops, and the card becomes key). Meeting card `Sources/Zeus/Scribe/ScribeMeetingCardView.swift:370` and `:388` (Return is the primary action, Escape cancels). `Sources/Zeus/Scribe/ScribeMeetingCardPanel.swift:42-46` (the card can become key after a click) |
| Why it confuses | Both cards teach Return and Escape as their own keys. Whichever card was clicked last takes the key. A meeting card on screen during a dictation check means Return can join or start the meeting instead of writing the dictated text, or the reverse after the check card is focused. |
| Fix | While the dictation check card is up, it should own Return and Escape. The meeting card should ignore those keys until the check card is gone, and say so if both are visible. |
| Owner | integration, Scribe and Murmur |

### S05-12

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. One saved voice deletes immediately at `Sources/Zeus/Settings/GSSpeakerRecognitionCard.swift:29`. Delete all on the same card confirms at `:126-134`. A paired Mac's key is removed at `Sources/Zeus/Settings/GSShelfPage.swift:77-82` with the warning under the list. Trusted chats clear at `Sources/Zeus/Settings/GSAgentHubCards.swift:130-132`, and the same row says the list is cleared when Zeus quits |
| Why it confuses | Delete all asks. Delete one voice does not, on the same card. Removing a paired Mac deletes the key in one click. "Clear all" on trusted chats is immediate, and the sentence above it says the trust already ends when Zeus quits, so "allowed" does not last in the way the button implies. |
| Fix | Use the Delete all confirm for one voice. Confirm before a paired Mac's key is deleted. Say that trusted chats last until quit, and confirm Clear all. |
| Owner | integration, settings |

### S05-13

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. `Sources/Zeus/Scribe/ScribeController.swift:1713` ("Couldn't save …" plus `error.localizedDescription`). `Sources/Zeus/Dictation/DictationController.swift:1255` ("Couldn't read the file here:" plus `error.localizedDescription`). The same pattern is on the notes line at `ScribeController.swift:1052` and the engine status at `Sources/Zeus/Dictation/DictationController.swift:962` |
| Why it confuses | A failed save or a failed file read shows the system error string, which can be a framework name, a code, or a path. The person gets no next step. Scribe already has a plain sentence for a microphone that is off (`Sources/Zeus/Scribe/ScribeIdleView.swift:67-69`). These failures do not match it. |
| Fix | Map known failures to one sentence and a button (try again, open Settings). Keep the system string in the diagnostics log. |
| Owner | integration, Scribe and Murmur |

### S05-14

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. General `Sources/Zeus/Settings/GlanceSettingsPages.swift:117` ("Show in screen sharing"). Appearance `GlanceSettingsPages.swift:263-266` ("Show Zeus in screen shares"). Both bind `general.showInScreenSharing` (`Sources/ZeusCore/ScreenShare/ZeusScreenSharePolicy.swift:5`). The menu-bar panel repeats the Appearance title at `Sources/Zeus/App/PanelView.swift:107-108` |
| Why it confuses | One switch appears twice, under two titles and two sentences. General talks about windows, shares, and recordings. Appearance talks about people, screenshots, and meetings. Flipping either one flips the other. The policy ignores whether a meeting is active (`ZeusScreenSharePolicy.swift:24-26`), so the Appearance sentence about meetings describes a case the code does not treat as special. |
| Fix | One row, one title, on one page, and a menu item that uses that title. Say that a meeting does not change the switch. |
| Owner | integration, settings. #22 `ff33ee3d9ea7` rewords the Appearance sentence and leaves both rows in place |

### S05-15

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Sidebar `Sources/Zeus/Settings/GlanceSettingsWindow.swift:67` ("Insomnia") and `:76` (the keyboard-sharing section title is a third-party product name). Details `Sources/Zeus/Settings/GSInsomniaPage.swift:39` names `pmset`, a launchd agent, and the sudoers path. Remove at `:30` has no confirm. A hover on `:77` shows the app's bundle id. The notch has an Insomnia tab at `Sources/ZeusCore/TopBar/TopBarLayout.swift:33` |
| Why it confuses | "Insomnia" does not say "keep working with the lid closed", which the page subtitle does. The details row is an admin recipe. Remove uninstalls that rule in one click. The bundle id is an internal identifier on a row whose title is the app's name. The keyboard-sharing section is titled with another product's name. |
| Fix | Title the section with the subtitle's words. Move the command list to Diagnostics. Confirm Remove. Show the app name in the hover, and title the keyboard-sharing section for what it does. |
| Owner | integration, settings |

### S05-16

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. `Sources/Zeus/Settings/GSPolyglotPage.swift:15-18`, `:51-57`, and `:67-71`. Enabled by default at `Sources/Zeus/Polyglot/PolyglotSettings.swift:30`. The hint tells the person to say "Hey Zeus, translate" or "start Polyglot". Wake is off until turned on (`Sources/Zeus/App/SettingsCatalog.swift:176`) |
| Why it confuses | The feature's only name in the sidebar, the button, and the spoken command is Polyglot. The hint offers a wake phrase that does nothing until Hey Zeus is turned on, on another page. If a second app with the same name is installed, the page offers to open it from inside the Zeus page that already does live captions. |
| Fix | Name the page for live captions, and keep Polyglot as a spoken alias if it must stay. Point the hint at the switch on this page. Say that the other app is separate, and what opening it will do. |
| Owner | integration, Polyglot |

### S05-17

| | |
| --- | --- |
| Severity | P2 |
| Where | #67 `zeus-bot/hub-05-screen` `8babfef2818d`. `Sources/ZeusCore/AgentHub/HubTypes.swift:71-81` (loading is "Announced"; the five words are Running, Waiting for input, Needs approval, Done, Error). Empty copy at `:145-162` ("Nothing running", "Start a chat and it shows up here.", button "New chat"). Notch cards on integration `Sources/Zeus/Agents/AgentCardsUI.swift:403-415` (Done, Needs you, Question, Failed, Quiet). The Appearance preview draws "Working" at `Sources/Zeus/Settings/GlanceSettingsPages.swift:1416-1418` |
| Why it confuses | The same agent moment has a different word on the notch card, in the hub, and in the settings preview of a running card. "Announced" is not a state a person can act on. The hub empty state says "chat" and the group header says "sessions". |
| Fix | Use the notch words in the hub (Needs you, Question, Failed, Quiet, Done). Replace "Announced" with "Starting" or the loading sentence already used for the screen ("Connecting…"). Use one noun for a session. |
| Owner | #67, hub. The preview word is integration, Appearance |

### S05-18

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Murmure switch `Sources/Zeus/Settings/GlanceSettingsPages.swift:984-985` (`dictation.sounds`). It is read only at `Sources/Zeus/Dictation/DictationController.swift:1129-1131`. The player also requires the Sounds master at `Sources/Zeus/Dictation/DictationCuePlayer.swift:18-22`. The Dictation page style picker is `Sources/Zeus/Settings/GSDictationPage.swift:145-155`. Its preview uses `force` and ignores both switches (`DictationCuePlayer.swift:14` and `:41-43`). The catalog files `dictation.sounds` under Sounds (`SettingsCatalog.swift:100`). `docs/settings-inventory.md` line 154 calls it the same switch as Sounds |
| Why it confuses | Three controls govern one chime, on three pages, with three labels. Turning off "Play dictation sounds" leaves the Dictation page showing a style, and Play on that page still makes the sound. Turning off Sound feedback on the Sounds page also silences dictation, and that page does not mention dictation. The inventory says the Murmure switch and the Sounds switch are the same control. They are not. |
| Fix | One switch and one style, on the Dictation page. The Sounds master can still mute everything, and it should say that it includes dictation. Preview should stay quiet when the switch is off, or say that it is a preview. |
| Owner | integration, Murmur and Sounds |

### S05-19

| | |
| --- | --- |
| Severity | P2 |
| Where | #22 `zeus-bot/settings-plain` `ff33ee3d9ea7`. `Sources/Zeus/Settings/GlanceSettingsPages.swift:1354-1358`. On integration the same row is `GlanceSettingsPages.swift:1354-1357` and still says any program on this Mac running as the person can invoke the command |
| Why it confuses | The row is "Allow command-line control of sensitive actions". On this head the sentence is only that the zeus command can use the microphone, record, type, and click. The integration sentence also says any program on this Mac running as the person can invoke that command. #22 drops that clause and does not put it in the detail line. The switch looks narrower than the control. |
| Fix | Keep one short sentence, and keep the "any program running as you" clause in the detail that this copy pass already uses for the other rows. |
| Owner | #22, settings |

### S05-20

| | |
| --- | --- |
| Severity | P2 |
| Where | integration `2722dcb7`. Settings card title `Sources/Zeus/Settings/GSShelfPage.swift:14-16` ("Fling", while the switch says "Send and receive with nearby Macs"). Menu `Sources/Zeus/Stickies/ShelfBrainMenu.swift:15` ("Fling to") |
| Why it confuses | The switch is a plain description. The card and the Shelf menu use Fling, which is not explained on the row. A person who turned the switch on does not see that word again until the menu. |
| Fix | Use the switch's words on the card and in the menu, or define Fling once in the card title and use it everywhere, including the switch. |
| Owner | integration, Shelf settings |

## Already in the ledger

These match the lens and stay on their ledger ids. They are not new S05 rows.

| Ledger | Why it is this lens | Owner |
| --- | --- | --- |
| ZB-026 | Home Play stays on "Nothing playing" and does not say the player is not running. `Sources/Zeus/TopBar/HomeWidgetViews.swift:86-87` and `:97` | #56 |
| ZB-003 | Settings describe click, hold, and swipe routes the top bar never sends | #42 |
| ZB-017 | The visible title says "Typing" while the accessibility label still says "Start dictation" | #57 |
| ZB-028 | A hub session can sit on Loading with no failure and no stall | #62 |
| ZB-031 | A hub reply waiting for approval has no cancel, so a missing card leaves the draft stuck | #70 |
| ZB-032 | A connection error stays on screen after New chat | #67 |

## Counts

| | P1 | P2 | P3 | Total |
| --- | ---: | ---: | ---: | ---: |
| New (S05-01 through S05-20) | 4 | 16 | 0 | 20 |
| Ledger matches, not re-filed | | | | 6 |

S05-01 is on #81. S05-17 is on #67. S05-19 is on #22. S05-06 cites both integration and #22. The other new rows are on integration `2722dcb7`.
