const test = require("node:test");
const assert = require("node:assert/strict");
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const { createLoader } = require("./load-typescript.cjs");

const category = (href, items = []) => ({
  href, items, count: items.length, urgent_count: items.filter((item) => item.urgency === "critical").length,
  warning_count: 0,
});
const actions = {
  total: 2, total_urgent: 2, total_warning: 0,
  categories: {
    payouts: category("/dashboard/payouts"),
    applications: category("/dashboard/applications", [{ id: "app_test", user_id: "usr_test", full_name: "Candidat test", application_type: "driver", urgency: "critical", age_hours: 1 }]),
    incidents: category("/dashboard/parcels"),
    anomalies: category("/dashboard/anomalies"),
    stale_parcels: category("/dashboard/stale"),
    payment_blocked: category("/dashboard/parcels"),
    support: category("/dashboard/support"),
    disputes: category("/dashboard/parcels"),
    security: category("/dashboard/security", [{ id: "event_test", driver_name: "Livreur test", message: "Position à vérifier", urgency: "critical", age_hours: 1 }]),
  },
};
const finance = {
  commissions: { platform_received_xof: 1000, details: {} },
  topups: {}, payouts: {}, relays: { settlements: {} }, payments: { details: {} }, wallets: {},
  alerts: [], daily: [{ date: "2026-09-30", topups_xof: 1000, payouts_xof: 0 }],
};
const settlementTotals = {
  to_relay_xof: 150, to_denkma_xof: 450, to_driver_xof: 1400,
  to_relay_declared_xof: 0, to_denkma_declared_xof: 450, to_driver_declared_xof: 0,
  to_relay_validated_xof: 0, to_denkma_validated_xof: 0, to_driver_validated_xof: 0,
  upcoming_to_relay_xof: 50, pending_count: 2, declared_count: 1, rejected_count: 0,
  outstanding_count: 3, unavailable_count: 0,
};
const settlementAction = {
  action: "denkma_payment", relay_id: "relay_test", relay_name: "Boutique test",
  direction: "to_denkma", label: "Relais → Denkma", amount_xof: 450,
  status: "declared", stage: "due", can_validate: true, can_reject: true,
  parcel_id: "parcel_test", tracking_code: "PKP-TEST", declared_at: "2026-10-01T08:00:00Z",
};

function appRenderer(pathname, errorKeys = [], overrides = {}, pending = false) {
  const queries = {
    me: { email: "admin@example.test", full_name: "Admin test", role: "admin" },
    settings: {}, "action-center": actions, "admin-events": { events: [], unread_count: 0 },
    dashboard: { total_parcels: 4, parcels_today: 1, delivered: 2, failed: 0, active_parcels: 2, pending_payouts: 0, success_rate: 100, active_relays: 1, active_drivers: 2, live_fleet: 1, signal_lost: 0, critical_delay: 0, stale_parcels: 0, payment_blocked_parcels: 0, revenue_xof: 1000 },
    "finance-overview": finance, "finance-recon": {},
    "finance-relay-settlements": { totals: settlementTotals, relays: [{ ...settlementTotals, relay_id: "relay_test", name: "Boutique test", is_active: false }], total: 1, has_more: false },
    "finance-relay-actions": { actions: [settlementAction], total: 1, has_more: false },
    payouts: { payouts: [{ payout_id: "withdrawal_test", user_id: "usr_test", user_name: "Bénéficiaire test", method: "bank", amount: 1000, status: "pending", created_at: "2026-09-30T08:00:00Z" }] },
    "drivers-list": { drivers: [{ user_id: "usr_driver", phone: "+221700000000", name: "Livreur test", is_active: true, is_available: false }] },
    relays: { relay_points: [], total: 0 },
    ...overrides,
  };
  const load = createLoader({
    "next/navigation": { usePathname: () => pathname, useRouter: () => ({ replace() {} }), useSearchParams: () => new URLSearchParams() },
    "next/link": { __esModule: true, default: ({ children, ...props }) => React.createElement("a", props, children) },
    "@/lib/api": {},
    "@/components/ui/toaster": { useToast: () => ({ toast() {} }) },
    "@/lib/use-admin-alert-notifications": { useAdminAlertNotifications() {} },
    "@tanstack/react-query": {
      useQuery: ({ queryKey }) => ({ data: errorKeys.includes(queryKey[0]) ? undefined : queries[queryKey[0]], isLoading: false, isError: errorKeys.includes(queryKey[0]), isFetching: false, dataUpdatedAt: 0, refetch() {}, error: null }),
      useMutation: () => ({ isPending: pending, isError: false, mutate() {} }),
      useQueryClient: () => ({ invalidateQueries() {} }),
    },
  });
  return (file, exportName = "default", props = {}) => renderToStaticMarkup(React.createElement(load(file)[exportName], props));
}

