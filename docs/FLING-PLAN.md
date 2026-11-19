# Fling: implementation plan

Status: plan only, nothing built. Base: worktree from `codex/island-look-20261115` (head 5e0a143); branch `codex/fling-20261115`. Every slice follows the Code Factory Procedure: fail-first test commit, then the implementation commit, gates, independent review, then Vera PASS at the head SHA before any merge. Tony merges.

Owner decisions applied (2026-11-15): name Fling. Transport is Network.framework with Bonjour `_zeus-fling._tcp` and peer-to-peer on. Pairing: the receiver accepts and both Macs show the same 6-digit code. TLS uses a pre-shared key (PSK) made at pairing and kept in Keychain under service `com.zeus.app`. Paired Macs are auto-accepted. Arrivals save to `~/Downloads/Fling`. Clipboard mode ships in v1. Floating papers are built but off by default. Aimed landing is v2. Flick sensitivity is Low, Normal or High. Limits: 100 items per send, warn over 2 GB. Each file gets a SHA-256 check and becomes visible only after a match. iPhone gets files through AirDrop only. Free. Fling Shelf items persist across relaunch. Settings get a Shelf section with a Fling group. Background receive is on. Fling arrivals get their own `lights.fling` glow.

Not in v1: resume after a dropped connection (a failed send shows "Failed, tap to retry" and resends the whole stack only on a new click), aimed landing, and anything on the phone side.

## 1. Verified facts (zeus-look @ 5e0a143)

| Fact | Where |
|---|---|
| `struct ShelfItem: Identifiable, Equatable { let id = UUID(); var url }` | `Sources/Zeus/TopBar/TopBarModel.swift:36-43` |
| `shelfTargeted` | `TopBarModel.swift:104` |
| `var shelf: [ShelfItem] = []`, kept in memory only | `TopBarModel.swift:157` |
| `lightOption(for cue:)`: `.shelfAdded -> "lights.shelf"` | `TopBarModel.swift:418-430` |
| `lightOption(for kind:)`: `.landed(airDrop)` picks `lights.airDrop` or `lights.shelf` | `TopBarModel.swift:563-575` |
| `addToShelf(_:isAirDrop:)` removes duplicate URLs, inserts at 0, then `show(.shelfAdded)` and `flash(.landed)`; `removeFromShelf` | `TopBarModel.swift:584-592` |
| `ShelfPage` (drop zone plus horizontal grid; `.onDrop(of: [.fileURL])` calls `addToShelf`) | `Sources/Zeus/TopBar/TopBarViews.swift:1084-1121` |
| `ShelfCell` (hover AirDrop through `NSSharingService(named: .sendViaAirDrop)`, Transcribe, Remove; `.onDrag` gives a file provider) | `TopBarViews.swift:1123-1150` (AirDrop at 1135) |
| Shelf tab badge count | `TopBarViews.swift:378` |
| `.shelfAdded` cue rendering | `TopBarViews.swift:1540, 1582` |
| `TopBarTab.shelf` | `Sources/ZeusCore/TopBar/TopBarLayout.swift:5, 24, 65` |
| `NotchCue.shelfAdded(Int)` | `TopBarLayout.swift:254` |
| `NotchLightKind.landed(airDrop:)`: duration at 29, geometry at 141 | `Sources/ZeusCore/TopBar/NotchLights.swift:11` |
| Landed light tint | `Sources/Zeus/Notch/NotchLights.swift:161` |
| `updateIntakeWatcher()` builds `AirDropScreenshotWatcher` and calls `addToShelf(isAirDrop:)` | `Sources/Zeus/TopBar/TopBarServices.swift:433-458` |
| The watcher's FSEvents stream is recursive, but it only reports files whose parent folder is exactly `~/Downloads` and whose quarantine says AirDrop; dot-files are skipped. So `~/Downloads/Fling/...` is already ignored by accident. The plan makes that skip explicit and tested. | `Sources/Zeus/TopBar/AirDropScreenshotWatcher.swift:97-125` |
| A file drag near the notch already switches to `.shelf` and opens the panel. **No NotchController change is needed.** | `Sources/Zeus/Notch/NotchController.swift:478-495` |
| `ShelfBrainMenu(url:)` offers Save to Brain and Make Sticky | `Sources/Zeus/Stickies/ShelfBrainMenu.swift:7-17` |
| Catalog is generated from `scripts/gen-settings-catalog.py` (row tuple at line 8, `o(...)`, `SECTION_TITLES` at 255, opt-in guard `validate_table` at 259) | `Sources/Zeus/App/SettingsCatalog.swift:1` |
| Light catalog rows | `SettingsCatalog.swift:62, 78, 79` |
| Freshness and missing-id check | `scripts/check-settings-catalog.sh` |
| `SettingOption.section` is a `SettingsNavigation.Section` (`Sources/Zeus/App/SettingsStore.swift:19`); that enum is at `Sources/Zeus/App/SettingsView.swift:10`, page switch at 260-290 (tiling uses `EmptyView()`) | as stated |
| The live sidebar is a second enum, `GSSection`, in groups settings, tools and app | `Sources/Zeus/Settings/GlanceSettingsWindow.swift:7-23` |
| Page dispatch | `Sources/Zeus/Settings/GlanceSettingsPages.swift:40-70` |
| Section id and alias lists | `Sources/ZeusCore/Settings/GlanceSettingsSnapshotMapping.swift:18, 47` |
| Existing light rows | `GlanceSettingsPages.swift:359`, AirDrop row 1368-1380, screenshot row 1400-1412 |
| Tests that iterate `GSSection`: `R24AppTests` and `QA22SettingsTests` (shown count = all minus iPhone) | `Tests/ZeusAppTests/` |
| `Resources/Info.plist` has no `NSLocalNetworkUsageDescription` and no `NSBonjourServices`. The plist test pattern is `Tests/ZeusCoreTests/AutomationUsageStringTests.swift:9-16`. | as stated |
| Entitlements: app-sandbox false, network.client true. No new entitlement needed while unsandboxed. | `Resources/Zeus.entitlements` |
| `KeychainStore` (service `com.zeus.app`, `get/set/remove`, String values) and `MemoryKeychain` for tests | `Sources/ZeusCore/Keychain/KeychainStore.swift:24-25, 85-118, 122` |
| `SystemKeychain` uses the `zeus-dev` keychain on local builds | `SystemKeychain.swift:7-54` |
| App instance `Keychain.store` | `Sources/Zeus/App/Licensing.swift:9-10` |
| Downloads access uses `FolderAccess.status/request(for: .downloads)` and only asks when a feature is enabled | `Sources/Zeus/App/FolderAccess.swift:5-73` |
| No Network.framework code exists in the repo today | grep |
| ZeusCore already imports CryptoKit | e.g. `Sources/ZeusCore/PeerSigning.swift` |
| `zeus-native-test-host` is a test-only executable at `qa/native-app-host`. `scripts/bundle.sh:43-45` copies only Zeus, zeus-hook, zeus-bridge and zeus-cli, so a new helper never ships. | as stated |
| CI runs `swift build`, then `qa/closed-loop/ci_motion_profile.py` -> `native.py`. That selects checks of kind `native-*` from `qa/feature-map.json` `checks`; a `native-fixture` row needs `suite` and `file`. | `.github/workflows/build.yml:73-89` |
| Highest REG on every local branch is REG-656 (REG-700 is used by another lane). **Reserve REG-660..699.** Highest feature id on every local branch is F14. | `qa/regressions.json` |

