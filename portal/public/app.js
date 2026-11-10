// ZEUS Portal UI. No framework; every value from the server goes in through textContent.
const root = document.getElementById('root');
const state = { view: 'licenses', q: '', filter: '', detail: null, stats: null };

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs ?? {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else if (k === 'style') el.style.cssText = v; // CSSOM, allowed by the CSP (no inline style attributes)
    else if (k === 'checked') el.checked = Boolean(v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return el;
}

async function api(path, { method = 'GET', body } = {}) {
  const res = await fetch(path, { method, headers: { 'x-zeus-portal': '1', ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined, credentials: 'same-origin' });
  const data = res.headers.get('content-type')?.includes('json') ? await res.json() : await res.text();
  if (res.status === 401 && data.error === 'signed_out') { render(); throw new Error('Signed out'); }
  if (!res.ok) throw new Error(data.message || 'Something went wrong.');
  return data;
}

let toastTimer;
function toast(text) {
  const el = document.getElementById('toast');
  el.textContent = text; el.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('show'), 2200);
}
async function copy(text, what) { await navigator.clipboard.writeText(text); toast(`${what} copied`); }

const PLAN = { lifetime: 'Lifetime', annual: 'Annual', trial: 'Trial', pro: 'Pro' };
const date = (s) => (s ? new Date(s * 1000).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : '');
const dateTime = (s) => new Date(s * 1000).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
const pill = (s) => h('span', { class: `pill ${s}` }, { active: 'Active', revoked: 'Turned off', expired: 'Expired' }[s] ?? s);
const ends = (l) => (l.expires ? `Until ${date(l.expires)}` : 'Never ends');

// Sign in / first run.
async function renderLogin(setup) {
  const pass = h('input', { class: 'input', type: 'password', placeholder: setup ? 'At least 12 characters' : 'Admin passphrase', autocomplete: setup ? 'new-password' : 'current-password' });
  const again = setup ? h('input', { class: 'input', type: 'password', placeholder: 'Type it again', autocomplete: 'new-password' }) : null;
  const error = h('div', { class: 'error' });
  const submit = async (e) => {
    e.preventDefault(); error.textContent = '';
    if (setup && pass.value !== again.value) { error.textContent = 'The two passphrases do not match.'; return; }
    try { await api(setup ? '/api/setup' : '/api/login', { method: 'POST', body: { passphrase: pass.value } }); render(); }
    catch (err) { error.textContent = err.message; }
  };
  root.replaceChildren(h('div', { class: 'login' }, h('form', { class: 'card stack', onsubmit: submit },
    h('img', { src: '/bolt.svg', alt: '' }),
    h('div', {}, h('h1', {}, setup ? 'Set up ZEUS Portal' : 'ZEUS Portal'),
      h('p', { class: 'sub' }, setup ? 'Choose the admin passphrase. Only a hash is kept, in your Zeus keychain.' : 'Sign in to manage licenses.')),
    pass, again, error, h('button', { class: 'btn primary', type: 'submit' }, setup ? 'Save and open' : 'Sign in'))));
  pass.focus();
}

function shell(content) {
  const nav = (id, label, icon, tint, count) => h('button', { class: `nav ${state.view === id ? 'on' : ''}`, onclick: () => go(id) },
    h('span', { class: 'ico', style: `background:${tint}22;color:${tint}` }, icon), label, count != null ? h('span', { class: 'count' }, count) : null);
  return h('div', { class: 'shell' },
    h('aside', { class: 'sidebar' },
      h('div', { class: 'brand' }, h('img', { src: '/bolt.svg', alt: '' }), h('div', {}, 'ZEUS Portal', h('small', {}, 'Licenses on this Mac'))),
      nav('licenses', 'Licenses', '◆', '#FFC83D', state.stats?.total),
      nav('new', 'New license', '+', '#3CCB7F'),
      nav('outbox', 'Deliveries', '✉', '#F06A93'),
      nav('audit', 'Activity', '◷', '#6B5BFF'),
      nav('settings', 'Settings', '⚙', '#9AA0AE'),
      h('div', { class: 'spacer' }),
      h('button', { class: 'nav', onclick: async () => { await api('/api/logout', { method: 'POST' }); render(); } }, h('span', { class: 'ico' }, '⏻'), 'Sign out')),
    h('main', { class: 'main' }, content));
}

function go(view, detail = null) { state.view = view; state.detail = detail; render(); }

async function viewLicenses() {
  const [{ stats }, { licenses }] = await Promise.all([api('/api/stats'),
    api(`/api/licenses?q=${encodeURIComponent(state.q)}&state=${state.filter}`)]);
  state.stats = stats;
  const search = h('input', { class: 'input', type: 'search', placeholder: 'Search email, name, ID or order', value: state.q });
  let timer;
  search.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(() => { state.q = search.value; render(true); }, 220); });
  const filters = h('div', { class: 'seg' }, ...[['', 'All'], ['active', 'Active'], ['expired', 'Expired'], ['revoked', 'Turned off']]
    .map(([v, t]) => h('button', { class: state.filter === v ? 'on' : '', onclick: () => { state.filter = v; render(); } }, t)));
  const stat = (n, l) => h('div', { class: 'card stat' }, h('div', { class: 'n' }, n), h('div', { class: 'l' }, l));
  const table = licenses.length ? h('table', {},
    h('thead', {}, h('tr', {}, ['Buyer', 'Plan', 'Macs', 'Status', 'Issued', 'Ends'].map((t) => h('th', {}, t)))),
    h('tbody', {}, licenses.map((l) => h('tr', { onclick: () => go('detail', l.id) },
      h('td', {}, h('div', { class: 't' }, l.name || l.email), h('div', { class: 'dim' }, l.name ? l.email : l.id)),
      h('td', {}, h('span', { class: `plan ${l.plan}` }, PLAN[l.plan] ?? l.plan)),
      h('td', { class: 'mono' }, `${l.used} of ${l.seats}`),
      h('td', {}, pill(l.state)),
      h('td', { class: 'muted' }, date(l.issued)),
      h('td', { class: 'muted' }, l.expires ? date(l.expires) : 'Never')))))
    : h('div', { class: 'empty' }, state.q || state.filter ? 'Nothing matches.' : 'No licenses yet. Create the first one.');
  const page = h('div', {},
    h('div', { class: 'head' }, h('div', {}, h('h1', {}, 'Licenses'), h('p', { class: 'sub' }, 'Every key you have issued, by hand or from a purchase.')),
      h('div', { class: 'actions' }, h('a', { class: 'btn', href: '/api/export.csv' }, 'Export CSV'), h('button', { class: 'btn primary', onclick: () => go('new') }, 'New license'))),
    h('div', { class: 'grid stats' }, stat(stats.active, 'Active'), stat(stats.lifetime, 'Lifetime, active'), stat(stats.activations, 'Macs activated'), stat(stats.revoked + stats.expired, 'Off or expired')),
    h('div', { class: 'toolbar' }, search, filters),
    h('div', { class: 'card' }, table));
  return { page, focus: search };
}