test("destination : paiements destinataire et part du livreur sont contrôlés séparément", () => {
  const html = appRenderer("/dashboard/parcels/parcel_test")("components/destination-management.tsx", "DestinationManagement", { parcel: {
    parcel_id: "parcel_test", status: "available_at_relay", delivery_mode: "home_to_home", updated_at: "2026-10-03T10:00:00Z", who_pays: "recipient",
    financial_contract: { price_xof: 2000, delivery_mode: "home_to_home", breakdown: { driver_revenue_xof: 1700 } },
    recipient_collection_plan: { status: "collection_required", collector: "relay", amount_due_xof: 1500, amount_received_xof: 500, receipts: [{ collector: "relay", collector_id: "relay_test", amount_xof: 500 }] },
  } });
  assert.ok(html.includes("Déjà reçu"));
  assert.ok(html.includes("Reste dû"));
  assert.ok(html.includes("Montant supplémentaire réellement reçu, pas le prix complet"));
  assert.ok(html.includes("encaissement par le relais ne paie pas automatiquement le livreur"));
  assert.ok(html.includes("reversements à Denkma, séparés de sa commission"));
  assert.ok(html.includes('max="1500"'));
});

test("destination : un paiement confirmé et un livreur payé ne sont pas réclamés à nouveau", () => {
  const html = appRenderer("/dashboard/parcels/parcel_test")("components/destination-management.tsx", "DestinationManagement", { parcel: {
    parcel_id: "parcel_test", status: "available_at_relay", delivery_mode: "home_to_home", updated_at: "2026-10-03T10:00:00Z", payment_status: "paid", paid_price: 2000,
    financial_contract: { price_xof: 2000, delivery_mode: "home_to_home", breakdown: { driver_revenue_xof: 1700 } },
    recipient_collection_plan: { status: "admin_review", amount_due_xof: 2000, amount_received_xof: 0 }, relay_settlement: { driver_payment_status: "validated" },
  } });
  assert.ok(html.includes("Aucun nouvel encaissement à demander"));
  assert.ok(html.includes("Déjà réglée : ne pas payer à nouveau"));
  assert.ok(html.includes('max="0"'));
});

test("le menu conserve tous les écrans, le repère actif et la recherche accessible", () => {
  const html = appRenderer("/dashboard/finance")("components/sidebar.tsx", "Sidebar", { admin: { email: "admin@example.test" } });
  assert.match(html, /Navigation principale/);
  assert.match(html, /Rechercher un écran/);
  assert.match(html, /href="\/dashboard\/finance"[^>]*aria-current="page"/);
  for (const label of ["Exploitation", "Comptes et partenaires", "Finances", "Communication et activité", "Contrôle et conformité", "Réglages"]) assert.ok(html.includes(label), label);
  assert.ok(html.includes('href="/dashboard/settings/alerts"'));
});

test("les fiches ont un fil d’Ariane et un vrai retour à la liste", () => {
  const render = appRenderer("/dashboard/parcels/prc_test");
  const crumbs = render("components/admin-page-context.tsx", "AdminBreadcrumbs");
  assert.ok(crumbs.includes("Détail du colis"));
  assert.ok(crumbs.includes('href="/dashboard/parcels"'));
  const context = render("components/admin-page-context.tsx", "AdminPageContext");
  assert.ok(context.includes("Retour à la liste"));
  assert.ok(!context.includes("À quoi sert cet écran ?"));
});

test("l’aide explique les messages aux utilisateurs sans les confondre avec les alertes admin", () => {
  const html = appRenderer("/dashboard/notifications")("components/admin-page-context.tsx", "AdminPageContext");
  assert.ok(html.includes("pas les administrateurs"));
  assert.ok(html.includes("/dashboard/settings/alerts"));
  assert.ok(html.includes("Offres") || html.includes("Communications avec visuel"));
});

test("les priorités incluent la sécurité et ouvrent le dossier de candidature à vérifier", () => {
  const html = appRenderer("/dashboard")("components/action-center-section.tsx", "ActionCenterSection");
  assert.ok(html.includes("Sécurité des livreurs"));
  assert.ok(html.includes("Position à vérifier"));
  assert.ok(html.includes("Vérifier le dossier"));
  assert.ok(html.includes('href="/dashboard/users/usr_test"'));
  assert.ok(!html.includes("Agent relais"));
  assert.ok(!/<button\b[^>]*>(?:(?!<\/button>)[\s\S])*<a\b/.test(html), "pas de lien imbriqué dans un bouton");
});

