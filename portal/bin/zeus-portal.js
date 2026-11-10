#!/usr/bin/env node
// zeus-portal: the ZEUS license portal on this Mac.
//   zeus-portal serve [--port 8790]        web portal at http://127.0.0.1:8790
//   zeus-portal issue --email a@b.com [--plan lifetime|annual|trial|pro] [--name "A B"] [--seats 2] [--days N]
//   zeus-portal list [--q text]            zeus-portal revoke <id> [--reason text]
//   zeus-portal export [file.csv]          zeus-portal public-key
//   zeus-portal passphrase                 set or reset the admin passphrase (typed, hidden)
//   zeus-portal webhook-secret <provider>  read a store's webhook secret from stdin into the keychain
import fs from 'node:fs';
import { hashPassphrase } from '../core/crypto.js';
import { DEFAULT_PORT, HOME, openPortal } from '../local/app.js';
import { startServer } from '../local/server.js';
import { adapters } from '../core/webhooks.js';

const [command = 'help', ...rest] = process.argv.slice(2);
const flag = (name, fallback = null) => { const i = rest.indexOf(`--${name}`); return i >= 0 && rest[i + 1] !== undefined ? rest[i + 1] : fallback; };
const positional = rest.filter((a, i) => !a.startsWith('--') && !(i > 0 && rest[i - 1].startsWith('--')));

function readHidden(prompt) {
  return new Promise((resolve) => {
    process.stdout.write(prompt);
    const stdin = process.stdin;
    if (stdin.isTTY) stdin.setRawMode(true);
    let value = '';
    const onData = (buf) => {
      for (const ch of buf.toString('utf8')) {
        if (ch === '\r' || ch === '\n') { stdin.removeListener('data', onData); if (stdin.isTTY) stdin.setRawMode(false); stdin.pause(); process.stdout.write('\n'); resolve(value); return; }
        if (ch === '\u0003') process.exit(130);
        if (ch === '\u007f') value = value.slice(0, -1); else value += ch;
      }
    };
    stdin.on('data', onData);
    stdin.resume();
  });
}

const { portal, secrets, config } = await openPortal();

switch (command) {
  case 'serve': {
    const port = Number(flag('port', DEFAULT_PORT));
    await startServer({ portal, secrets, config, port });
    console.log(`ZEUS Portal on http://127.0.0.1:${port}  (data ${HOME}, secrets in ${secrets.location})`);
    break;
  }
  case 'issue': {
    const license = await portal.issue({ plan: flag('plan', 'lifetime'), email: flag('email'), name: flag('name'), seats: flag('seats', 1),
      days: flag('days'), note: flag('note'), actor: 'cli' });
    if (rest.includes('--json')) console.log(JSON.stringify({ id: license.id, plan: license.plan, email: license.email, seats: license.seats, expires: license.expires, key: license.key }));
    else console.log(`${license.id}  ${license.plan}  ${license.email}  seats ${license.seats}\n${license.key}`);
    break;
  }
  case 'list': {
    for (const l of await portal.list({ q: flag('q', '') })) console.log([l.id, l.state, l.plan, l.email, `${l.used}/${l.seats}`].join('\t'));
    break;
  }
  case 'revoke': {
    const l = await portal.revoke(positional[0], { reason: flag('reason', 'revoked'), actor: 'cli' });
    console.log(`${l.id} ${l.state}`);
    break;
  }
  case 'export': {
    const csv = await portal.csv();
    if (positional[0]) { fs.writeFileSync(positional[0], csv, { mode: 0o600 }); console.log(`Wrote ${positional[0]}`); } else process.stdout.write(csv);
    break;
  }
  case 'public-key': console.log(portal.signer.publicBase64); break;
  case 'passphrase': {
    const first = await readHidden('New admin passphrase (12+ characters): ');
    const again = await readHidden('Again: ');
    if (first !== again) { console.error('They do not match.'); process.exit(1); }
    if (first.length < 12) { console.error('Use at least 12 characters.'); process.exit(1); }
    await secrets.set('admin.passphrase', await hashPassphrase(first));
    await portal.log('cli', 'passphrase_set');
    console.log('Saved (only a hash is kept, in the Zeus dev keychain).');
    break;
  }
  case 'webhook-secret': {
    const provider = positional[0];
    if (!adapters[provider]) { console.error(`Provider is one of: ${Object.keys(adapters).join(', ')}`); process.exit(2); }
    const secret = process.stdin.isTTY ? await readHidden(`${adapters[provider].title} webhook secret: `) : fs.readFileSync(0, 'utf8').trim();
    await secrets.set(`webhook.${provider}`, secret);
    await portal.log('cli', 'webhook_secret_set', null, { provider });
    console.log(`Saved. Turn it on with "providers.${provider}.enabled": true in ${HOME}/config.json.`);
    break;
  }
  default:
    console.log(fs.readFileSync(new URL(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
}
if (command !== 'serve') process.exit(0);