Unknowns, each planned around:

- **U1. TLS-PSK on Network.framework.** Unverified: whether `sec_protocol_options_add_pre_shared_key` plus a server-side selection block works on macOS 14.2, and whether TLS 1.3 external PSK is accepted or only TLS 1.2 PSK suites. Slice S0 settles it.
- **U2. Loopback and the Local Network prompt.** Unverified: whether loopback connections are exempt from the prompt and whether Bonjour works on a hosted CI runner. CI therefore uses direct loopback addresses only.
- **U3. Building the helper during tests.** Unverified: whether `swift test` builds an executable that no test target depends on. Plan: `scripts/test.sh` runs `swift build --product zeus-fling-peer` first, and CI already runs `swift build`. The test fails loudly if the binary is missing.
- **U4. Synthetic drags.** Unverified: whether `OwnedWindowEventDriver` can drive a real SwiftUI drag session. Fallback: hit-test by layout, then call the production drop delegate with a real `NSItemProvider`.
- **U5. Next free feature id.** Use F15 if it is still free on the integration branch at rebase. Otherwise take the next free one and update the REG rows.

## 2. Architecture

Three layers. The pure rules are kept apart so they can be tested without a network.

1. **ZeusCore/Fling (pure, no AppKit, no Network).** CryptoKit is used only in `FlingCrypto.swift`.
   - Wire framing and an incremental decoder.
   - Messages.
   - Limits.
   - File-name rule.
   - Pairing machine and code derivation.
   - Send and receive machines (State/Event/Effect reducers with tokens, following the `docs/STATE-MACHINES.md` pattern).
   - Save-mode rules, flick classifier, peer list, paper geometry.
   - Shelf persistence record.