async function viewNew() {
  let plan = 'lifetime';
  const email = h('input', { class: 'input', type: 'email', placeholder: 'buyer@example.com', required: true });
  const name = h('input', { class: 'input', placeholder: 'Optional' });
  const seats = h('input', { class: 'input', type: 'number', min: 1, max: 100, value: 2 });
  const days = h('input', { class: 'input', type: 'number', min: 1, max: 3650, placeholder: 'Default' });
  const note = h('input', { class: 'input', placeholder: 'Only you see this' });
  const queue = h('input', { type: 'checkbox', checked: true });
  const hint = h('div', { class: 'dim' });
  const error = h('div', { class: 'error' });
  const seg = h('div', { class: 'seg' });
  const paint = () => {
    seg.replaceChildren(...['lifetime', 'annual', 'trial', 'pro'].map((p) => h('button', { type: 'button', class: plan === p ? 'on' : '', onclick: () => { plan = p; paint(); } }, PLAN[p])));
    hint.textContent = { lifetime: 'Never ends. Leave days empty.', annual: 'Ends after 365 days unless you set days.', trial: 'Ends after 14 days unless you set days.', pro: 'The extra tier. Never ends unless you set days.' }[plan];
  };
  paint();
  const submit = async (e) => {
    e.preventDefault(); error.textContent = '';
    try {
      const { license } = await api('/api/licenses', { method: 'POST', body: { plan, email: email.value, name: name.value, seats: seats.value, days: days.value || null, note: note.value, queueEmail: queue.checked } });
      toast('License created'); go('detail', license.id);
    } catch (err) { error.textContent = err.message; }
  };
  const page = h('div', {},
    h('div', { class: 'head' }, h('div', {}, h('h1', {}, 'New license'), h('p', { class: 'sub' }, 'Signed on this Mac. Works offline in ZEUS.'))),
    h('form', { class: 'card', onsubmit: submit }, h('div', { class: 'form' },
      h('div', { class: 'field full' }, h('label', {}, 'Type'), seg, hint),
      h('div', { class: 'field' }, h('label', {}, 'Buyer email'), email),
      h('div', { class: 'field' }, h('label', {}, 'Buyer name'), name),
      h('div', { class: 'field' }, h('label', {}, 'Macs (seats)'), seats),
      h('div', { class: 'field' }, h('label', {}, 'Days'), days),
      h('div', { class: 'field full' }, h('label', {}, 'Note'), note),
      h('label', { class: 'full muted' }, queue, ' Add the delivery email to Deliveries'),
      h('div', { class: 'full actions' }, h('button', { class: 'btn primary', type: 'submit' }, 'Create license'), error))));
  return { page, focus: email };
}

