// node:sqlite with D1's API (prepare().bind().first()/all()/run(), batch() in one transaction),
// so the portal core runs the same SQL locally and on Cloudflare D1.
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { SCHEMA } from '../core/schema.js';

class Statement {
  constructor(db, sql, args = []) { this.db = db; this.sql = sql; this.args = args; }
  bind(...args) { return new Statement(this.db, this.sql, args.map((a) => (a === undefined ? null : a))); }
  stmt() { return this.db.prepare(this.sql); }
  async first() { const row = this.stmt().get(...this.args); return row ? { ...row } : null; }
  async all() { return { results: this.stmt().all(...this.args).map((r) => ({ ...r })), success: true }; }
  async run() { const r = this.stmt().run(...this.args); return { success: true, meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } }; }
  runSync() { const r = this.stmt().run(...this.args); return { success: true, meta: { changes: Number(r.changes) } }; }
}

export class LocalD1 {
  constructor(file) {
    if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(file);
    this.db.exec('PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 3000;');
    this.db.exec(SCHEMA);
    if (file !== ':memory:') { for (const f of [file, `${file}-wal`, `${file}-shm`]) { try { fs.chmodSync(f, 0o600); } catch { /* not yet */ } } }
  }
  prepare(sql) { return new Statement(this.db, sql); }
  async batch(statements) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const out = statements.map((s) => s.runSync());
      this.db.exec('COMMIT');
      return out;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  close() { this.db.close(); }
}