2. **New library target `ZeusFling`** (imports Network, Foundation, ZeusCore; no AppKit).
   - `FlingEndpoint`: NWListener, NWBrowser, NWConnection, TLS-PSK parameters.
   - Sessions that drive the Core machines over a connection.
   - File sink: hidden temp file, streaming SHA-256, atomic commit.
   - Pairing store.
   - Both the app and the test helper link this target, which is what makes the two-process end-to-end test real.
3. **App (`Sources/Zeus/Fling`, Shelf views, Settings).**
   - `@MainActor @Observable FlingService` facade.
   - Nearby strip, prompts, flick tracker, stacks and ribbon, papers, AirDrop target.
4. **Test helper executable `zeus-fling-peer`** (`qa/fling-peer`).
   - Drives one `FlingEndpoint` through JSON-line commands on stdin and events on stdout.
   - Uses a memory Keychain and a temp save root. Never shipped.

### Wire protocol v1

- Frame: `UInt32 BE length | UInt8 type | payload`.
  - Header payloads are JSON (Codable), at most 64 KiB.
  - Chunk payloads are `UInt32 index | bytes`, at most 1 MiB.
- Messages: `hello{v,id,name,model}`, `pairCommit{h}`, `pairKey{pub}`, `pairReveal{pub,nonce}`, `pairConfirm{mac}`, `pairDecline{reason}`, `offer{stackID, items:[{index,name,size,kind(file|link),uti,sha256,url?}]}`, `accept{stackID}`, `decline{stackID,reason}`, `chunk`, `fileDone{index}`, `itemResult{index,ok|mismatch}`, `stackDone`, `cancel{stackID}`.
- Wrong `v`: close with reason `version`.
- Two listeners:
  - **Transfer listener:** TLS-PSK, advertised on Bonjour, TXT `{v:1,id,name,model,pp}`. The PSK identity is the sender's install id; the server selection block looks it up. No PSK means the handshake fails.
  - **Pairing listener:** plain TCP, port in TXT `pp`. It accepts only pairing frames, one session at a time, and is closed when visibility is "Paired only" or "Off".
- Test mode: `FlingEndpoint.Discovery.direct(host, port)` bound to loopback skips Bonjour. Only the helper and tests use it; the app never reads an env var for it.

### Pairing (commitment plus short code)

1. The initiator sends `pairCommit = SHA256(pubA||nonceA)`.
2. The responder sends `pairKey(pubB)`.
3. The initiator sends `pairReveal(pubA, nonceA)`. A commitment mismatch fails the pairing.
4. Both sides compute X25519, then `transcript = SHA256(idA||idB||pubA||pubB||nonceA)`, `code = HKDF(shared, transcript, "zeus-fling-code-v1") mod 10^6`, and `psk = HKDF(shared, transcript, "zeus-fling-psk-v1", 32)`.
5. The receiver shows the code with Accept and Decline. The sender shows the same code with Cancel.
6. Accept sends `pairConfirm = HMAC(psk, "confirm"||transcript)`. Both sides store the PSK as base64 in `Keychain.store`, account `fling.peer.<installID>`.
7. Non-secret records (name, model, last seen) go to `~/Library/Application Support/Zeus/Fling/peers.json`, mode 0600.
8. The install id is a random UUID in defaults under `fling.installID`. It is never a hardware serial.

### Receive pipeline

