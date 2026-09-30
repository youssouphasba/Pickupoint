const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { createLoader, root } = require("./load-typescript.cjs");

const load = createLoader();
const { ADMIN_PAGES, ADMIN_NAVIGATION, adminPageForPath, searchAdminNavigation } = load("lib/admin-navigation.ts");
const display = load("lib/admin-display.ts");
const pageFile = (href) => path.join(root, "app", href.replace(/^\//, ""), "page.tsx");

function staticRoutes(directory, route = "/dashboard") {
  const result = [];
  if (fs.existsSync(path.join(directory, "page.tsx"))) result.push(route);
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && !entry.name.startsWith("[")) result.push(...staticRoutes(path.join(directory, entry.name), route + "/" + entry.name));
  }
  return result;
}

test("tous les écrans existants restent accessibles, une seule fois", () => {
  const hrefs = Array.from(ADMIN_PAGES, (page) => page.href);
  assert.equal(new Set(hrefs).size, hrefs.length);
  assert.deepEqual(hrefs.sort(), staticRoutes(path.join(root, "app/dashboard")).sort());
  assert.equal(ADMIN_NAVIGATION.length, 6);
});

test("chaque écran a une indication, un mode d’emploi et des liens valides", () => {
  for (const page of ADMIN_PAGES) {
    assert.ok(fs.existsSync(pageFile(page.href)), page.href);
    assert.ok(page.label && page.description && page.Icon);
    assert.equal(page.steps.length, 3);
    assert.ok(page.related.length >= 2);
    for (const link of page.related) {
      const target = adminPageForPath(link.href);
      assert.ok(target, link.href);
      const anchor = link.href.split("#")[1];
      if (anchor) assert.ok(target.sections.some((section) => section.id === anchor), link.href);
    }
  }
});

test("les accès rapides correspondent à des sections uniques réellement présentes", () => {
  for (const page of ADMIN_PAGES.filter((page) => page.sections)) {
    const source = fs.readFileSync(pageFile(page.href), "utf8");
    assert.equal(new Set(Array.from(page.sections, (section) => section.id)).size, page.sections.length);
    for (const section of page.sections) {
      assert.equal(source.split('id="' + section.id + '"').length - 1, 1, page.href + "#" + section.id);
    }
  }
});

test("la recherche tolère accents, espaces et les anciens noms d’écrans", () => {
  const found = (query) => Array.from(searchAdminNavigation(query).flatMap((group) => group.pages), (page) => page.href);
  assert.ok(found("  SEcurite  ").includes("/dashboard/security"));
  assert.ok(found("flotte live").includes("/dashboard/fleet"));
  assert.ok(found("décaissement").includes("/dashboard/payouts"));
  assert.ok(found("audit log").includes("/dashboard/audit-log"));
  assert.ok(found("heatmap").includes("/dashboard/heatmap"));
  assert.ok(found("horaires").includes("/dashboard/relays"));
  assert.equal(found("zzzz introuvable").length, 0);
  assert.equal(found(" ").length, ADMIN_PAGES.length);
});

test("le fil d’Ariane distingue les fiches et ignore les routes inconnues", () => {
  assert.equal(adminPageForPath("/dashboard/users/usr_123").detailLabel, "Dossier utilisateur");
  assert.equal(adminPageForPath("/dashboard/parcels/prc_123").href, "/dashboard/parcels");
  assert.equal(adminPageForPath("/dashboard/relays/rel_123").href, "/dashboard/relays");
  assert.equal(adminPageForPath("/dashboard/finance?from_date=2026-09-01#controles").href, "/dashboard/finance");
  assert.equal(adminPageForPath("/dashboard/settings/alerts/").label, "Mes alertes admin");
  assert.equal(adminPageForPath("/dashboard/unknown"), undefined);
  assert.equal(adminPageForPath("/dashboard/finance-unknown"), undefined);
  assert.equal(adminPageForPath("/dashboard/settings"), undefined);
});

test("les liens des actions ouvrent le bon dossier sans fausse destination", () => {
  assert.equal(display.adminActionHref({ href: "/dashboard/support?conversation=x", parcel_id: "p" }), "/dashboard/support?conversation=x");
  assert.equal(display.adminActionHref({ href: "#", parcel_id: "p/1" }), "/dashboard/parcels/p%2F1");
  assert.equal(display.adminActionHref({ user_id: "u 1" }), "/dashboard/users/u%201");
  assert.equal(display.adminActionHref({}, "/dashboard/payouts"), "/dashboard/payouts");
  assert.equal(display.adminActionHref({ href: "https://external.example" }), undefined);
  assert.equal(display.adminActionHref({}, "/dashboard/unknown"), undefined);
});

test("les statuts et payeurs absents ne sont pas inventés", () => {
  assert.equal(display.paymentStatusLabel("paid"), "Réglé");
  assert.equal(display.paymentStatusLabel(undefined), "Paiement non renseigné");
  assert.equal(display.paymentStatusLabel("future_status"), "Statut à vérifier");
  assert.equal(display.payerLabel("sender"), "Expéditeur");
  assert.equal(display.payerLabel("recipient"), "Destinataire");
  assert.equal(display.payerLabel(null), "Payeur non renseigné");
  assert.equal(display.settlementStatusLabel("declared"), "Déclaré, à vérifier");
  assert.equal(display.payoutMethodLabel("bank"), "Virement bancaire");
  assert.equal(display.payoutMethodLabel("cash"), "Espèces");
  assert.equal(display.payoutMethodLabel("wave"), "Wave");
  assert.equal(display.payoutMethodLabel(undefined), "Mode non renseigné");
});
