const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function run(file, url) {
  const parsed = new URL(url);
  const elements = new Map();
  const location = {search: parsed.search, origin: parsed.origin, pathname: parsed.pathname,
    replace(value) { this.href = value; }};
  const document = {getElementById(id) {
    if (!elements.has(id)) elements.set(id, {});
    return elements.get(id);
  }};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../assets', file), 'utf8'), {
    URL, URLSearchParams, document, window: {location, setTimeout(callback) { callback(); }},
  });
  return {elements, location};
}

test('wallet return uses supported native link and does not claim payment is credited', () => {
  const result = run('open-app.js', 'https://denkma.com/app/?wallet_return=success&topup_id=top_synthetic');
  const link = new URL(result.elements.get('openApp').href);
  assert.equal(link.protocol, 'denkma:');
  assert.equal(link.pathname, '/parcel');
  assert.equal(link.searchParams.get('topup_id'), 'top_synthetic');
  assert.equal(result.elements.get('title').textContent, 'Retour à votre solde');
  assert.match(result.elements.get('context').textContent, /vérifié/);
  assert.doesNotMatch(result.elements.get('context').textContent, /crédité|réussi/);
});

test('cancel return and invalid IDs are handled safely', () => {
  const result = run('open-app.js', 'https://denkma.com/app/?wallet_return=cancel&topup_id=../../bad');
  assert.equal(new URL(result.elements.get('openApp').href).searchParams.get('topup_id'), null);
  assert.match(result.elements.get('context').textContent, /quitté/);
});

test('referral and tracking links are preserved', () => {
  const referral = run('open-app.js', 'https://denkma.com/app/?ref=abc');
  assert.equal(new URL(referral.elements.get('openApp').href).pathname, '/referral/ABC');
  const parcel = run('open-app.js', 'https://denkma.com/app/?tracking=PKP-SYNTHETIC&phone=%2B221700000000');
  assert.equal(new URL(parcel.elements.get('openApp').href).searchParams.get('tracking'), 'PKP-SYNTHETIC');
});

test('old Stripe return URLs preserve recharge reference and route to the app page', () => {
  for (const kind of ['success', 'cancel']) {
    const result = run('wallet-return.js', `https://denkma.com/wallet/stripe/${kind}?topup_id=top_synthetic`);
    const link = new URL(result.location.href);
    assert.equal(link.pathname, '/app/');
    assert.equal(link.searchParams.get('wallet_return'), kind);
    assert.equal(link.searchParams.get('topup_id'), 'top_synthetic');
  }
});
