// Ed25519, HMAC and passphrase hashing on WebCrypto (standard APIs only, no Node-specific crypto).
// Signed blobs use the exact shape ZeusCore reads: `<PREFIX>.<base64url json>.<base64url signature>`.
const subtle = globalThis.crypto.subtle;
const enc = new TextEncoder();
const dec = new TextDecoder();

const PKCS8_PREFIX = hex('302e020100300506032b657004220420');
export const PREFIX = { license: 'ZEUS1', activation: 'ZEUSA1', revocations: 'ZEUSR1' };

export function hex(text) { return Uint8Array.from(text.match(/../g) ?? [], (h) => parseInt(h, 16)); }
export function toHex(bytes) { return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join(''); }
export function b64(bytes) { let s = ''; for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b); return btoa(s); }
export function fromB64(text) { return Uint8Array.from(atob(text), (c) => c.charCodeAt(0)); }
export function b64url(bytes) { return b64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
export function fromB64url(text) {
  let s = String(text).replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bytes = fromB64(s);
  // Canonical only: unused low bits in the last character would give one key many spellings.
  if (b64url(bytes) !== String(text)) throw new Error('non-canonical base64url');
  return bytes;
}
export function randomBytes(n) { return globalThis.crypto.getRandomValues(new Uint8Array(n)); }

export function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort()
      .filter((k) => value[k] !== undefined && value[k] !== null)
      .map((k) => [k, sortKeys(value[k])]));
  }
  return value;
}

/** A fresh signing key: just the 32-byte seed, base64. Never printed or logged by callers. */
export function generateSeed() { return b64(randomBytes(32)); }

export async function signerFromSeed(seedBase64) {
  const seed = fromB64(seedBase64);
  if (seed.length !== 32) throw new Error('signing key has the wrong length');
  const pkcs8 = new Uint8Array([...PKCS8_PREFIX, ...seed]);
  const privateKey = await subtle.importKey('pkcs8', pkcs8, { name: 'Ed25519' }, true, ['sign']);
  const jwk = await subtle.exportKey('jwk', privateKey);
  const raw = fromB64url(jwk.x);
  const publicKey = await subtle.importKey('raw', raw, { name: 'Ed25519' }, true, ['verify']);
  return { privateKey, publicKey, publicBase64: b64(raw) };
}

export async function publicKeyFromBase64(text) {
  const raw = fromB64(text);
  if (raw.length !== 32) throw new Error('public key has the wrong length');
  return subtle.importKey('raw', raw, { name: 'Ed25519' }, true, ['verify']);
}

export async function encodeBlob(prefix, payload, privateKey) {
  const body = enc.encode(JSON.stringify(sortKeys(payload)));
  const signature = await subtle.sign({ name: 'Ed25519' }, privateKey, body);
  return `${prefix}.${b64url(body)}.${b64url(signature)}`;
}

/** { payload } or { error: 'malformed' | 'bad_signature' }. */
export async function decodeBlob(prefix, text, publicKey) {
  const parts = cleanKey(text).split('.');
  if (parts.length !== 3 || parts[0] !== prefix || !parts[1] || !parts[2]) return { error: 'malformed' };
  let body; let signature;
  try { body = fromB64url(parts[1]); signature = fromB64url(parts[2]); } catch { return { error: 'malformed' }; }
  let valid = false;
  try { valid = await subtle.verify({ name: 'Ed25519' }, publicKey, signature, body); } catch { valid = false; }
  if (!valid) return { error: 'bad_signature' };
  try { return { payload: JSON.parse(dec.decode(body)) }; } catch { return { error: 'malformed' }; }
}

export function cleanKey(text) { return String(text ?? '').replace(/\s+/g, ''); }

export async function sha256Hex(text) { return toHex(await subtle.digest('SHA-256', enc.encode(text))); }

/** Same as ZeusCore `License.fingerprint`: first 6 bytes of SHA-256, hex. */
export async function fingerprint(key) { return (await sha256Hex(cleanKey(key))).slice(0, 12); }

export function licenseID() { return 'L-' + toHex(randomBytes(5)).toUpperCase(); }

export async function hmacHex(secret, data) {
  const key = await subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return toHex(await subtle.sign('HMAC', key, typeof data === 'string' ? enc.encode(data) : data));
}

export function safeEqual(a, b) {
  const x = String(a ?? ''); const y = String(b ?? '');
  if (!x || x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}

// Admin passphrase: PBKDF2-SHA256 (600k rounds, OWASP 2023), "pbkdf2$rounds$salt$hash".
const ROUNDS = 600_000;
async function pbkdf2(passphrase, salt, rounds) {
  const key = await subtle.importKey('raw', enc.encode(passphrase), 'PBKDF2', false, ['deriveBits']);
  return new Uint8Array(await subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: rounds }, key, 256));
}
export async function hashPassphrase(passphrase) {
  const salt = randomBytes(16);
  return ['pbkdf2', ROUNDS, b64(salt), b64(await pbkdf2(passphrase, salt, ROUNDS))].join('$');
}
export async function checkPassphrase(passphrase, stored) {
  const [kind, rounds, salt, hash] = String(stored ?? '').split('$');
  if (kind !== 'pbkdf2' || !salt || !hash) return false;
  const actual = await pbkdf2(String(passphrase ?? ''), fromB64(salt), Number(rounds));
  return safeEqual(b64(actual), hash);
}

/** Stateless admin session: "<expires>.<hmac>". */
export async function makeSession(secret, ttlSeconds, now) {
  const expires = now + ttlSeconds;
  return `${expires}.${await hmacHex(secret, `session:${expires}`)}`;
}
export async function checkSession(secret, token, now) {
  const [expires, mac] = String(token ?? '').split('.');
  if (!expires || !mac || Number(expires) < now) return false;
  return safeEqual(mac, await hmacHex(secret, `session:${expires}`));
}
