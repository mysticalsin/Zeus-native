// The license book: issue, look up, revoke, re-issue, activate seats, and the signed revocation list.
// `db` is D1 or the local SQLite shim with the same API (prepare/bind/first/all/run, batch).
import { cleanKey, decodeBlob, encodeBlob, fingerprint, licenseID, PREFIX } from './crypto.js';
import { deliveryEmail } from './email.js';

export const PLANS = ['lifetime', 'annual', 'trial', 'pro'];
const DAY = 86_400;
const DEFAULT_DAYS = { trial: 14, annual: 365 };
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export class PortalError extends Error {
  constructor(code, message, status = 400) { super(message); this.code = code; this.status = status; }
}

export class Portal {
  constructor({ db, signer, config = {}, now = () => Math.floor(Date.now() / 1000) }) {
    this.db = db; this.signer = signer; this.config = config; this.now = now;
  }

  q(sql, ...args) { return this.db.prepare(sql).bind(...args); }
  async all(sql, ...args) { return (await this.q(sql, ...args).all()).results ?? []; }

  logStatement(actor, action, licenseId = null, detail = null) {
    return this.q('INSERT INTO audit (ts, actor, action, license_id, detail) VALUES (?, ?, ?, ?, ?)',
      this.now(), actor, action, licenseId, detail == null ? null : (typeof detail === 'string' ? detail : JSON.stringify(detail)));
  }
  async log(...args) { await this.logStatement(...args).run(); }

