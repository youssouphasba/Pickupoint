const test = require("node:test");
const assert = require("node:assert/strict");
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const { createLoader } = require("./load-typescript.cjs");

const { referralConfigErrors } = createLoader()("lib/referral-settings.ts");
const client = {
  enabled: true, sponsor_bonus_xof: 1000, referred_bonus_xof: 0,
  apply_metric: "sent_parcels", apply_max_count: 0,
  reward_metric: "delivered_sender_parcels", reward_count: 1,
  max_referrals_per_sponsor: 0,
  metric_options: [{ value: "sent_parcels", label: "Colis créés" }, { value: "delivered_sender_parcels", label: "Colis livrés" }],
  sponsor_roles: [{ value: "client", label: "Client" }, { value: "driver", label: "Livreur" }],
};
const driver = {
  ...client, apply_metric: "completed_driver_deliveries", reward_metric: "completed_driver_deliveries",
  metric_options: [{ value: "completed_driver_deliveries", label: "Missions terminées" }],
  sponsor_roles: [{ value: "driver", label: "Livreur" }],
};

function renderReferralForm({ driverConfig = driver, pending = false, stats = undefined } = {}) {
  let stateIndex = 0;
  const seededState = [true, client, driverConfig];
  const load = createLoader({
    react: {
      ...React,
      useState(initial) {
        const index = stateIndex++;
        return index < seededState.length ? [seededState[index], () => {}] : React.useState(initial);
      },
    },
    "@/lib/api": {},
    "@/components/referral-ledger": { ReferralLedger: () => null },
    "@/components/page-section-nav": { PageSectionNav: () => null },
    "@/components/ui/toaster": { useToast: () => ({ toast() {} }) },
    "@tanstack/react-query": {
      useQuery: ({ queryKey }) => ({
        data: queryKey[0] === "settings" ? { referral_roles: { client, driver: driverConfig } }
          : queryKey[0] === "referral-stats" ? stats : undefined,
        isLoading: false, isError: false, refetch() {},
      }),
      useMutation: () => ({ isPending: pending, isError: false, mutate() {} }),
      useQueryClient: () => ({ invalidateQueries() {}, setQueryData() {} }),
    },
  });
  return renderToStaticMarkup(React.createElement(load("app/dashboard/promotions/page.tsx").default));
}

function saveButton(html) {
  const button = Array.from(html.matchAll(/<button\b[^>]*>(?:(?!<\/button>)[\s\S])*<\/button>/g))
    .map((match) => match[0]).find((button) => button.includes("Sauvegarder"));
  assert.ok(button);
  return button;
}

test("les règles valides autorisent une prime nulle et les limites nulles sans les modifier", () => {
  assert.equal(referralConfigErrors(client, client.metric_options).length, 0);
  assert.equal(referralConfigErrors(driver, driver.metric_options).length, 0);
  assert.equal(client.referred_bonus_xof, 0);
});

test("aucune liste globale ne remplace des activités absentes ou incompatibles", () => {
  assert.match(referralConfigErrors(driver, undefined)[0], /ne sont pas chargées/);
  const errors = referralConfigErrors({ ...driver, apply_metric: "sent_parcels", reward_metric: "delivered_sender_parcels" }, driver.metric_options);
  assert.equal(errors.length, 2);
  assert.match(errors[0], /ajouter le code/);
  assert.match(errors[1], /débloquer les primes/);
});

test("les valeurs négatives, fractionnaires et les objectifs nuls sont bloqués", () => {
  for (const config of [{ ...client, sponsor_bonus_xof: -1 }, { ...client, reward_count: 0 }, { ...client, apply_max_count: 1.5 }, { ...client, referred_bonus_xof: NaN }]) {
    assert.ok(referralConfigErrors(config, client.metric_options).length > 0);
  }
});

test("le formulaire utilise les options des paramètres sans dépendre des statistiques", () => {
  const html = renderReferralForm();
  assert.ok(html.includes("Ce filleul peut être parrainé par un client ou livreur."));
  assert.ok(html.includes("Ce filleul peut être parrainé par un livreur."));
  assert.ok(!html.includes("parrainer ou d’être parrainés"));
  const driverCard = html.split('id="referral-role-driver"')[1].split("</fieldset>")[0];
  assert.ok(driverCard.includes("Missions terminées"));
  assert.ok(!driverCard.includes("<select"));
  assert.ok(!saveButton(html).includes('disabled=""'));
});

test("une ancienne condition incompatible reste visible et peut être remplacée explicitement", () => {
  const html = renderReferralForm({ driverConfig: { ...driver, apply_metric: "sent_parcels" } });
  const driverCard = html.split('id="referral-role-driver"')[1].split("</fieldset>")[0];
  assert.ok(driverCard.includes("Choisir une activité autorisée"));
  assert.ok(driverCard.includes('value="completed_driver_deliveries"'));
  assert.ok(driverCard.includes("Choisissez une activité autorisée pour ajouter le code."));
  assert.ok(saveButton(html).includes('disabled=""'));
});

test("la sauvegarde est bloquée pendant le chargement des activités sans inventer de choix", () => {
  const html = renderReferralForm({ driverConfig: { ...driver, metric_options: undefined } });
  const driverCard = html.split('id="referral-role-driver"')[1].split("</fieldset>")[0];
  assert.ok(driverCard.includes("Les activités autorisées ne sont pas chargées"));
  assert.ok(!driverCard.includes('<option value="delivered_sender_parcels"'));
  assert.ok(saveButton(html).includes('disabled=""'));
});

test("les adaptations anciennes sont signalées sans masquer les seuils et montants", () => {
  const html = renderReferralForm({ driverConfig: { ...driver, configuration_warnings: ["Ancienne activité adaptée ; montants et seuils conservés."] } });
  assert.ok(html.includes("Ancienne activité adaptée ; montants et seuils conservés."));
  assert.ok(html.includes('role="status"'));
  assert.ok(html.includes('value="1000"'));
});

test("les champs de parrainage sont verrouillés pendant la sauvegarde", () => {
  const html = renderReferralForm({ pending: true });
  assert.match(html, /<fieldset[^>]*disabled=""[^>]*class="grid gap-4 sm:grid-cols-2"/);
});