async function viewDetail(id) {
  const { license: l, email, audit } = await api(`/api/licenses/${encodeURIComponent(id)}`);
  const act = async (action, body, done) => { try { await api(`/api/licenses/${l.id}/${action}`, { method: 'POST', body: body ?? {} }).then(done); } catch (err) { toast(err.message); } };
  const revoke = () => { if (confirm(`Turn off ${l.id}? ZEUS stops accepting it at the next check.`)) act('revoke', { reason: prompt('Reason (shown in Activity)', 'refund') || 'revoked' }, () => { toast('Key turned off'); render(); }); };
  const reissue = () => { if (confirm('Make a new key for this buyer and turn this one off?')) act('reissue', {}, (r) => { toast('New key issued'); go('detail', r.license.id); }); };
  const restore = () => act('restore', {}, () => { toast('Key turned back on'); render(); });
  const page = h('div', {},
    h('button', { class: 'btn quiet sm back', onclick: () => go('licenses') }, '‹ Licenses'),
    h('div', { class: 'head' }, h('div', {}, h('h1', {}, l.name || l.email), h('p', { class: 'sub' }, `${PLAN[l.plan]} · ${l.id} · ${ends(l)}`)),
      h('div', { class: 'actions' }, pill(l.state))),
    h('div', { class: 'grid two' },
      h('div', { class: 'stack' },
        h('div', { class: 'card stack' }, h('p', { class: 'eyebrow' }, 'License key'), h('div', { class: 'keybox' }, l.key),
          h('div', { class: 'actions' }, h('button', { class: 'btn primary sm', onclick: () => copy(l.key, 'Key') }, 'Copy key'),
            h('button', { class: 'btn sm', onclick: () => copy(`${email.subject}\n\n${email.body}`, 'Email') }, 'Copy email'),
            h('a', { class: 'btn sm', href: `mailto:${encodeURIComponent(email.to)}?subject=${encodeURIComponent(email.subject)}&body=${encodeURIComponent(email.body)}` }, 'Open in Mail'))),
        h('div', { class: 'card stack' }, h('p', { class: 'eyebrow' }, 'Delivery email'), h('div', { class: 'muted' }, `To ${email.to} · ${email.subject}`), h('pre', { class: 'mail' }, email.body))),
      h('div', { class: 'stack' },
        h('div', { class: 'card' }, h('p', { class: 'eyebrow' }, 'Details'),
          ...[['Email', l.email], ['Name', l.name || 'Not given'], ['Macs', `${l.used} of ${l.seats} in use`], ['Issued', date(l.issued)], ['Ends', l.expires ? date(l.expires) : 'Never'],
            ['From', l.source === 'portal' ? 'Made by hand' : `${l.source} order ${l.order_ref ?? ''}`], ['Fingerprint', l.fingerprint],
            ...(l.revoke_reason ? [['Turned off', `${l.revoke_reason}${l.revoked_at ? `, ${date(l.revoked_at)}` : ''}`]] : []),
            ...(l.replaced_by ? [['Replaced by', l.replaced_by]] : []), ...(l.replaces ? [['Replaces', l.replaces]] : []), ...(l.note ? [['Note', l.note]] : [])]
            .map(([k, v]) => h('div', { class: 'row' }, h('span', { class: 'n' }, k), h('span', { class: k === 'Fingerprint' ? 'mono' : '' }, v)))),
        h('div', { class: 'card' }, h('p', { class: 'eyebrow' }, 'Macs'),
          l.activations.length ? l.activations.map((a) => h('div', { class: 'row' }, h('div', {}, h('div', { class: 't' }, a.name || 'Mac'), h('div', { class: 'n mono' }, a.device),
            h('div', { class: 'n' }, `Since ${date(a.created)}, last seen ${date(a.last_seen)}`)),
          h('button', { class: 'btn sm danger', onclick: async () => { if (confirm('Free this seat?')) { await api(`/api/licenses/${l.id}/activations/${encodeURIComponent(a.device)}`, { method: 'DELETE' }); toast('Seat freed'); render(); } } }, 'Free seat')))
            : h('div', { class: 'muted' }, 'Not activated with the server yet. Offline activations do not show here.')),
        h('div', { class: 'card stack' }, h('p', { class: 'eyebrow' }, 'Manage'),
          h('div', { class: 'actions' },
            l.status === 'revoked' ? (l.replaced_by ? null : h('button', { class: 'btn sm', onclick: restore }, 'Turn back on')) : h('button', { class: 'btn sm danger', onclick: revoke }, 'Turn off'),
            l.replaced_by ? null : h('button', { class: 'btn sm', onclick: reissue }, 'Re-issue'))),
        h('div', { class: 'card' }, h('p', { class: 'eyebrow' }, 'History'),
          audit.map((e) => h('div', { class: 'row' }, h('span', {}, e.action.replace(/_/g, ' ')), h('span', { class: 'n' }, `${e.actor} · ${dateTime(e.ts)}`)))))));
  return { page };
}

