CREATE TABLE IF NOT EXISTS licenses (
  id TEXT PRIMARY KEY,
  key TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  plan TEXT NOT NULL,
  email TEXT NOT NULL,
  name TEXT,
  seats INTEGER NOT NULL DEFAULT 1,
  issued INTEGER NOT NULL,
  expires INTEGER,
  status TEXT NOT NULL DEFAULT 'active',
  revoked_at INTEGER,
  revoke_reason TEXT,
  source TEXT NOT NULL DEFAULT 'portal',
  order_ref TEXT,
  replaces TEXT,
  replaced_by TEXT,
  note TEXT
);
CREATE INDEX IF NOT EXISTS licenses_email ON licenses(email);
CREATE UNIQUE INDEX IF NOT EXISTS licenses_order ON licenses(source, order_ref) WHERE order_ref IS NOT NULL;
CREATE TABLE IF NOT EXISTS activations (
  license_id TEXT NOT NULL,
  device TEXT NOT NULL,
  name TEXT,
  created INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (license_id, device)
);
CREATE TABLE IF NOT EXISTS audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  license_id TEXT,
  detail TEXT
);
CREATE TABLE IF NOT EXISTS webhook_events (
  provider TEXT NOT NULL,
  event_id TEXT NOT NULL,
  received INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'processing',
  kind TEXT,
  license_id TEXT,
  PRIMARY KEY (provider, event_id)
);
CREATE TABLE IF NOT EXISTS outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created INTEGER NOT NULL,
  license_id TEXT NOT NULL,
  to_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ready'
);
