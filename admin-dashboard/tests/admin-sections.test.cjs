const test = require("node:test");
const assert = require("node:assert/strict");
const React = require("react");
const { createLoader } = require("./load-typescript.cjs");

function sectionEffect(hash) {
  const scrolled = [];
  const listeners = new Map();
  const cleanups = [];
  const window = {
    location: { hash },
    addEventListener: (event, callback) => listeners.set(event, callback),
    removeEventListener: (event, callback) => {
      if (listeners.get(event) === callback) listeners.delete(event);
    },
  };
  const document = { getElementById: (id) => ({ scrollIntoView: () => scrolled.push(id) }) };
  const load = createLoader({ react: {
    ...React, useState: () => ["", () => {}],
    useEffect: (effect) => cleanups.push(effect()),
  } }, { window, document });
  return { nav: load("components/page-section-nav.tsx").PageSectionNav, scrolled, listeners, cleanups };
}

test("un lien vers une section asynchrone rejoint la cible après chargement", () => {
  const harness = sectionEffect("#controles");
  harness.nav({ page: "/dashboard/finance", hiddenSections: ["controles"] });
  assert.deepEqual(harness.scrolled, []);
  harness.cleanups.pop()();
  harness.nav({ page: "/dashboard/finance" });
  assert.deepEqual(harness.scrolled, ["controles"]);
  assert.equal(harness.listeners.size, 1);
  harness.cleanups.pop()();
  assert.equal(harness.listeners.size, 0);
});

test("une ancre absente n’est pas utilisée comme destination", () => {
  const harness = sectionEffect("#inconnue");
  harness.nav({ page: "/dashboard/configuration" });
  assert.deepEqual(harness.scrolled, []);
});
