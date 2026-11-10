// Purchase to license, for any store. Each adapter only knows how to check its provider's
// signature and read its order and refund events; issuing, storing and the delivery email are
// shared. Nothing here signs up for, calls or pays any provider: they are off until configured.
import { hmacHex, safeEqual } from './crypto.js';
import { PortalError } from './portal.js';

const TOLERANCE = 300; // seconds, for providers that sign a timestamp

function header(headers, name) { return headers.get ? headers.get(name) : headers[name.toLowerCase()]; }
function pairs(text, sep) {
  return Object.fromEntries(String(text ?? '').split(sep).map((p) => p.trim().split('=')).filter((p) => p.length >= 2)
    .map(([k, ...v]) => [k, v.join('=')]));
}

export const adapters = {
  // Lemon Squeezy: X-Signature is hex HMAC-SHA256 of the raw body.
  lemonsqueezy: {
    title: 'Lemon Squeezy',
    async verify(raw, headers, secret) { return safeEqual(header(headers, 'x-signature'), await hmacHex(secret, raw)); },
    parse(event) {
      const name = event?.meta?.event_name;
      const data = event?.data ?? {};
      const a = data.attributes ?? {};
      const eventId = `${name}:${data.id}:${a.updated_at ?? ''}`;
      if (name === 'order_created' && a.status === 'paid') {
        return { kind: 'order', eventId, orderRef: String(data.id), email: a.user_email, name: a.user_name,
          product: String(a.first_order_item?.variant_id ?? ''), quantity: a.first_order_item?.quantity ?? 1 };
      }
      if (name === 'order_refunded') return { kind: 'refund', eventId, orderRef: String(data.id) };
      return { kind: 'ignore', eventId };
    },
  },
  // Paddle Billing: Paddle-Signature "ts=...;h1=..." over "<ts>:<raw body>".
  paddle: {
    title: 'Paddle',
    async verify(raw, headers, secret, now) {
      const { ts, h1 } = pairs(header(headers, 'paddle-signature'), ';');
      if (!ts || Math.abs(now - Number(ts)) > TOLERANCE) return false;
      return safeEqual(h1, await hmacHex(secret, `${ts}:${raw}`));
    },
    parse(event) {
      const data = event?.data ?? {};
      if (event?.event_type === 'transaction.completed') {
        // Paddle sends a customer id, not the email: the checkout passes it in custom_data.
        return { kind: 'order', eventId: event.event_id, orderRef: String(data.id), email: data.custom_data?.email ?? data.customer?.email,
          name: data.custom_data?.name ?? data.customer?.name, product: String(data.items?.[0]?.price?.id ?? ''), quantity: data.items?.[0]?.quantity ?? 1 };
      }
      if (event?.event_type === 'adjustment.created' && data.action === 'refund') {
        return { kind: 'refund', eventId: event.event_id, orderRef: String(data.transaction_id) };
      }
      return { kind: 'ignore', eventId: event?.event_id };
    },
  },
  // Stripe: Stripe-Signature "t=...,v1=..." over "<t>.<raw body>".
  stripe: {
    title: 'Stripe',
    async verify(raw, headers, secret, now) {
      const parts = String(header(headers, 'stripe-signature') ?? '').split(',').map((p) => p.trim().split('='));
      const t = parts.find(([k]) => k === 't')?.[1];
      const v1 = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
      if (!t || !v1.length || Math.abs(now - Number(t)) > TOLERANCE) return false;
      const expected = await hmacHex(secret, `${t}.${raw}`);
      return v1.some((v) => safeEqual(v, expected));
    },
    parse(event) {
      const o = event?.data?.object ?? {};
      if (event?.type === 'checkout.session.completed' && o.payment_status === 'paid') {
        return { kind: 'order', eventId: event.id, orderRef: String(o.payment_intent ?? o.id), email: o.customer_details?.email ?? o.customer_email,
          name: o.customer_details?.name, product: String(o.metadata?.zeus_product ?? ''), quantity: 1 };
      }
      if (event?.type === 'charge.refunded') return { kind: 'refund', eventId: event.id, orderRef: String(o.payment_intent) };
      return { kind: 'ignore', eventId: event?.id };
    },
  },
  // Any other store, Zapier or a manual script: X-Zeus-Signature is hex HMAC-SHA256 of the raw body.
  generic: {
    title: 'Generic',
    async verify(raw, headers, secret) { return safeEqual(header(headers, 'x-zeus-signature'), await hmacHex(secret, raw)); },
    parse(event) {
      if (event?.type === 'order.paid') {
        return { kind: 'order', eventId: event.event_id, orderRef: String(event.order_id), email: event.email, name: event.name,
          product: String(event.product ?? ''), quantity: 1, plan: event.plan, seats: event.seats };
      }
      if (event?.type === 'order.refunded') return { kind: 'refund', eventId: event.event_id, orderRef: String(event.order_id) };
      return { kind: 'ignore', eventId: event?.event_id };
    },
  },
};

