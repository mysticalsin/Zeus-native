import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setup, sign } from './helpers.js';

const post = (router, provider, raw, headers) => router.handle(new Request(`http://127.0.0.1/webhooks/${provider}`, { method: 'POST', body: raw, headers }));

function lemon(id = 9001, event = 'order_created') {
  return JSON.stringify({ meta: { event_name: event }, data: { id, attributes: { status: 'paid', user_email: 'buyer@shop.io', user_name: 'Bea Buyer', updated_at: 'x',
    first_order_item: { variant_id: 111, quantity: 1 } } } });
}

test('Lemon Squeezy: signed order issues one key and one delivery email; replay is idempotent', async () => {
  const { router, portal } = await setup();
  const raw = lemon();
  const headers = { 'x-signature': await sign('ls_secret_123', raw) };
  const first = await (await post(router, 'lemonsqueezy', raw, headers)).json();
  assert.equal(first.ok, true);
  const again = await (await post(router, 'lemonsqueezy', raw, headers)).json();
  assert.equal(again.duplicate, true);
  assert.equal(again.license, first.license);
  const all = await portal.list();
  assert.equal(all.length, 1);
  assert.equal(all[0].seats, 2);
  assert.equal(all[0].email, 'buyer@shop.io');
  const outbox = await portal.outbox();
  assert.equal(outbox.length, 1);
  assert.match(outbox[0].body, /ZEUS1\./);
  assert.match(outbox[0].body, /Hi Bea,/);
});

test('Lemon Squeezy: bad signature is 401 and stores nothing; refund turns the key off', async () => {
  const { router, portal } = await setup();
  const raw = lemon(42);
  assert.equal((await post(router, 'lemonsqueezy', raw, { 'x-signature': 'deadbeef' })).status, 401);
  assert.equal((await portal.list()).length, 0);
  await post(router, 'lemonsqueezy', raw, { 'x-signature': await sign('ls_secret_123', raw) });
  const refund = lemon(42, 'order_refunded');
  const res = await (await post(router, 'lemonsqueezy', refund, { 'x-signature': await sign('ls_secret_123', refund) })).json();
  assert.equal((await portal.get(res.license)).state, 'revoked');
});

test('Stripe: v1 signature with timestamp; stale timestamp rejected; same order under a new event id reuses the key', async () => {
  const { router, portal, clock } = await setup();
  const event = (id) => JSON.stringify({ id, type: 'checkout.session.completed', data: { object: { id: 'cs_1', payment_intent: 'pi_1', payment_status: 'paid',
    customer_details: { email: 'S@x.io', name: 'Sam' } } } });
  const header = async (raw, t = clock.t) => ({ 'stripe-signature': `t=${t},v1=${await sign('whsec_123456', `${t}.${raw}`)}` });
  const raw1 = event('evt_1');
  assert.equal((await post(router, 'stripe', raw1, await header(raw1, clock.t - 1000))).status, 401);
  const a = await (await post(router, 'stripe', raw1, await header(raw1))).json();
  const raw2 = event('evt_2');
  const b = await (await post(router, 'stripe', raw2, await header(raw2))).json();
  assert.equal(a.license, b.license);
  assert.equal((await portal.list()).length, 1);
});

test('Paddle: ts;h1 signature over ts:body', async () => {
  const { router, portal, clock } = await setup();
  const raw = JSON.stringify({ event_id: 'evt_p1', event_type: 'transaction.completed', data: { id: 'txn_1', custom_data: { email: 'p@x.io' }, items: [{ price: { id: 'pri_1' }, quantity: 1 }] } });
  const res = await post(router, 'paddle', raw, { 'paddle-signature': `ts=${clock.t};h1=${await sign('pdl_secret_123', `${clock.t}:${raw}`)}` });
  assert.equal(res.status, 200);
  assert.equal((await portal.list())[0].email, 'p@x.io');
});

test('Generic: plan and seats from the event; provider off is 404; missing secret is 503', async () => {
  const { router, portal, secrets, config } = await setup();
  const raw = JSON.stringify({ event_id: 'g1', type: 'order.paid', order_id: 'o1', email: 'g@x.io', plan: 'annual', seats: 3 });
  await post(router, 'generic', raw, { 'x-zeus-signature': await sign('generic_secret_1', raw) });
  const l = (await portal.list())[0];
  assert.equal(l.plan, 'annual'); assert.equal(l.seats, 3);
  config.providers.paddle.enabled = false;
  assert.equal((await post(router, 'paddle', '{}', {})).status, 404);
  await secrets.remove('webhook.stripe');
  assert.equal((await post(router, 'stripe', '{}', {})).status, 503);
});

test('Failed processing releases the event so the store can retry', async () => {
  const { router, portal } = await setup();
  const raw = JSON.stringify({ event_id: 'g2', type: 'order.paid', order_id: 'o2', email: '' });
  const headers = { 'x-zeus-signature': await sign('generic_secret_1', raw) };
  assert.equal((await post(router, 'generic', raw, headers)).status, 422);
  const row = await portal.q('SELECT count(*) AS n FROM webhook_events').first();
  assert.equal(row.n, 0);
});