test("le tableau de bord propose des accès utiles et une actualisation", () => {
  const html = appRenderer("/dashboard")("app/dashboard/page.tsx");
  assert.ok(html.includes("Accès fréquents"));
  assert.ok(html.includes("Actualiser"));
  assert.ok(html.includes("Candidatures partenaires"));
  assert.ok(!html.includes("KPI"));
});

test("configuration : taux théoriques, arrondis et protection des contrats sont explicites", () => {
  const html = appRenderer("/dashboard/configuration", [], { settings: {
    pricing: { rounding_step_xof: 50 },
    commission_rules: { home_to_home: { driver_rate: 0.75, platform_rate: 0.25 } },
  } })("app/dashboard/configuration/page.tsx");
  assert.match(html, /Ces taux servent de base au calcul/);
  assert.match(html, /multiples de 50 FCFA/);
  assert.match(html, /Les montants convenus ne sont pas recalculés/);
  assert.match(html, /Si la marge est insuffisante/);
});

test("configuration : toutes les sections, sauvegardes explicites et libellés d’inputs", () => {
  const html = appRenderer("/dashboard/configuration")("app/dashboard/configuration/page.tsx");
  for (const id of ["tarifs", "commissions", "livraison", "diffusion", "recompenses", "guide", "mises-a-jour"]) {
    assert.ok(html.includes('id="' + id + '"'), id);
    assert.ok(html.includes('href="#' + id + '"'), id);
  }
  assert.ok(html.includes("Sauvegarder tarifs et livraison"));
  assert.ok(html.includes("Sauvegarder la diffusion"));
  assert.ok(html.includes("Sauvegarder les récompenses"));
  assert.ok(html.includes("Sauvegarder la vidéo"));
  assert.ok(html.includes("Sauvegarder les mises à jour"));
  assert.ok(html.indexOf('id="livraison"') < html.indexOf('id="mises-a-jour"'));
  assert.match(html, /<label for="[^"]+"[^>]*>Relais vers relais<\/label>/);
  assert.match(html, /aria-describedby="[^"]+-help"/);
});

test("finance : les règlements relais sont distincts des recharges et tous les raccourcis existent", () => {
  const html = appRenderer("/dashboard/finance")("app/dashboard/finance/page.tsx");
  for (const id of ["synthese", "controles", "paiements-colis", "commissions", "recharges", "relais", "retraits", "soldes", "mouvements"]) {
    assert.ok(html.includes('id="' + id + '"'), id);
    assert.ok(html.includes('href="#' + id + '"'), id);
  }
  assert.ok(html.includes("Règlements des relais"));
  assert.ok(html.includes("hors plateforme"));
  assert.ok(html.includes("sans filtre de période"));
  assert.ok(html.includes("les soldes des portefeuilles restent actuels"));
  assert.ok(!html.includes("Flux wallet brut"));
  assert.ok(html.includes("Voir les dossiers"));
  for (const button of html.matchAll(/<button\b[^>]*>((?:(?!<\/button>)[\s\S])*)<\/button>/g)) {
    assert.ok(!button[1].includes("Solde disponible"), "un indicateur sans action n’est pas un bouton");
  }
});

test("finance relais : les deux sens, les livreurs et les colis sont accessibles séparément", () => {
  const html = appRenderer("/dashboard/finance")("components/relay-settlements-section.tsx", "RelaySettlementsSection");
  for (const text of ["Denkma doit aux relais", "Les relais doivent à Denkma", "Les relais doivent aux livreurs", "Déclarations à valider", "sans compensation", "Boutique test", "PKP-TEST", "Relais inactif"]) assert.ok(html.includes(text), text);
  assert.ok(html.includes('href="/dashboard/parcels/parcel_test"'));
  assert.ok(html.includes('href="/dashboard/relays/relay_test"'));
  assert.ok(html.includes("Valider le paiement"));
  assert.ok(html.includes("Rejeter la déclaration"));
});

