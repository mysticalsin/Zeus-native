// Portal secrets (signing key, admin passphrase hash, session key, webhook secrets) in the Zeus dev keychain.
//
// No password dialogs, ever: items are created by /usr/bin/security itself, so the same tool reads
// them back silently; the zeus-dev keychain (no auto-lock) is unlocked with the password in
// ~/.zeus/devkeychain.pass, fed through stdin so it never appears in a process list.
// Service `com.zeus.portal` on purpose: the ZEUS app loads every item under `com.zeus.app`, and the
// signing key must never be inside the app.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const SERVICE = process.env.ZEUS_PORTAL_SERVICE || 'com.zeus.portal';
const SECURITY = '/usr/bin/security';
const safe = (s) => /^[A-Za-z0-9+/=._$:@-]+$/.test(String(s));

export function devKeychainPath() { return path.join(os.homedir(), 'Library/Keychains/zeus-dev.keychain-db'); }
function passwordFile() {
  return [path.join(os.homedir(), '.zeus/devkeychain.pass'), path.join(os.homedir(), '.zeus-dev/codesign/keychain-pass')]
    .find((f) => { try { fs.accessSync(f, fs.constants.R_OK); return true; } catch { return false; } });
}

export class KeychainSecrets {
  constructor({ keychain = devKeychainPath(), service = SERVICE } = {}) {
    this.keychain = keychain; this.service = service; this.cache = new Map(); this.unlocked = false; this.writable = true;
  }
  get location() { return `${path.basename(this.keychain)}, service ${this.service}`; }
  available() { return fs.existsSync(this.keychain); }

  interactive(lines) {
    // `security -i` reads commands from stdin: secrets never go through argv.
    return spawnSync(SECURITY, ['-i'], { input: lines.join('\n') + '\nquit\n', encoding: 'utf8' }).status === 0;
  }

  unlock() {
    if (this.unlocked) return;
    const file = passwordFile();
    if (!file) throw new Error('The Zeus dev keychain password file is missing (~/.zeus/devkeychain.pass).');
    const password = fs.readFileSync(file, 'utf8').trim();
    if (!safe(password)) throw new Error('The Zeus dev keychain password has characters the portal cannot pass safely.');
    this.interactive([`unlock-keychain -p ${password} "${this.keychain}"`]);
    this.unlocked = true;
  }

  async get(account) {
    if (this.cache.has(account)) return this.cache.get(account);
    this.unlock();
    const run = spawnSync(SECURITY, ['find-generic-password', '-s', this.service, '-a', account, '-w', this.keychain], { encoding: 'utf8' });
    const value = run.status === 0 ? run.stdout.replace(/\n$/, '') : '';
    if (value) this.cache.set(account, value);
    return value || null;
  }

  async set(account, value) {
    if (!safe(value) || !safe(account)) throw new Error('Secret has unsupported characters.');
    this.unlock();
    this.interactive([`add-generic-password -U -s ${this.service} -a ${account} -l "ZEUS Portal" -T ${SECURITY} -w ${value} "${this.keychain}"`]);
    const check = spawnSync(SECURITY, ['find-generic-password', '-s', this.service, '-a', account, this.keychain]);
    if (check.status !== 0) throw new Error('Could not save to the Zeus dev keychain.');
    this.cache.set(account, value);
  }

  async remove(account) {
    this.unlock();
    spawnSync(SECURITY, ['delete-generic-password', '-s', this.service, '-a', account, this.keychain]);
    this.cache.delete(account);
  }
}

/** For tests and throwaway runs. */
export class MemorySecrets {
  constructor(initial = {}) { this.items = new Map(Object.entries(initial)); this.writable = true; }
  get location() { return 'memory'; }
  available() { return true; }
  async get(account) { return this.items.get(account) ?? null; }
  async set(account, value) { this.items.set(account, value); }
  async remove(account) { this.items.delete(account); }
}
