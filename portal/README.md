# ZEUS Portal

Generate and manage ZEUS licenses on this Mac: lifetime, annual and 14 day trial keys, seats per
Mac, revocation, re-issue, CSV export and an audit log. Purchase webhooks issue keys on their own.

Zero npm dependencies: Node 22.13 or newer (`node:sqlite`, WebCrypto). Data stays on this Mac.

## Run

```sh
cd portal
node bin/zeus-portal.js serve          # http://127.0.0.1:8790
npm link                               # optional: installs the `zeus-portal` command
```

First visit asks for an admin passphrase (12 characters or more). Reset it any time with
`zeus-portal passphrase` (typed hidden, never echoed).

```sh
zeus-portal issue --email buyer@example.com --name "Ada Buyer" --plan lifetime --seats 2
zeus-portal list --q ada
zeus-portal revoke L-0123456789 --reason "refund"
zeus-portal export licenses.csv
zeus-portal public-key                 # the value embedded in ZEUS (ZeusCore LicenseKeys.release)
```

Test: `npm test` (runs `node --test test/*.test.js`).

## Keys

- License key: `ZEUS1.<base64url JSON>.<base64url Ed25519 signature>`. The app checks it offline.
- Activation proof: `ZEUSA1...`, signed per Mac when a seat is claimed (optional, needs a server).
- Revocation list: `ZEUSR1...`, a signed list of turned-off ids the app checks once a day.

## Security model

- The Ed25519 signing key is generated once and kept in the Zeus dev keychain
  (`~/Library/Keychains/zeus-dev.keychain-db`, service `com.zeus.portal`, account `signing.ed25519`).
  It is never written to disk, printed, or sent anywhere. Only `public-key.txt` is on disk.
- Service `com.zeus.portal` is deliberately separate from the app's `com.zeus.app`: the app reads
  every item under its own service, so a shared service would load the signing key into ZEUS.
- Keychain items are written with `security -i` over stdin, so secrets never appear in process
  arguments, and are readable by `/usr/bin/security` without a password dialog.
- The admin passphrase is stored only as a PBKDF2-SHA256 hash (600,000 rounds). Sessions are
  HMAC-signed HttpOnly SameSite=Strict cookies; admin calls also need an `x-zeus-portal` header.
  Login is rate limited (8 tries per 5 minutes).
- The server binds to 127.0.0.1 only and checks the Host header (no DNS rebinding). Strict CSP,
  no inline scripts or styles.
- Data: `~/.zeus-portal/portal.sqlite` and `config.json`, both mode 600.

## Purchases

`POST /webhooks/<provider>` with `lemonsqueezy`, `paddle`, `stripe` or `generic`. Each verifies the
store's signature (HMAC, with a 5 minute window for Paddle and Stripe), is idempotent by event id
and by order id, issues the key, stores it and queues the delivery email in Deliveries. A refund
turns the key off. Nothing is emailed automatically: copy the text or open it in Mail.

All providers are off. To turn one on after choosing a store:

1. Set `"enabled": true` for it in `~/.zeus-portal/config.json`, and map store product ids to
   plans under `products` (otherwise `defaultProduct` is used: lifetime, 2 seats).
2. Save the store's signing secret: `pbpaste | zeus-portal webhook-secret lemonsqueezy`
   (or paste it in Settings).
3. Point the store's webhook at a public URL that forwards to this portal. A store cannot reach
   127.0.0.1, so this needs a hosting decision first.

## App side

ZEUS embeds the public key (`Sources/ZeusCore/License/LicenseKeys.swift`). With no license server
set, keys are fully offline. With one set (Settings, License, Server), activating claims a seat
through `POST /api/v1/activate`, Deactivate frees it, and `GET /api/v1/revocations` is fetched once
a day. `zeus-cli license verify|activate|deactivate` checks a key the same way from the terminal.
