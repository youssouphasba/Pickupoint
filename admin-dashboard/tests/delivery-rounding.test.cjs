const test = require("node:test");
const assert = require("node:assert/strict");
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const { createLoader } = require("./load-typescript.cjs");

const load = createLoader();
const { roundingBenefits } = load("lib/delivery-rounding.ts");
const { DenkmaRoundingOffer } = load("components/denkma-rounding-offer.tsx");
const snapshot = (amount) => ({ rounding: { version: "customer_down_driver_up_v1", customer_discount_xof: amount } });

test("les anciens colis ne reçoivent pas une réduction inventée", () => {
  assert.equal(Object.keys(roundingBenefits({})).length, 0);
  assert.equal(Object.keys(roundingBenefits({ financial_rounding: { rounding: { customer_discount_xof: 37 } } })).length, 0);
});

test("le contrat convenu a priorité sur les nouveaux devis", () => {
  assert.equal(roundingBenefits({ financial_rounding: snapshot(37), financial_contract: { breakdown: snapshot(12) } }).customer_discount_xof, 12);
  assert.equal(roundingBenefits({ quote_breakdown: { financial_rounding: snapshot(37) } }).customer_discount_xof, 37);
});

test("le montant offert est affiché en vert et n'est pas une seconde prime", () => {
  const html = renderToStaticMarkup(React.createElement(DenkmaRoundingOffer, { amount: 14.1, includedInGain: true }));
  assert.match(html, /text-green-800/);
  assert.match(html, /14,1 FCFA offerts par Denkma/);
  assert.match(html, /inclus dans le gain/);
  for (const amount of [0, -10, NaN, Infinity, undefined]) {
    assert.equal(renderToStaticMarkup(React.createElement(DenkmaRoundingOffer, { amount })), "");
  }
});
