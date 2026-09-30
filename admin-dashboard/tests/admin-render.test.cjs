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

function appRenderer(pathname, errorKeys = [], overrides = {}, pending = false) {
  const queries = {
    me: { email: "admin@example.test", full_name: "Admin test", role: "admin" },
    settings: {}, "action-center": actions, "admin-events": { events: [], unread_count: 0 },
    dashboard: { total_parcels: 4, parcels_today: 1, delivered: 2, failed: 0, active_parcels: 2, pending_payouts: 0, success_rate: 100, active_relays: 1, active_drivers: 2, live_fleet: 1, signal_lost: 0, critical_delay: 0, stale_parcels: 0, payment_blocked_parcels: 0, revenue_xof: 1000 },
    "finance-overview": finance, "finance-recon": {},
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
  assert.ok(html.includes("Les soldes des portefeuilles restent actuels"));
  assert.ok(!html.includes("Flux wallet brut"));
  assert.ok(html.includes("Voir les dossiers"));
  for (const button of html.matchAll(/<button\b[^>]*>((?:(?!<\/button>)[\s\S])*)<\/button>/g)) {
    assert.ok(!button[1].includes("Solde disponible"), "un indicateur sans action n’est pas un bouton");
  }
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