1. Validate the offer: names, count, sizes, link scheme, disk space.
2. Accept (paired with auto-accept on, or the user's Accept).
3. Write `<saveRoot>/.fling-partial-<stackID>/<index>` (mode 0600, `O_EXCL`), hashing as the bytes stream in.
4. On `fileDone`, compare the hash.
5. On a match, pick a free name (append " 2" and so on) and rename into the stack folder. Only then does the file reach `addToShelf(urls, origin: .fling(peerName), stack:)`.
6. Every other end state deletes the partial folder. At launch, a sweep deletes `.fling-partial-*` folders older than 1 h.

### Sending needs a gesture

The signature is `FlingService.send(_ items:, to:, gesture: FlingGesture)` where `FlingGesture` is `.button`, `.drop`, `.flick` or `.menu`. No timer, arrival, retry or reconnect path calls it.

## 3. State machines (add entries 25 to 27 to `docs/STATE-MACHINES.md`, "EXPLICIT from the start")

- **25. Fling pairing** (`ZeusCore/Fling/FlingPairing.swift`, `FlingPairingMachine`, roles initiator and responder)
  - States: idle, committing, awaitingKey, awaitingReveal, showingCode(code, deadline 60 s), confirmed, declined, expired, failed(reason).
  - Events: start, received(msg), userAccept, userDecline, userCancel, tick, connectionLost.
  - Effects: send(msg), storePSK, showCode, hidePrompt, close.
  - Rules:
    - Store only on confirmed. Decline, expiry or failure stores nothing.
    - Three declines from one id within 10 min mute that id for 10 min (`FlingMuteLedger`).
    - At most one pairing prompt on screen.
- **26. Fling send** (`FlingTransfer.swift`, `FlingSendMachine`)
  - States: hashing, offering, awaitingAccept, sending(index, sent), finishing, done, declined(reason), failed(reason), cancelled.
  - Rules:
    - The offer goes out only after every hash is ready.
    - Cancel from any non-final state sends `cancel` and closes.
    - Peer lost ends in failed(peerLost). There is no resume.
- **27. Fling receive** (`FlingTransfer.swift`, `FlingReceiveMachine`)
  - States: validating, prompting(deadline 60 s), receiving(index, got), verifying, committing, done, declined(reason), failed(reason: hashMismatch, overSize, badName, tooMany, diskFull, notPaired, peerLost, replay), cancelled.
  - Effects: makeTemp, write, verify, commit, deleteTemp, addToShelf, notifyPeer.
  - Rules:
    - A prompt timeout is a decline.
    - Bytes beyond the declared size fail the transfer.
    - deleteTemp runs on every end state except done.
- **Not machines** (pure functions or lists): `FlingFlick.classify`, `FlingPeerList` (10 s freshness), `FlingSaveRules`.

## 4. Threat model and caps (`ZeusCore/Fling/FlingLimits.swift`)

| Threat | Defence | Test |
|---|---|---|
| Unpaired peer sends files | The transfer listener is TLS-PSK only, and an unknown identity fails the handshake. The pairing listener accepts only pairing frames; an offer there gets `decline(notPaired)` and the connection closes. | REG-673, REG-686 |
| Spoofed name or id | Paired Macs are shown by the name stored at pairing, not the TXT name. A peer claiming a paired id without the PSK fails TLS and is shown as "not paired". The 6-digit code plus commitment defeats a man in the middle (1 in 10^6 per attempt, one prompt at a time, mute after 3 declines). | REG-663, 664, 666 |
| Path traversal | `FlingNames.validate` rejects `/`, `\`, `:`, NUL, control characters, `.` and `..`, a leading dot, an empty name, or more than 255 UTF-8 bytes (after NFC). A bad name declines the whole offer with `badName`. The final path is checked to stay inside the stack folder. Senders clean their own names before offering. | REG-667, 687 |
| Oversized or zip-bomb payload | At most 100 items. Header frame at most 64 KiB, chunk at most 1 MiB. Bytes beyond the declared size abort. Total size must fit in free space minus 1 GiB. Archives are never unpacked. Links: http or https only, at most 2048 characters. | REG-660, 668, 669, 674, 693 |
| Partial files | Hidden partial folder, mode 0600, deleted on every end state except done, plus the launch sweep. A file is visible only after a hash match. | REG-670, 671 |
| Hash mismatch | Delete the temp file, `itemResult(mismatch)` to the sender, "Could not verify <name>" on both sides. | REG-670 |
| Replay | TLS session freshness. The receiver keeps stack ids for 10 min and declines a repeat with `replay`. | REG-672 |
| Local network scanning or flooding | At most 8 connections. Handshake timeout 10 s, idle timeout 30 s. One active transfer per peer. With visibility "Paired only", TXT carries only `id` and the pairing listener is off; with "Off", nothing is advertised or listened. | REG-694, 695 |
| Secrets | PSKs only in Keychain. Logs carry peer id prefixes and byte counts only, never keys, codes or file contents. | review gate |
| Sending without a gesture | Enforced by the `gesture:` parameter. A failure never resends on its own. | REG-692 |

## 5. Files

Changed:

- **`Package.swift`**
  - Add target `ZeusFling` (deps ZeusCore).
  - Add `.executableTarget(name: "zeus-fling-peer", dependencies: ["ZeusFling","ZeusCore"], path: "qa/fling-peer")` and its product.
  - Add `ZeusFling` to the Zeus and ZeusAppTests dependencies.
- **`TopBarModel.swift`**
  - `ShelfItem` gains `origin: ShelfOrigin = .local`, `stackID: UUID? = nil`, `verified = false`.
  - New `addToShelf(_ urls:, origin:, stack:)`. The old `addToShelf(_:isAirDrop:)` stays as a wrapper.
  - `.fling` maps to the `.flingLanded` light and the `.flingArrived` cue.
  - Light options map to `lights.fling`.
  - Load and save persisted Fling items.
- **`ZeusCore/TopBar/NotchLights.swift`**: `case flingLanded`, which shares the landed burst.
- **`Zeus/Notch/NotchLights.swift:161`**: tint for it.
- **`TopBarLayout.swift:254`**: cues `flingArrived(count:from:)`, `flingSent(count:to:)`, `flingProblem(String)`.
- **`TopBarViews.swift`**
  - `ShelfPage`: Nearby strip, stack cells, ribbon mode.
  - `ShelfCell`: Fling glyph and picker, progress ring, flick tracker.
  - Cue rendering at 1540 and 1582.
- **`TopBarServices.swift:433`**: `updateFlingService()` next to `updateIntakeWatcher()`.
- **`AirDropScreenshotWatcher.swift:114`**: explicit `FlingSaveRules.isInsideFlingFolder(url)` skip.
- **`ShelfBrainMenu.swift`**: optional `fling: FlingService?`, plus a "Fling to" submenu listing peers and AirDrop.
- **Settings**
  - `SettingsView.swift:10`: `.shelf` with title, subtitle, icon and `EmptyView()` page.
  - `GlanceSettingsWindow.swift:7`: `GSSection.shelf` in the tools group, "Shelf", `tray.fill`.
  - `GlanceSettingsSnapshotMapping.swift:18, 47`: add "shelf".
  - `GlanceSettingsPages.swift:65`: `case .shelf: ShelfSettingsPage()`.
- **`scripts/gen-settings-catalog.py`**: rows (section 7), `'shelf':'Shelf'`, and `fling.enabled` added to the opt-in guard. Regenerate `SettingsCatalog.swift` and `docs/settings-inventory.md`.
- **`Resources/Info.plist`**
  - `NSLocalNetworkUsageDescription`: "Zeus looks for nearby Macs running Zeus so you can send files to them with Fling."
  - `NSBonjourServices`: [`_zeus-fling._tcp`].
- **`scripts/test.sh`**: `swift build --product zeus-fling-peer` before `swift test`.
- **QA and docs**: `qa/feature-map.json`, `qa/regressions.json`, `docs/STATE-MACHINES.md`.

New:

- **`Sources/ZeusCore/Fling/`**: `FlingWire.swift`, `FlingLimits.swift`, `FlingNames.swift`, `FlingCrypto.swift`, `FlingPairing.swift`, `FlingTransfer.swift`, `FlingSaveRules.swift`, `FlingFlick.swift`, `FlingPeers.swift`, `FlingShelfRecord.swift` (`ShelfOrigin` and the persisted record), `FlingGeometry.swift`.
- **`Sources/ZeusFling/`**: `FlingEndpoint.swift`, `FlingSession.swift`, `FlingFileSink.swift`, `FlingPairingStore.swift`.
- **`Sources/Zeus/Fling/`**: `FlingService.swift`, `FlingNearbyStrip.swift`, `FlingPromptPanel.swift` (non-activating panel near the notch, pattern from `Scribe/ScribeMeetingCardPanel.swift`), `FlingFlickTracker.swift`, `FlingStackViews.swift`, `FlingPaperController.swift`.
- **Settings page**: `Sources/Zeus/Settings/GSShelfPage.swift`.
- **Helper**: `qa/fling-peer/main.swift`.
- **`Tests/ZeusCoreTests/`**: `FlingWireTests`, `FlingNamesTests`, `FlingPairingTests`, `FlingTransferMachineTests`, `FlingSaveRulesTests`, `FlingFlickTests`, `FlingPeersTests`, `FlingShelfRecordTests`, `FlingPlistTests`.
- **`Tests/ZeusAppTests/`**: `FlingTwoProcessTests`, `FlingArrivalTests`, `FlingShelfJourneyTests`, `FlingPairingStoreTests`.
- **Docs**: `docs/FLING.md`.

Key cross-file signatures:

```swift
// ZeusCore
public enum ShelfOrigin: Codable, Equatable, Sendable { case local, airDrop, fling(peer: String) }
public enum FlingNames { public static func validate(_ name: String) -> Result<String, FlingNameError> }
public struct FlingFrameDecoder { public mutating func feed(_ data: Data) throws(FlingWireError) -> [FlingFrame] }
public enum FlingFlick { public static func classify(samples: [FlickSample], sensitivity: FlickSensitivity, peers: Int) -> FlickOutcome } // .drop, .send(peerIndex), .picker
public enum FlingSaveRules { public static func destination(mode: FlingSaveMode, root: URL, peer: String, date: Date, downloadsGranted: Bool) -> URL; public static func isInsideFlingFolder(_ url: URL) -> Bool }
// ZeusFling
public final class FlingEndpoint: @unchecked Sendable {
  public init(identity: FlingIdentity, keys: KeychainStore, saveRoot: URL, discovery: Discovery, queue: DispatchQueue)
  public var events: AsyncStream<FlingEvent> { get }
  public func start() throws; public func stop()
  public func pair(with peer: FlingPeerAddress) ; public func answerPairing(accept: Bool)
  public func send(_ items: [FlingOutgoingItem], to peer: FlingPeerAddress) -> UUID ; public func cancel(_ stackID: UUID)
  public func answerOffer(_ stackID: UUID, accept: Bool)
}
// App
@MainActor @Observable final class FlingService { func send(_ items: [TopBarModel.ShelfItem], to: FlingTarget, gesture: FlingGesture) }
```

## 6. Settings rows (Shelf section, group "Fling", through `gen-settings-catalog.py`)

| id | Title | Kind | Default |
|---|---|---|---|
| `fling.enabled` | Send and receive with nearby Macs | toggle | false. An explicit opt-in in the `validate_table` guard. Turning it on, here or with the Shelf "Turn on Fling" button, starts the listener and the system Local Network prompt. |
| `fling.receiveInBackground` | Receive while the notch is closed | toggle | true |
| `fling.deviceName` | Name shown to nearby Macs | text | "" (empty means the Mac's name) |
| `fling.visibility` | Who can see this Mac | choice: Everyone nearby, Paired only, Off | Everyone nearby |
| `fling.autoAcceptPaired` | Accept from paired Macs without asking | toggle | true |
| `fling.saveMode` | Where arrivals go | choice: Downloads/Fling, Clipboard, Ask each time | Downloads/Fling |
| `fling.papers` | Show arrivals as floating papers | toggle | false |
| `fling.flickSensitivity` | Flick sensitivity | choice: Low, Normal, High | Normal |
| `fling.openLinks` | Open received links in the browser | toggle | true (http/https only) |
| `fling.pairedMacs` | Paired Macs | action (custom row: name, last seen, Remove) | none |
| `lights.fling` | Glow when a Fling arrives | toggle, appearance "Everyday lights" (mirrored on the Shelf page) | true |

Flick thresholds: Low 1800, Normal 1200, High 800 pt/s, measured over the last 80 ms of drag samples.

If Downloads access is denied in Downloads mode, files save to `~/Library/Application Support/Zeus/Fling/Inbox/` and a `.permission` cue points to the Downloads row. Nothing is lost and nothing prompts on its own.

## 7. Slices (each: failing test commit, then implementation, REG rows added with the guard)

0. **S0 spike (throwaway branch, not merged).**
   - Loopback NWListener and NWConnection with PSK, the selection block, an unknown identity rejected, and the TLS version recorded.
   - The NWBrowser policy-denied state recorded (expected `kDNSServiceErr_PolicyDenied`; unverified).
   - Result goes into `docs/FLING.md`.
   - **Stop and escalate to Tony if TLS-PSK cannot be made to work.** Any replacement crypto needs his approval.
1. **S1 Core wire.** `FlingWire`, `FlingLimits`, `FlingNames`. Tests: REG-660, 661, 662, 667, 668, 693.
2. **S2 Core pairing.** `FlingCrypto`, `FlingPairing`, mute ledger. Tests: REG-663, 664, 665, 666.
3. **S3 Core transfers and rules.**
   - Send and receive machines, `FlingSaveRules`, `FlingPeers`, `FlingShelfRecord`, `FlingFlick`.
   - Tests: REG-669, 670, 671, 672, 674, 675, 676, 677, 678, 679, 694, 695.
4. **S4 Transport and end-to-end.**
   - `ZeusFling` target, `zeus-fling-peer`, `FlingTwoProcessTests` (section 8).
   - Tests: REG-673, 685, 686, 687, 688.
5. **S5 App wiring.**
   - Shelf model fields and wrapper, persistence, lights and cues, intake skip, `FlingService` in `TopBarServices`, `FlingPairingStore` on `Keychain.store`, Info.plist, `FlingPlistTests`, `FlingArrivalTests`, `FlingPairingStoreTests`.
   - Tests: REG-680, 681, 682, 683, 691, 692.
6. **S6 Settings.** Catalog rows, Shelf section in both enums, `GSShelfPage` with the Paired Macs list. Test: REG-684. Run `check-settings-catalog.sh`.
7. **S7 Shelf UI.**
   - Nearby strip (paired first, then by name; AirDrop last; Local Network help row).
   - Fling glyph and picker, drop onto an avatar (Shelf cells and Finder files), accept and pairing-code panel, "Fling to" menu, progress ring and check.
   - `FlingShelfJourneyTests`. Tests: REG-689, 690.
8. **S8 Flick.** `FlingFlickTracker` on cells. Fly-off arc, or a fade under Reduce Motion. Journey case added to REG-677.
9. **S9 Stacks.** Stack cell (3 fanned thumbnails and a count), ribbon (Escape or back chevron), group and ungroup, drag-out copies all files, "Save stack to folder…" moves files and updates Shelf URLs. Tests in `FlingArrivalTests`; uses spare REG-696.
10. **S10 Clipboard and Ask modes, links.** Uses REG-697.
11. **S11 Floating papers** (`fling.papers`, off). Non-activating `.floating` panels with `canJoinAllSpaces` and `fullScreenAuxiliary`, cascade from `FlingGeometry`, pinch to group. Closing a paper never touches the Shelf. Uses REG-698.
12. **S12 Docs and closure.**
    - `docs/FLING.md`: user behaviour, protocol, threat model, limits, owner checks.
    - STATE-MACHINES entries 25 to 27.
    - Feature map final.
    - REG-699 stays spare.

## 8. End-to-end test (required): `Tests/ZeusAppTests/FlingTwoProcessTests.swift`, check `native-FlingTwoProcessTests`

- **Setup**
  - The test resolves `.build/debug/zeus-fling-peer`, or `ZEUS_FLING_PEER` if set, and fails with a clear message if it is missing.
  - It spawns process A (sender) and process B (receiver). Each gets its own temp save root, its own memory Keychain and `--direct 127.0.0.1:0`.
  - B prints `{"event":"listening","port":N,"pairPort":M}`.
- **Steps**
  1. A `pair` -> both print `pairCode`. Assert the codes are equal and 6 digits. B `answerPairing accept` -> both print `paired`.
  2. A sends a PNG image, a `.mov` stub, a link (`https://example.com`) and a 50 MB random file as one stack.
  3. Assert:
     - B prints `itemVerified` four times, with SHA-256 matching the test's own hashes.
     - The files exist under B's `<root>/Fling/<stack folder>/`.
     - The link was written as a URL item.
     - B's `shelf.json`, decoded with ZeusCore `FlingShelfRecord`, holds 4 records: origin fling(A's name), one stackID, verified true.
     - No `.fling-partial-*` folder remains.
  4. **Unpaired peer:** process C (never paired) sends to B. B prints `rejected(notPaired)` (TLS) and C prints a failure; nothing new is written under B's root.
  5. **Traversal:** A uses the helper-only `--raw-name "../evil.txt"`. B prints `declined(badName)`; nothing appears in B's root or its parent.
  6. **Cancel:** A sends 50 MB with the helper-only pacing `--chunk-delay-ms 20`. After B reports progress of at least 10%, A sends `cancel`. Both print `cancelled`, no final or partial file remains, and a following 1-file send succeeds.
  7. **Extra:** `--corrupt-byte` gives `hashMismatch` with the temp file deleted.
