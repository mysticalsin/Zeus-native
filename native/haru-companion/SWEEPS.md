# Bug sweeps

Baseline `583c3dcc`. Head after these sweeps is recorded by `git log`.
Each real defect was committed as a failing test, then the fix.
`H-external` entries are the hunt at
`echo-shared/haru-companion-hunt-583c3dcc.md`
(sha256 `9bc245303071f8355d163223e7f6df578493aaaaeacbf03abc89e9766ca5e435`).

## 1. Session spawn failure

- Lens: session state machine. A failed `spawn` left the session in `Starting`, and the socket reported `illegal_transition`.
- Checked: `begin_model_load` on a launcher that returns an error, and `handle_raw(START)`.
- Test: `538094d` `tests/sweep_session.rs`
- Fix: `c391c76`

## 2. Close, restart, and client drop

- Lens: close/start interleaving. `spawn_fresh_idle` forgot a live pid, close from that idle session left it running, and a client drop did not end the session.
- Checked: 2000 pseudo-random interleavings, restart-then-close, and `serve_one` without `CLOSE`.
- Test: `f761aae` `tests/sweep_race.rs`
- Fix: `11c6a57`

## 3. Child process lifecycle

- Lens: zombies, drop, SIGTERM then SIGKILL, parent death.
- Checked: `/bin/true` reaped by `alive`, dropping `StdLauncher` kills `sleep`, a Python handler records SIGTERM, SIGTERM-ignored still dies, `PR_GET_PDEATHSIG` is 9.
- Test: `ddd086e` `tests/sweep_lifecycle.rs`
- Fix: `09e91ec`
- Process-group kill is H-external HC-05, not this commit.

## 4. Frame buffer recovery

- Lens: socket framing. An oversized length stuck the framer and dropped a valid frame in the same buffer. Partial reads already reassembled.
- Test: `467a711` `tests/sweep_framing.rs`
- Fix: `b3a6d38`

## 5. JSON decoder

- Lens: UTF-8 strings, fractional numbers, nesting, a second server frame, non-empty CLOSE, raw controls.
- Test: `64059b0` `tests/sweep_decoder.rs`
- Fix: `3214ea9`
- Canonical integer spelling (`1.0`, `01`) is H-external HC-11.

## 6. Watchdog samples

- Lens: a 1 GB report filled the latency window, a non-finite step was ignored, and a late garbage frame was scored as silence.
- Test: `25d2b85` `tests/sweep_watchdog.rs`
- Fix: `4dd7966`

## 7. Child-state illegal exits

- Lens: `on_exit` before launch spawned, and `stopped_failed` came back after the budget window via `unwrap_or(Unhealthy)`.
- Test: `f188041` `tests/sweep_child_state.rs`
- Fix: `4a8e177` (the restart logic landed in that commit together with rustfmt)

## 8. Unbounded input

- Lens: upstream length and the text-token buffer.
- Test: `6eda0c4` `tests/sweep_memory.rs` and `engine::text_bound`
- Fix: `a14434c`
- A legal-sized but non-3200 upstream frame is H-external HC-10.

## 9. Socket path

- Lens: dangling symlink, regular file, socket left after a failed spawn.
- Test: `2b9632f` `tests/sweep_socket_path.rs`
- Fix: `40ce10c`
- A live listener was still unlinked. That is H-external HC-13.

## 10. Flags

- Lens: `--watchdog` was discarded, and `--frames` had no cap.
- Test: `700cee8`
- Fix: `54c6283`

## 11. Numeric edges

- Lens: haru-pipe zero sample rate, split f32 bytes, large Kaiser beta, percentile rank, and `find_loop` period 0. A huge WAV chunk does not panic on 64-bit; the walker still uses checked sizes.
- Test: `4d935ab`
- Fix: `18ce6d1`

## 12. serve accepts one client

- Lens: after a successful spawn, `serve` removed the socket and returned before a client could connect.
- Test: `99644d2`
- Fix: `94b47c2`

## 13. Property tests

- Lens: proptest 1.5, 64 cases. Random frames do not panic. Unicode prompts round-trip.
- Test: `a9b9b35` `tests/sweep_proptest.rs`
- Finding: none beyond sweeps 5 and HC-11.

