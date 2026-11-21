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

## 16. Security review (ARTEX at 583c3dcc)

- Lens: IPC sockets. Checked against head `c569f6fa`.
- Test: `c582fb4` `tests/sweep_security.rs`
- Fix: `69572c9`
- E-02: fixed in `69572c9`. `serve` accepts Zeus only on the 0600 socket and applies `SO_PEERCRED` / `getpeereid` against `geteuid`. `serve_one_with` takes an injected `PeerCheck`, and a scripted foreign uid is `PermissionDenied`. The child socket is bound the same way, its connection is peer-checked, and both sockets are unlinked on exit. The child socket is mode 0600 and its parent, when created here, is mode 0700.
- E-04: the chmod-after-bind race was already fixed by `10a7474` (no `set_permissions` on the path). `69572c9` also creates a missing parent directory at mode 0700. `e02_child_socket_is_0600_inside_a_0700_dir` locks both modes. `848116b` replaced the process umask with `fchmodat(..., AT_SYMLINK_NOFOLLOW)`.

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
| HC-15 | `65ac6dc` | `10a7474`, `848116b` | the path is not chmod'd through a symlink. `848116b` sets mode 0600 with `fchmodat` and `AT_SYMLINK_NOFOLLOW` and does not change the process umask |
| HC-16 | `25d2b85` | `4dd7966` | a non-finite step is an immediate latency restart |
| HC-17 | `538094d` | `c391c76` | a failed exec is `process_exited` and the session is `failed`, not `Starting` |
| HC-18 | `65ac6dc` | `10a7474` | a directory whose name contains `reference` is not refused. `reference_path` is still rejected on START |
| HC-19 | `65ac6dc` | `10a7474` | the restart window is `Instant`, so `advance(10 min)` does not grant another restart |

## CI on `0e7065d`

- Time: 2026-11-21T05:23:12Z. Pull request run `44862869399` and push run `44862867972` both failed. Companion job `136719942210` failed `hc05_kill_reaps_the_process_group` at `tests/sweep_hunt.rs:173` and `hc18_a_model_directory_may_contain_the_word_reference` at line 470, both `PermissionDenied` (os error 13). The pipe job passed.
- Cause: `bind_socket` set the process umask to `0177` while other tests created directories, so those directories were mode 0600 and a later write was `EACCES`.
- Test: `588188e` `tests/sweep_umask.rs`. It failed on the umask build with `PermissionDenied` at `create`/`write`.
- Fix: `848116b`. A new parent is `fchmod`'d to 0700 on a directory fd. The socket is `fchmodat` mode 0600 with `AT_SYMLINK_NOFOLLOW`. `umask` is not called.
- After that fix, `e02_child_socket_is_0600_inside_a_0700_dir` still sees socket 0600 and parent 0700.
- One parallel `cargo test --locked` then failed `thirty_minute_synthetic_soak_stays_flat` with fd count 5 before and 6 after, while `ten_thousand_connect_cycles_do_not_leak_fds` ran in the same process. The soak alone passed. It now lives in `tests/sweep_soak.rs`.

## 17. UX polish and motion

- Time: 2026-11-21T05:23:12Z.
- Lens: UX polish and motion.
- Findings: `state_machine_svg` placed `close` and `fail(socket_closed)` on the same point `(185, 142)`. The streaming-to-closing `close` label sat on the `animateMotion` path. A foreign peer was dropped with no bytes; the client `read_exact` returned `UnexpectedEof`.
- Stress: 20 foreign-uid connections in a row. Each must read one `peer_uid` error frame, and the server must return `PermissionDenied`.
- Test: `a822b99` `tests/sweep_ux.rs`. Both tests failed before the fix.
- Fix: `6ffb0aa`. Edge labels are offset off the nodes, off each other, and at least 16 px from the motion path. `serve_one_with` writes an error frame with code `peer_uid` before it returns `PermissionDenied`. `docs/state-machine.svg` matches the generator.
- Counts after the fix, `cargo +stable test --locked` (default threads): haru-companion 87 passed, 0 failed. haru-pipe 16 passed, 0 failed. `cargo +stable fmt --check` and `cargo +stable clippy --locked --all-targets -- -D warnings` passed for both crates.

## 18. Bind window and child rebind

- Time: 2026-11-21T06:17:00Z. Hammer re-check at `f8704c45` (report sha256 `60b09ec7`) plus Sentinel FIRST AGREED 0.65 Low.
- Lens: security. N-1, E-04(1) through E-04(5), E-02 test gaps.
- Test: `12d88e4` `tests/sweep_bind.rs`. Six tests failed: world-writable parent accepted, sticky 01777 left writable, Python received the parent gate path, a replaced socket was accepted, `unlink_if_ours` deleted a different inode, and `O_DIRECTORY` was the literal `0x10000`.
- Fix: this commit. Python is given `gate.model`. The parent records the directory-entry dev/ino and refuses a later path that does not match; a connect to the listener confirms the replacement. `fchmodat` and `unlinkat` use the parent directory fd. A non-sticky group or world writable parent is refused. A sticky directory we own is tightened to 0700. A directory this call creates is `fchmod` 0700 before bind, including under umask 000. Open flags come from `libc` 0.2.191. `/proc/self/fd` is documented as fail closed; the test printed `haru-companion skip: fchmodat AT_SYMLINK_NOFOLLOW uses /proc/self/fd; bind fails closed when it is absent (1 skipped)`.
- N-2: `serve` still uses `FakeBackend::quiet()`, and the probe child is dropped so `StdLauncher::drop` kills it. Not changed.
- Counts: `cargo +stable test --locked` haru-companion 97 passed, 0 failed. haru-pipe 16 passed, 0 failed.

## Checked, not a new defect

- Cross compile, stable 1.100, target `aarch64-apple-darwin`: `cargo check --locked` exits 0 for both crates. `cargo build --locked` compiles and fails at link. `xcrun --sdk macosx` is missing (`os error 2`) and the host `cc` rejects `-arch arm64` (`unsupported option '-arch' for target 'x86_64-pc-linux-gnu'`). No Mach-O was produced.
- `cargo audit` 0.21.2 and `cargo deny` 0.16.4 both exit 1 before checking these crates: the current RustSec database contains a CVSS 4.0 vector they cannot parse (`RUSTSEC-2026-0209`). That is the tool, not an advisory against haru-companion or haru-pipe.