  async issue({ plan = 'lifetime', email, name = null, seats = 1, days = null, source = 'portal', orderRef = null,
    replaces = null, note = null, actor = 'admin', queueEmail = false } = {}) {
    if (!PLANS.includes(plan)) throw new PortalError('bad_plan', 'Pick lifetime, annual, trial or pro.');
    email = String(email ?? '').trim().toLowerCase();
    if (!EMAIL.test(email)) throw new PortalError('bad_email', 'Enter the buyer\'s email address.');
    seats = Number.parseInt(seats, 10);
    if (!Number.isInteger(seats) || seats < 1 || seats > 100) throw new PortalError('bad_seats', 'Seats must be between 1 and 100.');
    name = name ? String(name).trim().slice(0, 120) || null : null;
    const custom = days != null && days !== '' ? Number.parseInt(days, 10) : null;
    if (custom != null && (!Number.isInteger(custom) || custom < 1 || custom > 3650)) throw new PortalError('bad_days', 'Days must be between 1 and 3650.');
    const span = custom ?? DEFAULT_DAYS[plan] ?? null;
    const issued = this.now();
    const expires = span ? issued + span * DAY : null;
    const id = licenseID();
    const key = await encodeBlob(PREFIX.license, { id, email, plan, issued, expires, name, seats }, this.signer.privateKey);
    const statements = [
      this.q(`INSERT INTO licenses (id, key, fingerprint, plan, email, name, seats, issued, expires, source, order_ref, replaces, note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id, key, await fingerprint(key), plan, email, name, seats, issued, expires, source, orderRef, replaces, note),
      this.logStatement(actor, 'issue', id, { plan, seats, source, orderRef, expires }),
    ];
    if (replaces) {
      statements.push(this.q('UPDATE licenses SET status = \'revoked\', revoked_at = ?, revoke_reason = \'reissued\', replaced_by = ? WHERE id = ?',
        issued, id, replaces));
      statements.push(this.logStatement(actor, 'reissue', replaces, { new: id }));
    }
    if (queueEmail) {
      const mail = deliveryEmail({ id, key, plan, email, name, seats, expires }, this.config);
      statements.push(this.q('INSERT INTO outbox (created, license_id, to_email, subject, body) VALUES (?, ?, ?, ?, ?)',
        issued, id, mail.to, mail.subject, mail.body));
    }
    await this.db.batch(statements); // one transaction
    return this.get(id);
  }

  async get(id) {
    const row = await this.q('SELECT * FROM licenses WHERE id = ?', id).first();
    return row ? this.decorate(row) : null;
  }

  async findByOrder(source, orderRef) {
    const row = await this.q('SELECT * FROM licenses WHERE source = ? AND order_ref = ?', source, orderRef).first();
    return row ? this.decorate(row) : null;
  }

  async decorate(row) {
    const activations = await this.all('SELECT device, name, created, last_seen FROM activations WHERE license_id = ? ORDER BY created', row.id);
    const state = row.status === 'revoked' ? 'revoked' : (row.expires && row.expires < this.now() ? 'expired' : 'active');
    return { ...row, state, activations, used: activations.length };
  }

  async require(id) {
    const license = await this.get(id);
    if (!license) throw new PortalError('not_found', 'No license with that ID.', 404);
    return license;
  }

  async list({ q = '', state = '', limit = 500 } = {}) {
    const like = `%${String(q).trim().toLowerCase()}%`;
    const rows = await this.all(`SELECT l.*, (SELECT count(*) FROM activations a WHERE a.license_id = l.id) AS used FROM licenses l
      WHERE (? = '%%' OR lower(l.email) LIKE ? OR lower(coalesce(l.name, '')) LIKE ? OR lower(l.id) LIKE ?
      OR lower(coalesce(l.order_ref, '')) LIKE ? OR l.fingerprint LIKE ?) ORDER BY l.issued DESC, l.rowid DESC LIMIT ?`,
    like, like, like, like, like, like, Math.min(Number(limit) || 500, 5000));
    const now = this.now();
    const all = rows.map((r) => ({ ...r, state: r.status === 'revoked' ? 'revoked' : (r.expires && r.expires < now ? 'expired' : 'active') }));
    return state ? all.filter((l) => l.state === state) : all;
  }

  async stats() {
    const all = await this.list({ limit: 5000 });
    const count = (s) => all.filter((l) => l.state === s).length;
    return { total: all.length, active: count('active'), revoked: count('revoked'), expired: count('expired'),
      activations: all.reduce((n, l) => n + l.used, 0), lifetime: all.filter((l) => l.plan === 'lifetime' && l.state === 'active').length };
  }

  async revoke(id, { reason = 'revoked', actor = 'admin' } = {}) {
    const license = await this.require(id);
    if (license.status === 'revoked') return license;
    await this.db.batch([
      this.q('UPDATE licenses SET status = \'revoked\', revoked_at = ?, revoke_reason = ? WHERE id = ?', this.now(), String(reason).slice(0, 80), id),
      this.logStatement(actor, 'revoke', id, { reason }),
    ]);
    return this.get(id);
  }

  async restore(id, { actor = 'admin' } = {}) {
    const license = await this.require(id);
    if (license.replaced_by) throw new PortalError('replaced', 'This key was re-issued. Use the new key instead.');
    await this.db.batch([
      this.q('UPDATE licenses SET status = \'active\', revoked_at = NULL, revoke_reason = NULL WHERE id = ?', id),
      this.logStatement(actor, 'restore', id),
    ]);
    return this.get(id);
  }

  /** New key with the same buyer, plan, seats and end date; the old key is turned off in the same transaction. */
  async reissue(id, { actor = 'admin' } = {}) {
    const old = await this.require(id);
    if (old.replaced_by) throw new PortalError('replaced', 'This key was already re-issued.');
    const days = old.expires ? Math.max(Math.ceil((old.expires - this.now()) / DAY), 1) : null;
    return this.issue({ plan: old.plan, email: old.email, name: old.name, seats: old.seats, days,
      source: 'portal', replaces: old.id, note: old.note, actor });
  }

  async updateNote(id, note, { actor = 'admin' } = {}) {
    await this.require(id);
    await this.db.batch([this.q('UPDATE licenses SET note = ? WHERE id = ?', note ? String(note).slice(0, 500) : null, id),
      this.logStatement(actor, 'note', id)]);
    return this.get(id);
  }

  async removeActivation(id, device, { actor = 'admin' } = {}) {
    await this.require(id);
    await this.db.batch([this.q('DELETE FROM activations WHERE license_id = ? AND device = ?', id, device),
      this.logStatement(actor, 'remove_activation', id, { device })]);
    return this.get(id);
  }

  // Public API used by the app.

  /** A key this server issued, matched by signature and fingerprint. */
  async lookupKey(key) {
    key = cleanKey(key);
    const decoded = await decodeBlob(PREFIX.license, key, this.signer.publicKey);
    if (decoded.error) throw new PortalError(decoded.error, decoded.error === 'malformed' ? 'That is not a ZEUS license key.' : 'This key is not valid.');
    const license = await this.get(decoded.payload.id);
    if (!license || license.fingerprint !== await fingerprint(key)) throw new PortalError('unknown_license', 'This server does not know this key.', 404);
    return license;
  }

  async activate({ key, device, name = null }) {
    device = String(device ?? '');
    if (!/^[0-9a-f]{16}$/.test(device)) throw new PortalError('bad_device', 'Bad device id.');
    const license = await this.lookupKey(key);
    if (license.state === 'revoked') throw new PortalError('revoked', 'This key was turned off.', 403);
    if (license.state === 'expired') throw new PortalError('expired', 'This license has expired.', 403);
    const now = this.now();
    const label = name ? String(name).slice(0, 80) : null;
    const known = license.activations.findIndex((a) => a.device === device);
    if (known >= 0) {
      await this.q('UPDATE activations SET last_seen = ?, name = coalesce(?, name) WHERE license_id = ? AND device = ?', now, label, license.id, device).run();
    } else {
      // Atomic seat check: inserts only while fewer than `seats` Macs hold the key.
      const result = await this.q(`INSERT INTO activations (license_id, device, name, created, last_seen)
        SELECT ?, ?, ?, ?, ? WHERE (SELECT count(*) FROM activations WHERE license_id = ?) < ?`,
      license.id, device, label, now, now, license.id, license.seats).run();
      if (!result.meta?.changes) throw new PortalError('seats_full', 'All seats are in use.', 409);
      await this.log('app', 'activate', license.id, { device, name: label });
    }
    const seat = known >= 0 ? known + 1 : license.used + 1;
    const token = await encodeBlob(PREFIX.activation, { license: license.id, device, issued: now, seat, seats: license.seats }, this.signer.privateKey);
    return { token, seat, seats: license.seats };
  }

  async deactivate({ key, device }) {
    const license = await this.lookupKey(key);
    const result = await this.q('DELETE FROM activations WHERE license_id = ? AND device = ?', license.id, String(device ?? '')).run();
    const freed = (result.meta?.changes ?? 0) > 0;
    if (freed) await this.log('app', 'deactivate', license.id, { device });
    return { freed };
  }

  async revocationList() {
    const ids = (await this.all('SELECT id FROM licenses WHERE status = \'revoked\' ORDER BY id')).map((r) => r.id);
    return encodeBlob(PREFIX.revocations, { issued: this.now(), ids }, this.signer.privateKey);
  }

  // Admin views.

  async audit({ limit = 200, licenseId = null } = {}) {
    return licenseId
      ? this.all('SELECT * FROM audit WHERE license_id = ? ORDER BY id DESC LIMIT ?', licenseId, limit)
      : this.all('SELECT * FROM audit ORDER BY id DESC LIMIT ?', limit);
  }

  async outbox() { return this.all('SELECT * FROM outbox ORDER BY id DESC LIMIT 200'); }

  async markSent(id, { actor = 'admin' } = {}) {
    const row = await this.q('SELECT license_id FROM outbox WHERE id = ?', id).first();
    if (!row) throw new PortalError('not_found', 'No such email.', 404);
    await this.db.batch([this.q('UPDATE outbox SET status = \'sent\' WHERE id = ?', id),
      this.logStatement(actor, 'email_marked_sent', row.license_id, { outbox: id })]);
  }

  async email(id) { return deliveryEmail(await this.require(id), this.config); }

  async csv() {
    const cols = ['id', 'state', 'plan', 'email', 'name', 'seats', 'used', 'issued', 'expires', 'source', 'order_ref',
      'revoke_reason', 'replaced_by', 'fingerprint', 'note', 'key'];
    const iso = (s) => (s ? new Date(s * 1000).toISOString() : '');
    const cell = (v) => {
      const text = v == null ? '' : String(v);
      const safe = /^[=+\-@\t\r]/.test(text) ? `'${text}` : text; // no formula injection in spreadsheets
      return /[",\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
    };
    const rows = await this.list({ limit: 5000 });
    return [cols.join(','), ...rows.map((l) => cols.map((c) => cell(c === 'issued' || c === 'expires' ? iso(l[c]) : l[c])).join(','))].join('\n') + '\n';
  }
}