/** What a product id maps to, from config.products[provider][product]; falls back to config.defaultProduct. */
export function productFor(config, provider, parsed) {
  const mapped = config.products?.[provider]?.[parsed.product];
  const fallback = config.defaultProduct ?? { plan: 'lifetime', seats: 2 };
  const pick = mapped ?? (provider === 'generic' && parsed.plan ? { plan: parsed.plan, seats: parsed.seats ?? fallback.seats } : fallback);
  return { plan: pick.plan, seats: (pick.seats ?? 1) * Math.max(Number(parsed.quantity) || 1, 1), days: pick.days ?? null };
}

/**
 * Verifies, de-duplicates and processes one webhook. Returns { status, body }.
 * Idempotent twice over: by (provider, event id) and by (provider, order id).
 */
export async function handleWebhook({ provider, raw, headers, portal, config, getSecret }) {
  const adapter = adapters[provider];
  if (!adapter || !config.providers?.[provider]?.enabled) return { status: 404, body: { ok: false, error: 'provider_off' } };
  const secret = await getSecret(`webhook.${provider}`);
  if (!secret) return { status: 503, body: { ok: false, error: 'no_secret' } };
  const now = portal.now();
  if (!(await adapter.verify(raw, headers, secret, now))) return { status: 401, body: { ok: false, error: 'bad_signature' } };
  let event;
  try { event = JSON.parse(raw); } catch { return { status: 400, body: { ok: false, error: 'bad_json' } }; }
  const parsed = adapter.parse(event);
  if (!parsed.eventId) return { status: 400, body: { ok: false, error: 'no_event_id' } };

  const claim = await portal.q('INSERT OR IGNORE INTO webhook_events (provider, event_id, received, kind) VALUES (?, ?, ?, ?)',
    provider, parsed.eventId, now, parsed.kind).run();
  if (!claim.meta?.changes) {
    const seen = await portal.q('SELECT status, license_id FROM webhook_events WHERE provider = ? AND event_id = ?', provider, parsed.eventId).first();
    if (seen?.status === 'processing') return { status: 409, body: { ok: false, error: 'in_progress' } };
    return { status: 200, body: { ok: true, duplicate: true, license: seen?.license_id ?? null } };
  }
  try {
    let licenseId = null;
    if (parsed.kind === 'order') {
      const existing = await portal.findByOrder(provider, parsed.orderRef);
      if (existing) {
        licenseId = existing.id;
      } else {
        if (!parsed.email) throw new PortalError('no_email', 'The order has no buyer email.');
        const product = productFor(config, provider, parsed);
        const license = await portal.issue({ ...product, email: parsed.email, name: parsed.name, source: provider,
          orderRef: parsed.orderRef, actor: `webhook:${provider}`, queueEmail: true });
        licenseId = license.id;
      }
    } else if (parsed.kind === 'refund') {
      const license = await portal.findByOrder(provider, parsed.orderRef);
      if (license) { await portal.revoke(license.id, { reason: 'refunded', actor: `webhook:${provider}` }); licenseId = license.id; }
    }
    await portal.q('UPDATE webhook_events SET status = \'done\', license_id = ? WHERE provider = ? AND event_id = ?', licenseId, provider, parsed.eventId).run();
    return { status: 200, body: { ok: true, kind: parsed.kind, license: licenseId } };
  } catch (error) {
    // Let the provider retry: forget the claim.
    await portal.q('DELETE FROM webhook_events WHERE provider = ? AND event_id = ?', provider, parsed.eventId).run();
    const status = error instanceof PortalError ? 422 : 500;
    return { status, body: { ok: false, error: error.code ?? 'failed', message: error.message } };
  }
}
