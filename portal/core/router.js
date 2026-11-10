// HTTP routes on the Fetch API (Request -> Response) (portable: no Node-only APIs).
import { b64, checkPassphrase, checkSession, hashPassphrase, makeSession, randomBytes } from './crypto.js';
import { PortalError } from './portal.js';
import { adapters, handleWebhook } from './webhooks.js';

const SESSION_TTL = 12 * 3600;
const COOKIE = 'zp_session';
const MAX_BODY = 256 * 1024;

const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers },
});
const fail = (code, message, status = 400) => json({ ok: false, error: code, message }, status);

/** Small fixed-window limiter. Per process. The portal listens on 127.0.0.1 only. */
export class Limiter {
  constructor(limit, windowSeconds) { this.limit = limit; this.window = windowSeconds * 1000; this.hits = new Map(); }
  allow(key) {
    const now = Date.now();
    const entry = this.hits.get(key);
    if (!entry || now - entry.start > this.window) { this.hits.set(key, { start: now, count: 1 }); return true; }
    entry.count += 1;
    if (this.hits.size > 5000) this.hits.clear();
    return entry.count <= this.limit;
  }
}

function cookie(request, name) {
  const header = request.headers.get('cookie') ?? '';
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return v.join('=');
  }
  return null;
}

async function readBody(request) {
  const text = await request.text();
  if (text.length > MAX_BODY) throw new PortalError('too_large', 'Request too large.', 413);
  return text;
}
async function readJSON(request) {
  const text = await readBody(request);
  try { return text ? JSON.parse(text) : {}; } catch { throw new PortalError('bad_json', 'Bad JSON.'); }
}

/**
 * secrets: { get(name) -> Promise<string|null>, set?(name, value), writable: boolean }
 * Accounts used: admin.passphrase (hash only), session.key, webhook.<provider>.
 */
