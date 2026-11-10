import { generateSeed, hmacHex, signerFromSeed } from '../core/crypto.js';
import { Portal } from '../core/portal.js';
import { createRouter } from '../core/router.js';
import { LocalD1 } from '../local/d1.js';
import { MemorySecrets } from '../local/keychain.js';

export async function setup({ now = 1_800_000_000, config = {} } = {}) {
  const clock = { t: now };
  const signer = await signerFromSeed(generateSeed());
  const db = new LocalD1(':memory:');
  const cfg = { productName: 'ZEUS', providers: { lemonsqueezy: { enabled: true }, paddle: { enabled: true }, stripe: { enabled: true }, generic: { enabled: true } },
    products: { lemonsqueezy: { 111: { plan: 'lifetime', seats: 2 } } }, defaultProduct: { plan: 'lifetime', seats: 2 }, ...config };
  const portal = new Portal({ db, signer, config: cfg, now: () => clock.t });
  const secrets = new MemorySecrets({ 'webhook.lemonsqueezy': 'ls_secret_123', 'webhook.paddle': 'pdl_secret_123', 'webhook.stripe': 'whsec_123456', 'webhook.generic': 'generic_secret_1' });
  const router = createRouter({ portal, secrets, config: cfg });
  return { clock, signer, db, portal, secrets, router, config: cfg };
}

export const sign = hmacHex;
export const device = 'a1b2c3d4e5f60718';
