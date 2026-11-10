import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decodeBlob, encodeBlob, fromB64url, b64url, generateSeed, PREFIX, signerFromSeed } from '../core/crypto.js';
import { device, setup } from './helpers.js';

test('sign and verify: a lifetime key round-trips with every field', async () => {
  const { portal, signer } = await setup();
  const l = await portal.issue({ plan: 'lifetime', email: 'Ana@Example.com', name: 'Ana Lima', seats: 3 });
  const { payload, error } = await decodeBlob(PREFIX.license, l.key, signer.publicKey);
  assert.equal(error, undefined);
  assert.deepEqual(payload, { email: 'ana@example.com', id: l.id, issued: 1_800_000_000, name: 'Ana Lima', plan: 'lifetime', seats: 3 });
  assert.equal(l.expires, null);
  assert.equal(l.state, 'active');
});

test('tamper rejection: edited payload, foreign key and junk all fail', async () => {
  const { portal, signer } = await setup();
  const l = await portal.issue({ plan: 'trial', email: 'a@b.co' });
  const [p, body, sig] = l.key.split('.');
  const forged = JSON.parse(new TextDecoder().decode(fromB64url(body)));
  forged.plan = 'lifetime'; delete forged.expires;
  const tampered = [p, b64url(new TextEncoder().encode(JSON.stringify(forged))), sig].join('.');
  assert.equal((await decodeBlob(PREFIX.license, tampered, signer.publicKey)).error, 'bad_signature');
  const other = await signerFromSeed(generateSeed());
  const foreign = await encodeBlob(PREFIX.license, { id: l.id, email: 'a@b.co', plan: 'lifetime', issued: 1 }, other.privateKey);
  assert.equal((await decodeBlob(PREFIX.license, foreign, signer.publicKey)).error, 'bad_signature');
  await assert.rejects(portal.activate({ key: foreign, device }), { code: 'bad_signature' });
  assert.equal((await decodeBlob(PREFIX.license, 'ZEUS1.nope', signer.publicKey)).error, 'malformed');
  assert.equal((await decodeBlob(PREFIX.license, l.key.replace('ZEUS1', 'ZEUS9'), signer.publicKey)).error, 'malformed');
});

test('expiry: trial is 14 days, annual 365, and expired keys cannot activate', async () => {
  const { portal, clock } = await setup();
  const trial = await portal.issue({ plan: 'trial', email: 't@x.io' });
  const annual = await portal.issue({ plan: 'annual', email: 'y@x.io' });
  assert.equal(trial.expires - trial.issued, 14 * 86_400);
  assert.equal(annual.expires - annual.issued, 365 * 86_400);
  clock.t += 15 * 86_400;
  assert.equal((await portal.get(trial.id)).state, 'expired');
  assert.equal((await portal.get(annual.id)).state, 'active');
  await assert.rejects(portal.activate({ key: trial.key, device }), { code: 'expired' });
});

test('revocation: list is signed, names the key, and blocks activation until restored', async () => {
  const { portal, signer } = await setup();
  const keep = await portal.issue({ email: 'k@x.io' });
  const gone = await portal.issue({ email: 'g@x.io' });
  await portal.revoke(gone.id, { reason: 'refund' });
  const decoded = await decodeBlob(PREFIX.revocations, await portal.revocationList(), signer.publicKey);
  assert.deepEqual(decoded.payload.ids, [gone.id]);
  await assert.rejects(portal.activate({ key: gone.key, device }), { code: 'revoked' });
  await portal.restore(gone.id);
  assert.equal((await portal.activate({ key: gone.key, device })).seat, 1);
  assert.equal((await portal.get(keep.id)).state, 'active');
});

test('re-issue: new key, same buyer and seats, old key turned off and linked', async () => {
  const { portal } = await setup();
  const old = await portal.issue({ plan: 'annual', email: 'r@x.io', seats: 2 });
  const fresh = await portal.reissue(old.id);
  const after = await portal.get(old.id);
  assert.notEqual(fresh.key, old.key);
  assert.equal(fresh.seats, 2);
  assert.equal(fresh.replaces, old.id);
  assert.equal(after.state, 'revoked');
  assert.equal(after.replaced_by, fresh.id);
  await assert.rejects(portal.restore(old.id), { code: 'replaced' });
});

test('seats: activation counts Macs, same Mac is free, full key says so, deactivate frees', async () => {
  const { portal, signer } = await setup();
  const l = await portal.issue({ email: 's@x.io', seats: 2 });
  const one = await portal.activate({ key: l.key, device: '0000000000000001', name: 'Studio' });
  assert.equal(one.seat, 1);
  const token = await decodeBlob(PREFIX.activation, one.token, signer.publicKey);
  assert.equal(token.payload.device, '0000000000000001');
  assert.equal((await portal.activate({ key: l.key, device: '0000000000000001' })).seat, 1);
  assert.equal((await portal.activate({ key: l.key, device: '0000000000000002' })).seat, 2);
  await assert.rejects(portal.activate({ key: l.key, device: '0000000000000003' }), { code: 'seats_full' });
  assert.equal((await portal.deactivate({ key: l.key, device: '0000000000000001' })).freed, true);
  assert.equal((await portal.activate({ key: l.key, device: '0000000000000003' })).seats, 2);
  await assert.rejects(portal.activate({ key: l.key, device: 'nope' }), { code: 'bad_device' });
});

test('CSV export neutralises spreadsheet formulas', async () => {
  const { portal } = await setup();
  await portal.issue({ email: 'c@x.io', name: '=HYPERLINK("http://evil")' });
  const csv = await portal.csv();
  assert.match(csv, /"'=HYPERLINK\(""http:\/\/evil""\)"/);
  assert.equal(csv.split('\n')[0].split(',')[0], 'id');
});

test('tamper rejection: a second spelling of the same signature is refused', async () => {
  const signer = await signerFromSeed(generateSeed());
  const key = await encodeBlob(PREFIX.license, { id: 'L-1', email: 'a@b.co', plan: 'lifetime', issued: 1 }, signer.privateKey);
  // 64 signature bytes leave 4 unused bits in the last base64url character.
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const last = alphabet.indexOf(key.at(-1));
  const twin = key.slice(0, -1) + alphabet[last ^ 1];
  assert.ok((await decodeBlob(PREFIX.license, key, signer.publicKey)).payload);
  assert.equal((await decodeBlob(PREFIX.license, twin, signer.publicKey)).error, 'malformed');
});
