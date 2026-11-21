# Sweep 03 — Security and privacy

Lens: secrets at rest and in logs, Keychain access control, socket and peer checks, file modes, path traversal, process launch, update integrity, approval timeout, entitlements, transport of credentials, provider consent, and biometric templates.

This file is the only change on `zeus-bot/sweep-03-security`. No production code, tests, CI, `Package.swift`, or `qa/feature-map.json` edits.

## Scope that was read

| Head | SHA | Role |
| --- | --- | --- |
| `codex/integration-20261111` | `2722dcb7497d5415fbc1fcb1f65c49629966a281` | Integration tree. Line numbers below are this commit unless a row names another SHA. |
| `zeus-bot/bug-ledger` (#54) | `255e52aba94234e2b194fd81b2cf4b93e628cc93` | Ledger `specs/bugs/ledger.md`, read before any row was written. |
| `zeus-bot/voice-providers` (#53) | `16c2d697dcd479f6cbe510ad65fda731b82194fa` | Provider Keychain and HTTP. |
| `zeus-bot/fix-license` (#58) | `10faecc83b32849db0a712f69e807c9317d51a96` | License commit and revocation. |
| `zeus-bot/fix-core-ipc-version` (#60) | `4750e01fb9e3e62fe690c2546809abc6c9a6e8cd` | Peer credentials and version parse. |
| `zeus-bot/hub-03-transcript` (#64) | `0e4111c3abf5c906db5b7aef213f1bb13cebd2cf` | Hub transcript files. |
| `zeus-bot/hub-04-decision` (#70) | `7c000d3a8d5882593e3a1bf34afd98ae4b3be2f6` | Approval and reply gate. |
| `zeus-bot/settings-faceid` (#48) | `daa3f87a660fae97d9187d9aec99a4303bf6e82c` | Face verification and templates. |
| `zeus-bot/settings-autoupdate` (#49) | `4ada39309d863dcc63b35241f3d77392d4ff2fcb` | Signed updater. |
| `zeus-bot/settings-weather` (#42) | `d0a9000861a61850e8ae396c01b142cce6343748` | Weather location. |
| `zeus-bot/companion-persona-orb` (#52) | `665b9167303f9596d5222b77a663e36f780d60d7` | Persona selection. |
| `zeus-bot/glass-settings-shell` (#33) | `d8fb8c2df661c9627cd8d9698fe669141d310b63` | Settings shell. |
| `zeus-bot/privacy-motion-hygiene` (#23) | `c876b17d7e86149b35d3651e8befc6bcddefedc9` | Unmerged command-log draft. Not a required head. Read because it touches the log finding. |

## How a finding was established

Every row is a static reading of that commit. This VM is Linux and has no Keychain, no signed app, and no provider network. The sketches are failing tests to add later. They were not executed here. A row marked `duplicate of ZB-xxx` is the same defect already in `specs/bugs/ledger.md` on #54. Rows that an older ledger SHA described, and that the current head of that PR has since closed, are listed under "Checked and not reopened" and are not counted.

Severity uses the ledger scale. P1 is a credential, transcript, or approval control that fails open for a same-user program or a redirected request. P2 is a missing lock, mode, or consent that still needs a further condition. P3 is defense in depth on a path the owner already keeps private.

## Findings

| ID | Severity | Branch / SHA | File:line | Repro or failing-test sketch | Established | Owning PR or area |
| --- | --- | --- | --- | --- | --- | --- |
| S03-01 | P1 | integration `2722dcb7` | `Sources/ZeusCore/AgentHubRules.swift:185-188`; `Sources/ZeusCore/Terminal/ShellRisk.swift:7-9` and `:231` | Trust session `s`. Ask `autoApproves` for tool `Bash`, risk `.low`, command `python3 -c 'open("/tmp/zeus-sweep","w").close()'`. `ShellRisk` is `.unfamiliar`. The trust check returns true when risk is below `.network`, and `.unfamiliar` is below `.network`. The same is true for `bash -c`, `osascript -e`, `node -e`, `find -exec`, and `cp`. `AgentEventServer` then encodes an allow with no card (`AgentEventServer.swift:104-108`). | Static. Order of `ShellRisk` and the comparison were read together. | Agent approvals. Area of #14. |
| S03-02 | P1 | integration `2722dcb7` | `Sources/ZeusCore/CLIGate.swift:17-24`; `Sources/Zeus/App/CommandCenter.swift:237-249` and `:276-280`; `Sources/Zeus/App/VoiceTurnController.swift:824-835` and `:870-877` | With the command-line switch off, a same-user client sends `{"kind":"zeus.command","op":"ask","text":"what do you remember about me"}`. `isSensitive` is false for `.ask` and `.research`, so admission allows the line. The turn runs restricted, which blocks action tags, and still builds `BrainRequest` with `history` and the memory block. `.research` still launches the signed-in web engine. The reply goes back on the socket. | Static. The gate set, the two command cases, and the request fields were read in one pass. | Privacy / command socket. |
| S03-03 | P1 | integration `2722dcb7` | `Sources/ZeusCore/Hands/HandsGate.swift:249-271` | `HandsCommandLog.record("curl -H 'xi-api-key: example-secret' https://example.invalid", …)` then `write` to a fresh directory with umask `022`. The file contains `example-secret`. Mode is `0644`. `createDirectory` sets no mode. `CodeActions` and `AgentEventServer` append real shell lines through this type. | Static. The format string and `Data.write` were read. #23 drafts command redaction and mode `0600` and is not on this commit. On #23 the outcome column is still the raw card text. | Hands log. Draft on #23, not in the ledger. |
| S03-04 | P1 | integration `2722dcb7` | `Sources/Zeus/Voice/VoiceLog.swift:40-46` and `:63-67`; `Sources/Zeus/App/VoiceTurnController.swift:472` | Write `voice.logContent` true in the app's preferences domain, then finish one talk turn. `contentLoggingEnabled` reads that Boolean on every call. `logContent` records the transcript, and `log` mirrors it with `NSLog`. The project already treats a preferences write as enough to flip a privacy switch (`CLIGateStore.swift:56-57`) and moved the command-line switch into the Keychain for that reason. This switch stayed in preferences. | Static. The read site and the transcript call site were read. The preferences write was not performed on this VM. | Voice diagnostics. |
| S03-05 | P1 | integration `2722dcb7` | `Sources/Zeus/Brain/BrainWarmScheduler.swift:9-16` and `:20-32`; `Sources/Zeus/Brain/Providers/AnthropicAPIProvider.swift:33-37`; `Sources/Zeus/Voice/TTSHTTP.swift:8-15` and `:34-36`; `Sources/Zeus/Voice/Speaker.swift:27-28` | Point the messages host at a test server that answers `302` to a second host. The shared brain session's delegate implements metrics only, so the session follows the redirect and the `x-api-key` header is a custom header on the proposed request. The voice sessions from `TTSHTTP.makeSession()` have no delegate. Their warm requests set `xi-api-key` and `Authorization`. `ExplanationNoRedirects` (`ExplanationProvider.swift:187-191`) already refuses this for the explanation client. | Static. Delegate methods and header assignments were read. No live redirect was sent. | Brain and voice HTTP. Distinct from ZB-007, which is the provider transport on an older #53 SHA. |
| S03-06 | P2 | integration `2722dcb7` | `Sources/ZeusCore/Keychain/SystemKeychain.swift:96-109`; `Sources/ZeusCore/CLIGate.swift:63-70`; `Sources/Zeus/FacePresence/FaceVaultStore.swift:11` and `:57-58` | Create a generic password under service `com.zeus.app` and read `kSecAttrAccessible`. The add sets `kSecAttrAccessibleAfterFirstUnlock` and sets no `kSecAttrAccessControl`. The value is eligible to sync and to migrate with a backup, and it stays in the after-first-unlock class while the screen is locked. The face-template key `face.presence.vaultKey` is stored through this path. `CLIGateStore` already records that a same-user item planted with an open access list may be read back as the command-line switch. The update dictionary at line 99 changes only `kSecValueData`, so a planted item keeps its access list. | Static. The add and update dictionaries were read. Keychain was not called. The planted-item half is the comment's own open assumption, so that half is not treated as executed. | Keychain. Area of #53's older store, and face presence. |
| S03-07 | P2 | #53 `16c2d697` | `Sources/ZeusCore/Providers/CredentialStore.swift:64-74` | Update an existing provider item, then copy its attributes. `SecItemUpdate` writes `kSecValueData` only. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is set on add, and there is still no access-control object and no user-presence flag. A pre-created item keeps the class and the access list it was created with. | Static on that SHA. | #53 providers. |
| S03-08 | P2 | #48 `daa3f87a` | `Sources/ZeusCore/Settings/Sections/FaceID/FaceTemplatePolicy.swift:49-51`; `Sources/Zeus/FacePresence/FacePresenceController.swift:181` and `:396` | Enroll one face through `FacePresenceController`. The save calls `FaceVaultStore.save`. A search of `Sources/` on this SHA finds `FaceTemplatePolicy.seal` only in tests. That function refuses a key whose protection is not `keychainUserPresence` and refuses an image or thumbnail. The live enroll path never asks it, and the vault key remains the ordinary Keychain item from S03-06. | Static. Call sites of `seal` and of `vault.save` were listed. | #48 face verification. |
| S03-09 | P2 | integration `2722dcb7` | `Sources/Zeus/Agents/AgentEventServer.swift:118-128`; `Sources/ZeusCore/HookEnvelope.swift:76-81`; `Sources/zeus-hook/main.swift:55-61` | Deliver a `PermissionRequest` whose command is `rm -rf` and wait out the 100 second timeout. The server always passes `onTimeout: .ask`. `.ask` makes `claudePermissionRequestOutput()` return nil, and the hook writes nothing. The card text says the terminal will ask. A high-risk command uses the same timeout result as a low-risk one. Hub decision #70 does deny on timeout (`HubDecision.swift:23-24`). This socket path does not. | Static. The timeout argument, the nil output, and the hook's write were read. The 100 second wait was not run. | Agent hook approvals. Distinct from ZB-015, which is the uncancelled timeout task. |
| S03-10 | P2 | integration `2722dcb7` | `Sources/ZeusCore/Updates/UpdateAvailability.swift:85-92`, `:119-121`, and `:144-148`; `Sources/Zeus/App/UpdateCoordinator.swift:103-125` | Serve an HTTPS feed that redirects to a second HTTPS host whose JSON has a new version and a download URL. `HTTPSOnlyRedirects` accepts any HTTPS URL. `offer(from:)` trusts `version` and `downloadURL` with no signature. `UpdateCoordinator.performUpdate` opens that URL. Separately, set preferences key `debug.updateFakeVersion` to `0.0.1` while the running version is newer. `badgeState` replaces the feed offer with the fake, so a real offer is hidden. The debug command that writes the key is not in `CLIGate.sensitiveDebug`. | Static. Redirect predicate, JSON parse, badge precedence, and the debug writer were read. No feed was fetched. | Update badge. Distinct from ZB-008, which is the version parser. |
| S03-11 | P2 | integration `2722dcb7` | `Sources/ZeusCore/FeatureSettings.swift:42-48`; `Sources/Zeus/App/SettingsCatalog.swift:180`; `Sources/ZeusCore/Present/TalkSight.swift:72-80` | Fresh preferences. `talkSeeScreen()` is true. `talkDrawOnScreen()` is false, and `pointingSendScreenshot()` is false. A talk turn with Screen Recording granted and `seeScreen` true puts each display's image on the brain request (`TalkSightPolicy.plan`). No onboarding file references `talk.seeScreen`. The catalog test currently expects the default to be on, so a fix changes that test as well as the default. | Static. The three defaults and the request-shot rule were read. | Talk privacy. |
| S03-12 | P2 | integration `2722dcb7` | `Sources/ZeusCore/Diagnostics/FlightRecorder.swift:19-40` and `:127`; `Sources/Zeus/Settings/GSDiagnosticsLogs.swift:36-38` | `DiagnosticsRedactor.redact("https://user:example-secret@updates.example/feed")` still contains `example-secret`. The patterns cover named assignments, bearer tokens, a few key prefixes, JWTs, and 32 hex characters. A URL userinfo password matches none of those. Export sets `secretsRedacted` true. The export also omits `hands-commands.log` (S03-03), so that file stays on disk in the clear. | Static. Patterns and the manifest flag were read. The redact call was not executed. | Diagnostics export. |
| S03-13 | P2 | integration `2722dcb7` | `Sources/Zeus/TopBar/TopBarServices.swift:390-400` and `:427-431` | Leave the weather city empty. `fetchWeather` fills it from the current time zone and sends that name to the geocoding URL, then sends the returned coordinates to the forecast URL, both through `URLSession.shared`. That session follows redirects, including off the original host, and the coordinates are query items. #42's precise-location machine stays off until the owner turns it on and does not write coordinates into preferences. This top-bar path is separate and already on integration. | Static. The default city, both calls, and the shared session were read. | Weather. #42 does not replace this caller. |
| S03-14 | P3 | integration `2722dcb7` | `Sources/ZeusCore/UnixSocket.swift:239` and `:254` | Start the server with `ZEUS_SUPPORT_DIR` pointed at a new directory and umask `022`. The socket file is `0600`. The parent directory is created with no mode, so it is `0755`. A later log or transcript placed there with the process umask is then traversable by anyone who can reach that directory. | Static. `createDirectory` attributes and the following `chmod` of the socket were read. | IPC socket directory. |
| S03-15 | P3 | integration `2722dcb7` | `Sources/ZeusCore/Keychain/SystemKeychain.swift:30-35`; `Sources/Zeus/App/AssistantKeyImporter.swift:21-24` | Make the dev-keychain password file mode `0644` and launch a local build. `DevKeychain` reads the first readable password file and unlocks the keychain. `AssistantKeyImporter.insecureReason` refuses a key file whose mode includes `0o077`. The password reader has no equivalent check. | Static. The read condition and the importer check were compared. The file was not created. | Local-build Keychain. |
| S03-16 | P2 | #64 `0e4111c3` | `Sources/ZeusCore/AgentHub/HubTranscript.swift:192-195` | duplicate of ZB-030. Write one transcript into a fresh directory and `stat` the file. `createDirectory` and `Data.write` use the process umask. | Re-read of the same lines the ledger cites. | #64. Ledger owner. |
| S03-17 | P1 | integration `2722dcb7` | `Sources/ZeusCore/PeerCredentials.swift:112-113` | duplicate of ZB-004. On this commit the non-Darwin branch of `identify` returns nil, and `decide` denies a nil peer. #60 `4750e01f` reads `SO_PEERCRED`. The integration commit does not. | Re-read. The #60 replacement was also read. | #60. Ledger owner. |
| S03-18 | P2 | integration `2722dcb7` | `Sources/ZeusCore/Updates/UpdateAvailability.swift:15-22` | duplicate of ZB-008. `ZeusVersion(parsing: "2.0.0-rc1")` keeps the numeric prefix and stores patch 0. #60 replaces this parser. | Re-read. | #60. Ledger owner. |
| S03-19 | P2 | integration `2722dcb7` | `Sources/Zeus/App/LicenseManager.swift:163-165` and `:181-183` | duplicate of ZB-024. Activation stores the proof before the key. A failed key write leaves the proof. #58 adds a commit that rolls the proof back. | Re-read. | #58. Ledger owner. |
| S03-20 | P2 | integration `2722dcb7` | `Sources/ZeusCore/License/LicenseEngine.swift:69-72` | duplicate of ZB-025. A missing or undecodable revocation list returns not revoked. #58 adds `LicenseRevocationPolicy`, which keeps a key that is already on the last good list revoked. | Re-read. | #58. Ledger owner. |

## Counts

New rows are S03-01 through S03-15. Duplicates are S03-16 through S03-20.

| Set | P1 | P2 | P3 | Total |
| --- | ---: | ---: | ---: | ---: |
| New | 5 | 8 | 2 | 15 |
| Duplicate of a ZB row | 1 | 4 | 0 | 5 |
| All rows | 6 | 12 | 2 | 20 |

No P0 row. The face lockout bypass ZB-001 is closed on the current #48 head, so it is not in this table.

## Fix clusters

New rows only. Each cluster's files are disjoint from the other clusters. Duplicate rows stay with the PR named in the ledger.

| Cluster | IDs | Files | Base |
| --- | --- | --- | --- |
| Trusted shell | S03-01 | `Sources/ZeusCore/AgentHubRules.swift` | integration `2722dcb7` |
| Restricted brain calls | S03-02 | `Sources/ZeusCore/CLIGate.swift`, `Sources/Zeus/App/CommandCenter.swift`, `Sources/Zeus/App/VoiceTurnController.swift` | integration `2722dcb7` |
| Command log | S03-03 | `Sources/ZeusCore/Hands/HandsGate.swift` | integration `2722dcb7`. #23 is a partial draft. |
| Transcript switch | S03-04 | `Sources/Zeus/Voice/VoiceLog.swift` | integration `2722dcb7` |
| Credential redirects | S03-05 | `Sources/Zeus/Brain/BrainWarmScheduler.swift`, `Sources/Zeus/Voice/TTSHTTP.swift` | integration `2722dcb7` |
| Keychain class and password file | S03-06, S03-15 | `Sources/ZeusCore/Keychain/SystemKeychain.swift` | integration `2722dcb7` |
| Provider item update | S03-07 | `Sources/ZeusCore/Providers/CredentialStore.swift` | #53 `16c2d697` |
| Face enroll path | S03-08 | `Sources/Zeus/FacePresence/FacePresenceController.swift` | #48 `daa3f87a` |
| High-risk timeout | S03-09 | `Sources/Zeus/Agents/AgentEventServer.swift` | integration `2722dcb7` |
| Update badge | S03-10 | `Sources/ZeusCore/Updates/UpdateAvailability.swift`, `Sources/Zeus/App/UpdateCoordinator.swift` | integration `2722dcb7` |
| Screen default | S03-11 | `Sources/ZeusCore/FeatureSettings.swift`, `Sources/Zeus/App/SettingsCatalog.swift` | integration `2722dcb7` |
| Diagnostic redaction | S03-12 | `Sources/ZeusCore/Diagnostics/FlightRecorder.swift` | integration `2722dcb7` |
| Weather fetch | S03-13 | `Sources/Zeus/TopBar/TopBarServices.swift` | integration `2722dcb7` |
| Socket directory | S03-14 | `Sources/ZeusCore/UnixSocket.swift` | integration `2722dcb7` |

## Checked and not reopened

- ZB-001 on #48 `daa3f87a`: `fallbackResult` returns no grant while `phase == .lockedOut` or `lockActive` (`FaceVerificationMachine.swift` fallback case). The ledger's repro was the older SHA `1ba23ae6`.
- ZB-005 and ZB-006 on #49 `4ada3930`: `UpdateVerification.allows` accepts only `.valid`. `sparkleReadyToInstall` posts `UpdateVerification.verdict(status: lastTrust)` after `accepts` has stored that status. Install still goes through `confirmInstall`.
- ZB-007 on #53 `16c2d697`: `ProviderHTTPRedirect.forwarded` returns nil, and both `send` and `stream` install that delegate. The ledger's repro was SHA `30253774`.
- #70 `7c000d3a`: approval timeout and deny both produce `.deny`. Trust is not read on the reply gate. There is still no cancel from `.awaitingDecision` (ZB-031). That is a stuck draft, not an approval.
- #58 `10faecc8` and #60 `4750e01f` contain the fixes ZB-024, ZB-025, ZB-004, and ZB-008 ask for. Those four stay open on integration until those heads land, which is why they are duplicated above.
- #42 `d0a90008`: precise location starts off, the system prompt is the only prompt effect, and the disk writer removes `perm.location` and does not store coordinates.
- #33 `d8fb8c2d` and #52 `665b9167`: the shell is a registry of sections. Persona selection stores an id in preferences. Neither adds a credential, a socket, or an approval path.
- Scribe meetings and the wiki already create a `0700` directory and `0600` files. Wiki ids are limited to letters, digits, and `._-` with a safe first character. Hub transcripts are the exception, and that exception is ZB-030.
- `Process` launches that take a shell string were read. The watch runner executes one constant. The permission restart passes the pid and the bundle path as positional parameters, not as interpolated shell text. Terminal tab scripts drop any tty or session id outside a short safe alphabet.
- Entitlements: `Resources/Zeus.entitlements` sets the app sandbox off, so the camera, microphone, network, and automation keys do not confine the unsandboxed app. Usage strings for microphone, camera, speech, calendars, reminders, location, and automation are present. `scripts/bundle.sh` signs the app and the helpers with the hardened runtime. No source or doc claims certificate pinning. The explanation client, the update feed, and the provider transport on the current #53 head refuse redirects. The brain and voice sessions in S03-05 do not.
- No crash-upload client is referenced. Diagnostics stay local, with the redaction gap in S03-12.