async function viewOutbox() {
  const { outbox } = await api('/api/outbox');
  const page = h('div', {},
    h('div', { class: 'head' }, h('div', {}, h('h1', {}, 'Deliveries'), h('p', { class: 'sub' }, 'License emails ready to send. Nothing is sent without you.'))),
    outbox.length ? h('div', { class: 'stack' }, outbox.map((m) => h('div', { class: 'card stack' },
      h('div', { class: 'row' }, h('div', {}, h('div', { class: 't' }, m.to_email), h('div', { class: 'n' }, `${m.subject} · ${dateTime(m.created)} · ${m.license_id}`)),
        h('span', { class: `pill ${m.status === 'sent' ? 'active' : 'expired'}` }, m.status === 'sent' ? 'Sent' : 'Ready')),
      h('div', { class: 'actions' },
        h('button', { class: 'btn sm primary', onclick: () => copy(`${m.subject}\n\n${m.body}`, 'Email') }, 'Copy email'),
        h('a', { class: 'btn sm', href: `mailto:${encodeURIComponent(m.to_email)}?subject=${encodeURIComponent(m.subject)}&body=${encodeURIComponent(m.body)}` }, 'Open in Mail'),
        m.status === 'sent' ? null : h('button', { class: 'btn sm', onclick: async () => { await api(`/api/outbox/${m.id}/sent`, { method: 'POST' }); toast('Marked as sent'); render(); } }, 'Mark as sent'),
        h('button', { class: 'btn sm quiet', onclick: () => go('detail', m.license_id) }, 'Open license')))))
      : h('div', { class: 'card empty' }, 'No deliveries yet. Purchases and new licenses land here.'));
  return { page };
}