test("finance relais : une panne ou une répartition invalide ne masque pas l’incomplétude des totaux", () => {
  const partial = appRenderer("/dashboard/finance", ["finance-overview"])("app/dashboard/finance/page.tsx");
  assert.ok(partial.includes("Denkma doit aux relais"));
  const failed = appRenderer("/dashboard/finance", ["finance-relay-settlements", "finance-relay-actions"])("components/relay-settlements-section.tsx", "RelaySettlementsSection");
  assert.ok(failed.includes("Impossible de charger les montants dus"));
  assert.ok(failed.includes("Impossible de charger les actions"));
  assert.ok(!failed.includes("Denkma doit aux relais"));
  const issues = appRenderer("/dashboard/finance", [], {
    "finance-relay-settlements": { totals: { ...settlementTotals, unavailable_count: 2 }, relays: [], total: 0 },
    "finance-relay-actions": { actions: [{ parcel_id: "broken", tracking_code: "PKP-BROKEN", issue: "Relais manquant" }], total: 1 },
  })("components/relay-settlements-section.tsx", "RelaySettlementsSection");
  assert.ok(issues.includes("les totaux sont incomplets jusqu’à correction"));
  assert.ok(issues.includes('href="/dashboard/parcels/broken"'));
});

test("finance relais : les boutons suivent les droits calculés côté serveur", () => {
  const render = appRenderer("/dashboard/finance");
  const pending = render("components/relay-settlement-action.tsx", "RelaySettlementActionCard", { item: { ...settlementAction, status: "pending", can_validate: false, can_reject: false } });
  assert.ok(pending.includes("Le relais doit effectuer ce paiement"));
  assert.ok(!pending.includes("Valider le paiement"));
  const payable = render("components/relay-settlement-action.tsx", "RelaySettlementActionCard", { item: { ...settlementAction, direction: "to_relay", status: "pending", can_reject: false } });
  assert.ok(payable.includes("Enregistrer le versement"));
  const upcoming = render("components/relay-settlement-action.tsx", "RelaySettlementActionCard", { item: { ...settlementAction, direction: "to_relay", status: "pending", stage: "upcoming", can_validate: false, can_reject: false } });
  assert.ok(upcoming.includes("Commission prévue, due après livraison"));
  assert.ok(!upcoming.includes("Enregistrer le versement"));
  const paid = render("components/relay-settlement-action.tsx", "RelaySettlementActionCard", { item: { ...settlementAction, status: "validated", can_validate: false, can_reject: false, note: "REF-123" } });
  assert.ok(paid.includes("REF-123"));
  assert.ok(!paid.includes("Rejeter la déclaration"));
});

test("livreurs : un compte actif n’est pas présenté comme connecté", () => {
  const html = appRenderer("/dashboard/drivers")("app/dashboard/drivers/page.tsx");
  assert.ok(html.includes("Compte / disponibilité"));
  assert.ok(html.includes("Compte actif"));
  assert.ok(html.includes("pas la présence en ligne"));
  assert.ok(html.includes("Sans disponibilité ni mission"));
  assert.ok(!html.includes("Hors ligne"));
});

test("relais : la complétion d’adresse indique le contrôle à effectuer", () => {
  const html = appRenderer("/dashboard/relays")("app/dashboard/relays/page.tsx");
  assert.ok(html.includes("Compléter adresses et positions"));
  assert.ok(html.includes("Contrôlez ensuite le résultat sur la carte"));
  assert.ok(html.includes("Mois des statistiques"));
  assert.ok(html.includes("Rechercher dans tous les relais"));
});

test("configuration : chaque bloc est verrouillé pendant sa sauvegarde", () => {
  const html = appRenderer("/dashboard/configuration", [], {}, true)("app/dashboard/configuration/page.tsx");
  assert.equal(Array.from(html.matchAll(/<fieldset\b[^>]*disabled=""/g)).length, 4);
  assert.ok(html.includes('aria-label="Activer le mode Express"'));
  assert.ok(html.includes('aria-label="Activer le contrôle de version mobile"'));
});

test("retraits : le bénéficiaire est accessible et le versement reste externe", () => {
  const html = appRenderer("/dashboard/payouts")("app/dashboard/payouts/page.tsx");
  assert.ok(html.includes('href="/dashboard/users/usr_test"'));
  assert.ok(html.includes("Virement bancaire"));
  assert.ok(html.includes("Confirmer un envoi ne transfère pas d’argent"));
});

test("une panne ne donne pas un faux résultat rassurant et propose la reprise", () => {
  const anomalies = appRenderer("/dashboard/anomalies", ["action-center"])("app/dashboard/anomalies/page.tsx");
  assert.ok(anomalies.includes("Erreur de chargement"));
  assert.ok(!anomalies.includes("Aucune anomalie"));
  const config = appRenderer("/dashboard/configuration", ["settings"])("app/dashboard/configuration/page.tsx");
  assert.ok(config.includes("Réessayer"));
  assert.ok(!config.includes("Sauvegarder tarifs et livraison"));
  const dashboard = appRenderer("/dashboard", ["dashboard"])("app/dashboard/page.tsx");
  assert.ok(dashboard.includes("Les autres rubriques restent accessibles"));
});
