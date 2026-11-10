import assert from 'node:assert/strict';
import { test } from 'node:test';
import { device, setup } from './helpers.js';

const req = (path, { method = 'GET', body, headers = {}, cookie } = {}) => new Request(`http://127.0.0.1:8790${path}`, {
  method, body: body ? JSON.stringify(body) : undefined,
  headers: { 'content-type': 'application/json', ...(cookie ? { cookie } : {}), ...headers } });
const portalHeader = { 'x-zeus-portal': '1' };

test('first run sets the passphrase once, then sign-in is required and CSRF header enforced', async () => {
  const { router } = await setup();
  assert.equal((await (await router.handle(req('/api/session'))).json()).setup, true);
  assert.equal((await router.handle(req('/api/licenses'))).status, 401);
  assert.equal((await router.handle(req('/api/setup', { method: 'POST', body: { passphrase: 'short' }, headers: portalHeader }))).status, 400);
  const set = await router.handle(req('/api/setup', { method: 'POST', body: { passphrase: 'correct horse battery' }, headers: portalHeader }));
  assert.equal(set.status, 200);
  assert.equal((await router.handle(req('/api/setup', { method: 'POST', body: { passphrase: 'another long one!' }, headers: portalHeader }))).status, 409);
  assert.equal((await router.handle(req('/api/login', { method: 'POST', body: { passphrase: 'wrong wrong wrong' }, headers: portalHeader }))).status, 401);
  assert.equal((await router.handle(req('/api/login', { method: 'POST', body: { passphrase: 'correct horse battery' } }))).status, 403);
  const login = await router.handle(req('/api/login', { method: 'POST', body: { passphrase: 'correct horse battery' }, headers: portalHeader }));
  const cookie = login.headers.get('set-cookie').split(';')[0];
  assert.match(login.headers.get('set-cookie'), /HttpOnly; SameSite=Strict/);
  assert.equal((await router.handle(req('/api/licenses', { method: 'POST', cookie, body: { email: 'x@y.io' } }))).status, 403);
  const made = await (await router.handle(req('/api/licenses', { method: 'POST', cookie, headers: portalHeader, body: { email: 'x@y.io', plan: 'lifetime', seats: 1 } }))).json();
  assert.equal(made.ok, true);
  assert.match(made.email.body, /Settings, then License/);
  const list = await (await router.handle(req('/api/licenses?q=x%40y', { cookie }))).json();
  assert.equal(list.licenses.length, 1);
  const csv = await router.handle(req('/api/export.csv', { cookie }));
  assert.equal(csv.headers.get('content-type'), 'text/csv; charset=utf-8');
  assert.equal((await router.handle(req('/api/licenses', { cookie: 'zp_session=9999999999.forged' }))).status, 401);
});

test('app API: activate, revocations, public key need no session', async () => {
  const { router, portal, signer } = await setup();
  const l = await portal.issue({ email: 'a@b.io' });
  const act = await (await router.handle(req('/api/v1/activate', { method: 'POST', body: { key: l.key, device, name: 'MacBook' } }))).json();
  assert.equal(act.ok, true); assert.match(act.token, /^ZEUSA1\./);
  const pk = await (await router.handle(req('/api/v1/public-key'))).json();
  assert.equal(pk.publicKey, signer.publicBase64);
  const rv = await (await router.handle(req('/api/v1/revocations'))).json();
  assert.match(rv.list, /^ZEUSR1\./);
  const bad = await router.handle(req('/api/v1/activate', { method: 'POST', body: { key: 'ZEUS1.x.y', device } }));
  assert.equal(bad.status, 400);
});