- **Teardown:** every process gets `quit`, then SIGKILL after 5 s, and temp roots are deleted. Overall timeout 120 s.
- **Helper-only switches** (`--raw-name`, `--chunk-delay-ms`, `--corrupt-byte`, `--direct`) are parsed in `qa/fling-peer` only. They reach `FlingEndpoint` through an injected `FlingTestHooks` value whose default is empty, so the app cannot reach them.
- **Bonjour variant:** `ZEUS_FLING_E2E_BONJOUR=1` makes B advertise and A discover through NWBrowser instead of a direct address. It is for owner runs on a real Mac and is skipped (and reported as skipped) otherwise.
- **How CI runs it:** the hosted Mac runner's `swift build` builds the helper. `native.py` selects the new `native-fixture` checks from `qa/feature-map.json`. Loopback only, so no Bonjour, no Local Network prompt (U2: if loopback is not exempt, S0 shows it and the test binds `requiredInterfaceType = .loopback`) and no real Keychain.

**Hosted AppKit journey: `Tests/ZeusAppTests/FlingShelfJourneyTests.swift`, check `native-FlingShelfJourneyTests`.** It uses the `OwnedWindowEventDriver` pattern: an owned window, layout-resolved mouse events, and no global events.

1. A `ShelfPage` with a real `TopBarModel` (two items) and a fake `FlingSending` port listing two peers. Dragging cell 1 onto avatar 2 makes the fake record `send([item1], to: peer2, gesture: .drop)`. Fallback per U4.
2. A synthetic sample stream goes into the production `FlingFlickTracker`:
   - slow: a drop, no send;
   - fast with one paired peer: sends to it;
   - fast left with two peers: the left avatar;
   - upward with two peers: the picker shows.
