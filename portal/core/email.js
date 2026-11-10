// The delivery email a buyer gets. Plain text, so it pastes cleanly into any mail app.
const PLAN_NAMES = { lifetime: 'Lifetime license', annual: 'Annual license', trial: 'Trial license', pro: 'ZEUS Pro' };

export function planName(plan) { return PLAN_NAMES[plan] ?? 'License'; }

export function formatDate(seconds) {
  return new Date(seconds * 1000).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' });
}

export function deliveryEmail(license, config = {}) {
  const product = config.productName || 'ZEUS';
  const greeting = license.name ? `Hi ${license.name.split(' ')[0]},` : 'Hi,';
  const seats = license.seats === 1 ? '1 Mac' : `${license.seats} Macs`;
  const term = license.expires ? `Valid until ${formatDate(license.expires)}.` : 'Yours to keep, with no renewal.';
  const lines = [
    greeting, '',
    `Thank you for getting ${product}. Here is your ${planName(license.plan).toLowerCase()}.`, '',
    'Your license key:', '', license.key, '',
    'To activate:',
    `1. Open ${product} and go to Settings, then License.`,
    '2. Paste the key and press Activate.', '',
    `Covers ${seats}. ${term}`,
    'Moving to a new Mac? Press Deactivate on the old one first, then activate on the new one.',
  ];
  if (config.downloadURL) lines.push('', `Download ${product}: ${config.downloadURL}`);
  lines.push('', `License ID: ${license.id}`);
  if (config.supportEmail) lines.push(`Questions? Just reply, or write to ${config.supportEmail}.`);
  lines.push('', `The ${product} team`);
  return { to: license.email, subject: `Your ${product} license key`, body: lines.join('\n') };
}
