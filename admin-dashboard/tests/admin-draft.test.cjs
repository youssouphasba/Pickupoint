const test = require("node:test");
const assert = require("node:assert/strict");
const { createLoader } = require("./load-typescript.cjs");

function draftHarness(initial) {
  const slots = [];
  let cursor = 0;
  let pending = [];
  const react = {
    useState(initialValue) {
      const id = cursor++;
      if (!(id in slots)) slots[id] = initialValue;
      return [slots[id], (value) => { slots[id] = typeof value === "function" ? value(slots[id]) : value; }];
    },
    useRef(value) {
      const id = cursor++;
      if (!(id in slots)) slots[id] = { current: value };
      return slots[id];
    },
    useCallback(callback) { return callback; },
    useEffect(callback, dependencies) {
      const id = cursor++;
      if (!slots[id] || dependencies.some((value, index) => value !== slots[id][index])) pending.push(callback);
      slots[id] = dependencies;
    },
  };
  const { useAdminDraft } = createLoader({ react })("lib/use-admin-draft.ts");
  let server = initial;
  function render(nextServer = server) {
    server = nextServer;
    cursor = 0;
    const result = useAdminDraft(server);
    const effects = pending;
    pending = [];
    effects.forEach((effect) => effect());
    cursor = 0;
    return useAdminDraft(server);
  }
  return render;
}

test("une nouvelle réponse serveur actualise un bloc non modifié", () => {
  const render = draftHarness(null);
  assert.equal(render().draft, null);
  const data = { value: 1 };
  assert.equal(render(data).draft, data);
  const updated = { value: 2 };
  assert.equal(render(updated).draft, updated);
});

test("sauvegarder un autre bloc ne remplace pas les saisies non enregistrées", () => {
  const render = draftHarness({ price: 10 });
  render().setDraft((current) => ({ ...current, price: 15 }));
  assert.equal(render({ price: 10, refreshed: true }).draft.price, 15);
  assert.equal(render({ price: 20 }).draft.price, 15);
});

test("une sauvegarde réussie adopte la réponse serveur sans rétablir l’ancienne valeur", () => {
  const render = draftHarness({ price: 10 });
  render().setDraft({ price: 15 });
  const saved = { price: 15 };
  render().acceptSaved(saved);
  assert.equal(render().draft, saved);
  assert.equal(render({ price: 16 }).draft.price, 16);
  render().setDraft({ price: 17 });
  assert.equal(render({ price: 18 }).draft.price, 17);
});