## 14. Logging and soak

- Lens: error frames do not contain a prompt. 10_000 connect cycles and 13_534 fake frames (30 minutes at 133 ms) keep fds flat and RSS within 8 MiB.
- Test: `dc19169`
- Finding: no leak on those runs.

## 15. External hunt remainder

- Lens: the hunt behaviours that were still wrong after sweeps 1–14.
- Test: `65ac6dc` `tests/sweep_hunt.rs`
- Fix: `10a7474`

## H-external

| ID | Test | Fix | Result |
| --- | --- | --- | --- |
| HC-01 | `99644d2` | `94b47c2` | `serve` accepts one client, `--watchdog` reaches the engine, a failed spawn removes the socket, and the child is reaped on the way out |
| HC-02 | `65ac6dc` | `10a7474` | a missing path or a regular file is `NoLaunch { MissingModel }`, exit 2, no spawn |
| HC-03 | `f761aae`, `65ac6dc` | `11c6a57`, `10a7474` | EOF closes and kills the child. A read timeout no longer drops a quiet client |
| HC-04 | `65ac6dc` | `09e91ec`, `10a7474` | `alive` reaps with `try_wait`. `finish_model_load` after SIGKILL is `process_exited` and does not reach `streaming` |
| HC-05 | `65ac6dc` | `10a7474` | the child is a process-group leader and shutdown signals the group |
| HC-06 | `f188041` | `4a8e177` | `on_exit` before start does not spawn, and `stopped_failed` stays down |
| HC-07 | `f761aae`, `65ac6dc` | `c391c76`, `11c6a57` | START after a stall restart keeps the one restarted child |
| HC-08 | `65ac6dc` | `10a7474` | upstream read deadline is 2 s, the push counts an underrun, and the trace has `watchdog_restart` / `stall` |
| HC-09 | `65ac6dc` | `10a7474` | upstream TEXT is delivered to the token-loop watchdog |
| HC-10 | `6eda0c4`, `65ac6dc` | `a14434c`, `10a7474` | declarations over 8 MiB are rejected, and any other upstream frame must downsample to 3200 samples |
| HC-11 | `64059b0`, `65ac6dc` | `3214ea9`, `10a7474` | UTF-8 round-trips. Only a canonical integer token decodes, so `1.0` and `01` are not version 1 |
| HC-12 | `64059b0`, `65ac6dc` | `3214ea9` | nesting deeper than 16 is `BadJson`. Depth 20_000 does not abort |
| HC-13 | `65ac6dc` | `10a7474` | a socket that still accepts a connection is `AddrInUse` and is not unlinked |
| HC-14 | `2b9632f` | `40ce10c` | a dangling symlink is removed with `symlink_metadata` and the bind succeeds |
| HC-15 | `65ac6dc` | `10a7474` | the socket is created with umask `0177` and `fchmod` on the bound fd. The path is not chmod'd |
| HC-16 | `25d2b85` | `4dd7966` | a non-finite step is an immediate latency restart |
| HC-17 | `538094d` | `c391c76` | a failed exec is `process_exited` and the session is `failed`, not `Starting` |
| HC-18 | `65ac6dc` | `10a7474` | a directory whose name contains `reference` is not refused. `reference_path` is still rejected on START |
| HC-19 | `65ac6dc` | `10a7474` | the restart window is `Instant`, so `advance(10 min)` does not grant another restart |

## Checked, not a new defect

- Cross compile, stable 1.100, target `aarch64-apple-darwin`: `cargo check --locked` exits 0 for both crates. `cargo build --locked` compiles and fails at link. `xcrun --sdk macosx` is missing (`os error 2`) and the host `cc` rejects `-arch arm64` (`unsupported option '-arch' for target 'x86_64-pc-linux-gnu'`). No Mach-O was produced.
- `cargo audit` 0.21.2 and `cargo deny` 0.16.4 both exit 1 before checking these crates: the current RustSec database contains a CVSS 4.0 vector they cannot parse (`RUSTSEC-2026-0209`). That is the tool, not an advisory against haru-companion or haru-pipe.