export function createRouter({ portal, secrets, config, serveStatic = null, publicBase = '' }) {
  const loginLimiter = new Limiter(8, 300);
  const publicLimiter = new Limiter(60, 60);
  const ip = (request) => request.headers.get('cf-connecting-ip') ?? request.headers.get('x-forwarded-for') ?? 'local';

  async function sessionKey() {
    let key = await secrets.get('session.key');
    if (!key && secrets.writable) { key = b64(randomBytes(32)); await secrets.set('session.key', key); }
    return key;
  }
  async function signedIn(request) {
    const key = await sessionKey();
    return Boolean(key) && checkSession(key, cookie(request, COOKIE), portal.now());
  }
  function sessionCookie(request, value, maxAge) {
    const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
    return `${COOKIE}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${maxAge}${secure}`;
  }

  async function admin(request, url, parts) {
    // CSRF: admin calls must carry this header, which a cross-site form cannot set, plus a SameSite=Strict cookie.
    if (request.method !== 'GET' && request.headers.get('x-zeus-portal') !== '1') return fail('csrf', 'Missing portal header.', 403);
    if (!(await signedIn(request))) return fail('signed_out', 'Sign in first.', 401);
    const [, , resource, id, action, extra] = parts; // ['', 'api', resource, id, action, extra]
    const method = request.method;

    if (resource === 'stats' && method === 'GET') return json({ ok: true, stats: await portal.stats() });
    if (resource === 'licenses' && !id && method === 'GET') {
      return json({ ok: true, licenses: await portal.list({ q: url.searchParams.get('q') ?? '', state: url.searchParams.get('state') ?? '' }) });
    }
    if (resource === 'licenses' && !id && method === 'POST') {
      const body = await readJSON(request);
      const license = await portal.issue({ plan: body.plan, email: body.email, name: body.name, seats: body.seats ?? 1,
        days: body.days, note: body.note, queueEmail: Boolean(body.queueEmail) });
      return json({ ok: true, license, email: await portal.email(license.id) }, 201);
    }
    if (resource === 'licenses' && id && !action && method === 'GET') {
      const license = await portal.require(id);
      return json({ ok: true, license, email: await portal.email(id), audit: await portal.audit({ licenseId: id, limit: 50 }) });
    }
    if (resource === 'licenses' && id && method === 'POST') {
      const body = await readJSON(request);
      if (action === 'revoke') return json({ ok: true, license: await portal.revoke(id, { reason: body.reason || 'revoked' }) });
      if (action === 'restore') return json({ ok: true, license: await portal.restore(id) });
      if (action === 'reissue') {
        const license = await portal.reissue(id);
        return json({ ok: true, license, email: await portal.email(license.id) });
      }
      if (action === 'note') return json({ ok: true, license: await portal.updateNote(id, body.note) });
    }
    if (resource === 'licenses' && id && action === 'activations' && extra && method === 'DELETE') {
      return json({ ok: true, license: await portal.removeActivation(id, decodeURIComponent(extra)) });
    }
    if (resource === 'export.csv' && method === 'GET') {
      await portal.log('admin', 'export_csv');
      return new Response(await portal.csv(), { headers: { 'content-type': 'text/csv; charset=utf-8',
        'content-disposition': `attachment; filename="zeus-licenses-${new Date().toISOString().slice(0, 10)}.csv"`, 'cache-control': 'no-store' } });
    }
    if (resource === 'audit' && method === 'GET') return json({ ok: true, audit: await portal.audit({ limit: 300 }) });
    if (resource === 'outbox' && !id && method === 'GET') return json({ ok: true, outbox: await portal.outbox() });
    if (resource === 'outbox' && id && action === 'sent' && method === 'POST') { await portal.markSent(Number(id)); return json({ ok: true }); }
    if (resource === 'settings' && method === 'GET') {
      const providers = [];
      for (const [name, adapter] of Object.entries(adapters)) {
        providers.push({ name, title: adapter.title, enabled: Boolean(config.providers?.[name]?.enabled),
          secretSet: Boolean(await secrets.get(`webhook.${name}`)), url: `${publicBase || url.origin}/webhooks/${name}` });
      }
      return json({ ok: true, publicKey: portal.signer.publicBase64, secretsWritable: secrets.writable, secretStore: secrets.location,
        providers, products: config.products ?? {}, defaultProduct: config.defaultProduct ?? { plan: 'lifetime', seats: 2 } });
    }
    if (resource === 'settings' && id === 'webhook-secret' && method === 'POST') {
      if (!secrets.writable) return fail('read_only', 'This secret store is read-only.', 409);
      const body = await readJSON(request);
      if (!adapters[body.provider]) return fail('bad_provider', 'Unknown provider.');
      if (!/^[A-Za-z0-9_\-.:+/=]{8,256}$/.test(String(body.secret ?? ''))) return fail('bad_secret', 'That secret looks wrong.');
      await secrets.set(`webhook.${body.provider}`, body.secret);
      await portal.log('admin', 'webhook_secret_set', null, { provider: body.provider });
      return json({ ok: true });
    }
    return fail('not_found', 'No such route.', 404);
  }

  async function handle(request) {
    const url = new URL(request.url);
    const parts = url.pathname.split('/');
    try {
      if (url.pathname === '/healthz') return json({ ok: true });

      // App-facing API (no admin session).
      if (url.pathname.startsWith('/api/v1/')) {
        if (!publicLimiter.allow(ip(request))) return fail('rate_limited', 'Slow down.', 429);
        if (url.pathname === '/api/v1/activate' && request.method === 'POST') {
          const body = await readJSON(request);
          return json({ ok: true, ...(await portal.activate({ key: body.key, device: body.device, name: body.name })) });
        }
        if (url.pathname === '/api/v1/deactivate' && request.method === 'POST') {
          const body = await readJSON(request);
          return json({ ok: true, ...(await portal.deactivate({ key: body.key, device: body.device })) });
        }
        if (url.pathname === '/api/v1/revocations' && request.method === 'GET') return json({ ok: true, list: await portal.revocationList() });
        if (url.pathname === '/api/v1/public-key' && request.method === 'GET') return json({ ok: true, publicKey: portal.signer.publicBase64 });
        return fail('not_found', 'No such route.', 404);
      }

      if (parts[1] === 'webhooks' && request.method === 'POST' && parts[2]) {
        const raw = await readBody(request);
        const result = await handleWebhook({ provider: parts[2], raw, headers: request.headers, portal, config, getSecret: (n) => secrets.get(n) });
        return json(result.body, result.status);
      }

      if (url.pathname === '/api/session' && request.method === 'GET') {
        return json({ ok: true, setup: !(await secrets.get('admin.passphrase')), signedIn: await signedIn(request), writable: secrets.writable });
      }
      if (url.pathname === '/api/setup' && request.method === 'POST') {
        if (request.headers.get('x-zeus-portal') !== '1') return fail('csrf', 'Missing portal header.', 403);
        if (await secrets.get('admin.passphrase')) return fail('already_set', 'The passphrase is already set.', 409);
        if (!secrets.writable) return fail('read_only', 'This secret store is read-only.', 409);
        const { passphrase } = await readJSON(request);
        if (String(passphrase ?? '').length < 12) return fail('weak', 'Use at least 12 characters.');
        await secrets.set('admin.passphrase', await hashPassphrase(passphrase));
        await portal.log('admin', 'passphrase_set');
        const token = await makeSession(await sessionKey(), SESSION_TTL, portal.now());
        return json({ ok: true }, 200, { 'set-cookie': sessionCookie(request, token, SESSION_TTL) });
      }
      if (url.pathname === '/api/login' && request.method === 'POST') {
        if (request.headers.get('x-zeus-portal') !== '1') return fail('csrf', 'Missing portal header.', 403);
        if (!loginLimiter.allow(ip(request))) return fail('rate_limited', 'Too many tries. Wait five minutes.', 429);
        const { passphrase } = await readJSON(request);
        const stored = await secrets.get('admin.passphrase');
        if (!stored || !(await checkPassphrase(passphrase, stored))) {
          await portal.log('admin', 'login_failed');
          return fail('bad_passphrase', 'That passphrase is not right.', 401);
        }
        await portal.log('admin', 'login');
        const token = await makeSession(await sessionKey(), SESSION_TTL, portal.now());
        return json({ ok: true }, 200, { 'set-cookie': sessionCookie(request, token, SESSION_TTL) });
      }
      if (url.pathname === '/api/logout' && request.method === 'POST') {
        return json({ ok: true }, 200, { 'set-cookie': sessionCookie(request, '', 0) });
      }
      if (parts[1] === 'api') return await admin(request, url, parts);

      if (serveStatic) return await serveStatic(request);
      return fail('not_found', 'No such route.', 404);
    } catch (error) {
      if (error instanceof PortalError) return fail(error.code, error.message, error.status);
      console.error('portal error', error?.message);
      return fail('server_error', 'Something went wrong.', 500);
    }
  }

  return { handle };
}

export const securityHeaders = {
  'content-security-policy': "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
};
