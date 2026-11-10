// Wires the portal for this Mac: data in ~/.zeus-portal, secrets in the Zeus dev keychain.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { generateSeed, signerFromSeed } from '../core/crypto.js';
import { Portal } from '../core/portal.js';
import { LocalD1 } from './d1.js';
import { KeychainSecrets, MemorySecrets } from './keychain.js';

export const HOME = process.env.ZEUS_PORTAL_HOME || path.join(os.homedir(), '.zeus-portal');
export const DEFAULT_PORT = Number(process.env.ZEUS_PORTAL_PORT || 8790);

export const DEFAULT_CONFIG = {
  productName: 'ZEUS',
  supportEmail: '',
  downloadURL: '',
  // Purchases: all off until a store is chosen. Webhook secrets live in the keychain, not here.
  providers: { lemonsqueezy: { enabled: false }, paddle: { enabled: false }, stripe: { enabled: false }, generic: { enabled: false } },
  // Store product or price id -> what to issue, per provider. Example: { "lemonsqueezy": { "123456": { "plan": "lifetime", "seats": 2 } } }
  products: {},
  defaultProduct: { plan: 'lifetime', seats: 2 },
};

export function loadConfig(home = HOME) {
  fs.mkdirSync(home, { recursive: true, mode: 0o700 });
  const file = path.join(home, 'config.json');
  if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify(DEFAULT_CONFIG, null, 2) + '\n', { mode: 0o600 });
  const loaded = JSON.parse(fs.readFileSync(file, 'utf8'));
  return { ...DEFAULT_CONFIG, ...loaded, providers: { ...DEFAULT_CONFIG.providers, ...(loaded.providers ?? {}) } };
}

export function makeSecrets() {
  if (process.env.ZEUS_PORTAL_SECRETS === 'memory') return new MemorySecrets();
  const secrets = new KeychainSecrets();
  if (!secrets.available()) throw new Error('The Zeus dev keychain is missing (~/Library/Keychains/zeus-dev.keychain-db). Run scripts/make-dev-identity.sh first.');
  return secrets;
}

/** The signing key, created once in the keychain. Only the public half ever leaves it. */
export async function loadSigner(secrets, home = HOME) {
  let seed = await secrets.get('signing.ed25519');
  if (!seed) {
    seed = generateSeed();
    await secrets.set('signing.ed25519', seed);
  }
  const signer = await signerFromSeed(seed);
  seed = null;
  fs.writeFileSync(path.join(home, 'public-key.txt'), signer.publicBase64 + '\n', { mode: 0o644 });
  return signer;
}

export async function openPortal({ home = HOME } = {}) {
  const config = loadConfig(home);
  const secrets = makeSecrets();
  const signer = await loadSigner(secrets, home);
  const db = new LocalD1(path.join(home, 'portal.sqlite'));
  return { portal: new Portal({ db, signer, config }), secrets, config, db };
}