3. The accept panel view in an owned window: clicking Accept sends `.userAccept` to a recording receive machine; Decline and the 60 s timeout (injected clock) decline.

**`FlingArrivalTests`** (in-process, two endpoints over loopback, a real `TopBarModel`, throwaway defaults suite):

- items get `.fling` origin, a shared stackID and `verified`;
- the `.flingLanded` light shows with `lights.fling` on and not with it off;
- an `AirDropScreenshotWatcher` pointed at a temp "Downloads" ignores the `Fling/` subfolder (T-14);
- the old `addToShelf(isAirDrop:)` behaves as before.

## 9. Feature map and REG

- **Feature F15** (see U5): "Fling: send and receive between Macs from the Shelf".
  - F15.1 `native-ZeusCoreTests`: wire, names, pairing, machines, rules, flick, persistence, plist.
  - F15.2 `native-FlingTwoProcessTests`: two-process end-to-end.
  - F15.3 `native-FlingArrivalTests`: service to Shelf, lights, intake skip.
  - F15.4 `native-FlingShelfJourneyTests`: hosted UI.
  - F15.5 `native-SettingsCatalogTests`: Fling rows and the opt-in default.
  - F15.6 `missing-F15-device`: the owner checks in section 10, no cases.
- **New `checks` rows:** the three new suites as kind `native-fixture` (each with `suite` and `file`), plus `missing-F15-device`.
- **REG-660..699 reserved.** IDs are assigned per slice as listed in section 7: 660 to 695 named, 696 to 698 for stacks, links and clipboard, and papers, 699 spare. Each REG row names its guard file and function.

