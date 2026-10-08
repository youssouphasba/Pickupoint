const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const script = Array.from(html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g), match => match[1])
  .find(source => source.includes("L.map('senegalMap'"));

function run({readyState = 'complete', leafletAvailable = true, containerAvailable = true} = {}) {
  const listeners = new Map();
  const scheduled = [];
  const classes = new Set();
  const container = {classList: {add(value) { classes.add(value); }}, textContent: ''};
  const maps = [];
  const layers = [];
  const markers = [];
  const leaflet = {
    map(id, options) {
      const map = {id, options, fitBounds(bounds, padding) { this.bounds = bounds; this.padding = padding; }};
      maps.push(map);
      return map;
    },
    tileLayer(url, options) {
      const layer = {url, options, addTo(map) { this.map = map; return this; }};
      layers.push(layer);
      return layer;
    },
    divIcon(options) { return options; },
    marker(coordinates, options) {
      const marker = {coordinates, options,
        addTo(map) { this.map = map; return this; },
        bindPopup(content) { this.popup = content; return this; }};
      markers.push(marker);
      return marker;
    },
  };
  const document = {readyState,
    getElementById(id) { return id === 'senegalMap' && containerAvailable ? container : null; },
    addEventListener(event, callback) { listeners.set(event, callback); }};
  const window = {L: leafletAvailable ? leaflet : undefined};
  assert.ok(script, 'The coverage map script must be present');
  vm.runInNewContext(script, {window, document, L: window.L,
    setTimeout(callback, delay) { scheduled.push({callback, delay}); }});
  return {listeners, scheduled, classes, container, maps, layers, markers};
}

test('the coverage map uses the standard HTTPS tiles without a CARTO key', () => {
  const {layers} = run();
  assert.equal(layers.length, 1);
  assert.equal(layers[0].url, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  assert.doesNotMatch(html, /basemaps\.cartocdn\.com|carto\.com\/attributions/);
});

test('the copyright attribution is enabled, linked and not hidden by CSS', () => {
  const {maps, layers} = run();
  assert.equal(maps[0].options.attributionControl, true);
  assert.match(layers[0].options.attribution, /https:\/\/www\.openstreetmap\.org\/copyright/);
  assert.match(layers[0].options.attribution, /OpenStreetMap<\/a> contributors/);
  assert.doesNotMatch(html, /\.leaflet-control-attribution\s*\{[^}]*display\s*:\s*none/);
});

test('tile loading preserves the referrer and avoids unnecessary requests', () => {
  const {layers} = run();
  const {url, options} = layers[0];
  assert.equal(options.referrerPolicy, 'strict-origin-when-cross-origin');
  assert.equal(options.updateWhenIdle, true);
  assert.equal(options.updateWhenZooming, false);
  assert.equal(options.subdomains, undefined);
  assert.equal(options.detectRetina, undefined);
  assert.doesNotMatch(url, /\{r\}|\{s\}|@2x|\?/);
});

test('attribution icons do not inherit the full-size SVG map styling', () => {
  assert.match(html, /#senegalMap \.leaflet-control-attribution svg\{width:1em;height:\.667em\}/);
});

test('the existing coverage markers, popups and viewport are preserved', () => {
  const {maps, layers, markers} = run();
  assert.deepEqual(markers.map(marker => marker.options.title), [
    'Dakar', 'Pikine', 'Guédiawaye', 'Rufisque', 'Mbour', 'Thiès', 'Touba',
    'Diourbel', 'Louga', 'Saint-Louis', 'Kaolack', 'Tambacounda', 'Kolda', 'Ziguinchor',
  ]);
  assert.equal(markers.filter(marker => marker.options.icon.className.endsWith(' hub')).length, 5);
  assert.equal(maps[0].bounds.length, markers.length);
  assert.equal(maps[0].options.zoomControl, true);
  assert.equal(maps[0].options.scrollWheelZoom, false);
  assert.equal(layers[0].options.maxZoom, 19);
  for (const marker of markers) {
    assert.equal(marker.map, maps[0]);
    assert.match(marker.popup, /Couverte par Denkma/);
  }
});

test('initialization waits for the deferred Leaflet script and DOM readiness', () => {
  const result = run({readyState: 'loading'});
  assert.equal(result.maps.length, 0);
  assert.equal(result.scheduled.length, 0);
  assert.equal(typeof result.listeners.get('DOMContentLoaded'), 'function');
  result.listeners.get('DOMContentLoaded')();
  assert.equal(result.maps.length, 1);
  assert.match(html, /<script[^>]+src="https:\/\/unpkg\.com\/leaflet@1\.9\.4\/dist\/leaflet\.js"[^>]+defer/);
});

test('a failed Leaflet download shows a useful message without polling forever', () => {
  const result = run({leafletAvailable: false});
  assert.equal(result.maps.length, 0);
  assert.equal(result.scheduled.length, 0);
  assert.ok(result.classes.has('map-unavailable'));
  assert.match(result.container.textContent, /carte est momentanément indisponible/);
});

test('a missing map container does not initialize or schedule retries', () => {
  const result = run({containerAvailable: false});
  assert.equal(result.maps.length, 0);
  assert.equal(result.scheduled.length, 0);
});
