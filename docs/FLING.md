# Fling

Fling sends files between Macs that run Zeus, from the Shelf. The plan is `docs/FLING-PLAN.md`. This file records what was measured while building it and, at the end, how it behaves.

## S0 findings: TLS with a pre-shared key on Network.framework

Measured on macOS 27.2 (SDK 27.2, Swift 6.4.2) with a throwaway package outside this repository: an `NWListener` and an `NWConnection` over loopback (`requiredInterfaceType = .loopback`), TLS options built with `sec_protocol_options_add_pre_shared_key` on both sides.

| Case | Result |
|---|---|
| Same identity and key on both sides | Handshake completes, a ping and pong round trip works. |
| Server holds several PSKs, client uses the second | Works. The server picks the PSK by the identity the client sends. |
| Client sends an identity the server does not hold | Both sides fail with `-9864 unknown PSK identity`. |
| Known identity, wrong key | Both sides fail with `-9846 bad MAC` (server) and `-9820 bad MAC` (client). |
| Loopback connection | No Local Network prompt in a plain command line process. |
| `NWBrowser` for the Bonjour type in a plain command line process | Reaches `ready`. The policy-denied state was not seen outside an app bundle; it stays an owner check. |

What was negotiated: TLS 1.2 with `TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256` (0xCCAC), which has forward secrecy. Setting the minimum protocol to TLS 1.3 or appending other cipher suites did not change the negotiated version or suite, so the app records the suite it got instead of relying on those settings.

Two facts change the plan's wording but not its design:

1. **Do not set an identity hint on the server.** `sec_protocol_options_set_tls_pre_shared_key_identity_hint` makes every handshake fail (`-9858` client, `-9824` server).
2. **The server's PSK list is fixed when the listener is created.** Adding a PSK to the options object after the listener has started is not honoured (`-9864`). So the transfer listener is rebuilt whenever the set of paired Macs changes (a new pairing or a removal), and the new port is re-advertised.

Verdict: TLS-PSK works on this macOS. No replacement crypto is needed.