## 10. Gates and owner checks

**End gates, at the head SHA:**

1. `swift build`
2. `scripts/test.sh`, everything green, with the new suites present in the result events
3. `scripts/check-settings-catalog.sh`
4. Schema validation of `qa/feature-map.json` and `qa/regressions.json` (closed-loop gate)
5. A grep for the em dash character over the diff: zero hits
6. A secrets scan of the diff: no keys, codes or PSK values in code, logs or fixtures
7. A third-party-name scan of the diff and commit messages. The banned word list stays outside the repo, in the relay folder, and the factory runs the scan from there, so the repo never contains the word.
8. Confirm `scripts/bundle.sh` output has no `zeus-fling-peer`
9. Independent review
10. Vera PASS at the current head SHA

**Owner must check by hand** (F15.6):

- Two real Macs on one Wi-Fi: the peer shows in Nearby within 3 s, pairing codes match, a decline stores nothing, a file arrives in `~/Downloads/Fling` and on the Shelf, a 4 GB video verifies.
- Wi-Fi off on both, near each other: peer-to-peer discovery works or not. Record the result.
- The first enable shows the Local Network prompt once with the plist text. A denial shows the help row and nothing crashes.
- AirDrop to an iPhone from the Nearby strip, the Fling picker and the flick picker: the sheet opens with every selected item.
- Removing a paired Mac in Settings deletes its Keychain item, and the next send asks to pair again.
- Clipboard mode: Cmd-V in Finder pastes the file.
- Papers on: no focus is stolen, and closing a paper leaves the Shelf unchanged.

