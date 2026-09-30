const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const source = fs.readFileSync(path.join(__dirname, '../lib/campaign-audience.ts'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
const context = { exports: {} };
vm.runInNewContext(compiled, context);
const { audiencesForRecipients, resetRecipientAudience } = context.exports;
const options = {
  client: [{ value: 'all' }, { value: 'no_send' }],
  driver: [{ value: 'all' }, { value: 'driver_regular' }],
  relay_agent: [{ value: 'all' }, { value: 'relay_regular' }],
};

test('each recipient role receives only its own audience options', () => {
  for (const role of Object.keys(options)) {
    assert.equal(audiencesForRecipients([role], options), options[role]);
  }
});

test('all recipients and mixed recipients have no audience submenu', () => {
  for (const roles of [['all'], ['client', 'driver'], []]) {
    assert.equal(audiencesForRecipients(roles, options).length, 0);
  }
  assert.equal(audiencesForRecipients(['driver']).length, 0);
});

test('changing recipients clears the audience but preserves frequency and configured thresholds', () => {
  const defaults = { audience: 'all', min_deliveries: 5, min_completed_missions: 5, min_processed_parcels: 5, inactive_days: 30, max_exposures: 3, frequency_days: 7, cooldown_hours: 24 };
  const current = { ...defaults, audience: 'driver_regular', min_completed_missions: 12, max_exposures: 2 };
  const reset = resetRecipientAudience(current, defaults);
  assert.equal(reset.audience, 'all');
  assert.equal(reset.min_completed_missions, 12);
  assert.equal(reset.max_exposures, 2);
  assert.equal(current.audience, 'driver_regular');
  assert.equal(resetRecipientAudience(undefined, defaults).audience, 'all');
  assert.equal(resetRecipientAudience(undefined, undefined), undefined);
});