async function viewAudit() {
  const { audit } = await api('/api/audit');
  const page = h('div', {},
    h('div', { class: 'head' }, h('div', {}, h('h1', {}, 'Activity'), h('p', { class: 'sub' }, 'Every change, sign-in and activation, newest first.'))),
    h('div', { class: 'card' }, audit.length ? h('table', {}, h('thead', {}, h('tr', {}, ['When', 'Who', 'What', 'License', 'Details'].map((t) => h('th', {}, t)))),
      h('tbody', {}, audit.map((e) => h('tr', { onclick: () => e.license_id && go('detail', e.license_id) },
        h('td', { class: 'muted' }, dateTime(e.ts)), h('td', {}, e.actor), h('td', {}, e.action.replace(/_/g, ' ')),
        h('td', { class: 'mono' }, e.license_id ?? ''), h('td', { class: 'dim mono' }, e.detail ?? '')))))
      : h('div', { class: 'empty' }, 'Nothing yet.')));
  return { page };
}

async function viewSettings() {
  const s = await api('/api/settings');
  const providerRow = (p) => {
    const secret = h('input', { class: 'input', type: 'password', placeholder: p.secretSet ? 'Saved. Paste to replace' : 'Webhook signing secret', style: 'max-width:260px' });
    return h('div', { class: 'row' },
      h('div', {}, h('div', { class: 't' }, p.title), h('div', { class: 'n mono' }, p.url),
        h('div', { class: 'n' }, `${p.enabled ? 'On' : 'Off'} · secret ${p.secretSet ? 'saved in keychain' : 'not set'}`)),
      s.secretsWritable ? h('div', { class: 'actions' }, secret, h('button', { class: 'btn sm', onclick: async () => {
        try { await api('/api/settings/webhook-secret', { method: 'POST', body: { provider: p.name, secret: secret.value } }); toast('Secret saved'); render(); } catch (err) { toast(err.message); }
      } }, 'Save')) : null);
  };
  const page = h('div', {},
    h('div', { class: 'head' }, h('div', {}, h('h1', {}, 'Settings'), h('p', { class: 'sub' }, `Secrets live in ${s.secretStore}.`))),
    h('div', { class: 'stack' },
      h('div', { class: 'card stack' }, h('p', { class: 'eyebrow' }, 'Signing key'),
        h('div', { class: 'muted' }, 'ZEUS checks keys with this public key. The private half never leaves the keychain.'),
        h('div', { class: 'keybox' }, s.publicKey), h('div', { class: 'actions' }, h('button', { class: 'btn sm', onclick: () => copy(s.publicKey, 'Public key') }, 'Copy public key'))),
      h('div', { class: 'card' }, h('p', { class: 'eyebrow' }, 'Purchases'),
        h('div', { class: 'muted', style: 'margin-bottom:6px' }, 'When a store calls its webhook, the portal checks the signature, issues the key once per order and adds the email to Deliveries. A refund turns the key off. Stores are off until you pick one and turn it on in config.json.'),
        s.providers.map(providerRow)),
      h('div', { class: 'card' }, h('p', { class: 'eyebrow' }, 'Default for purchases'),
        h('div', { class: 'row' }, h('span', { class: 'n' }, 'Issued when a product is not mapped'), h('span', {}, `${PLAN[s.defaultProduct.plan]}, ${s.defaultProduct.seats} Macs`))),
      h('div', { class: 'card' }, h('p', { class: 'eyebrow' }, 'Data'),
        h('div', { class: 'row' }, h('div', {}, h('div', { class: 't' }, 'Export every license'), h('div', { class: 'n' }, 'CSV with keys. Keep it somewhere safe.')),
          h('a', { class: 'btn sm', href: '/api/export.csv' }, 'Export CSV')))));
  return { page };
}

async function render(keepFocus = false) {
  let session;
  try { session = await (await fetch('/api/session', { credentials: 'same-origin' })).json(); } catch { root.replaceChildren(h('div', { class: 'empty' }, 'The portal is not answering.')); return; }
  if (!session.signedIn) return renderLogin(session.setup);
  const views = { licenses: viewLicenses, new: viewNew, detail: () => viewDetail(state.detail), outbox: viewOutbox, audit: viewAudit, settings: viewSettings };
  try {
    const { page, focus } = await (views[state.view] ?? viewLicenses)();
    if (!state.stats) state.stats = (await api('/api/stats')).stats;
    root.replaceChildren(shell(page));
    if (focus && (keepFocus || state.view === 'new')) { focus.focus(); if (focus.type === 'search') focus.setSelectionRange(focus.value.length, focus.value.length); }
  } catch (err) { if (err.message !== 'Signed out') toast(err.message); }
}

render();