## 11. Risks and approvals

- **TLS-PSK API (U1)** is the main technical risk. S0 gates S4. A crypto fallback needs Tony's approval.
- **New package targets** (`ZeusFling`, `zeus-fling-peer`) change `Package.swift`. Low risk, but new structure; flag it in the PR.
- **Downloads access:** saving to `~/Downloads/Fling` needs Downloads folder access. Denied access falls back to the App Support Inbox; there is never a silent prompt.
- **Shelf persistence** adds a file at `~/Library/Application Support/Zeus/Shelf/shelf.json` (Fling items only, at most 500 records, atomic write, an unreadable file is never overwritten). Removable, not irreversible.
- **Keychain items on real Macs** are written only at pairing and removed with Remove. On local builds they go to the `zeus-dev` keychain, which matches the existing no-prompt rule; run `scripts/check-keychain-prompts.sh` once after S5.
- **Owner confirmation needed:**
  - `fling.enabled` defaults to false (opt-in) to match "after first-run consent". Background receive applies once it is on.
  - `fling.openLinks` defaults to true, which opens http/https links from accepted or paired senders. Say if it should be false.
  - The feature id F15.
- **Network behaviour is irreversible in one sense:** once a build with the plist keys ships, the Local Network prompt appears for anyone who enables Fling.
