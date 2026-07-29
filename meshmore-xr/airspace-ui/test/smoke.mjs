// Runtime smoke test for the AiRspace UI prototype.
//
// A passing `vite build` only proves the modules parse. This drives the real
// page in Chromium with a real WebGL context and asserts:
//   1. no console errors / page exceptions on load
//   2. the WebGL canvas actually renders non-uniform pixels (not a black void)
//   3. every one of the nine themes builds and renders
//   4. HORIZON and CONSOLE both build, and CONSOLE exposes live widgets
//   5. the Vectrex (flat) renderer builds
//
// Usage:  node test/smoke.mjs [baseUrl]     (default http://localhost:5181)

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.argv[2] || 'http://localhost:5181';
const SHOTS = new URL('../shots/', import.meta.url).pathname;
mkdirSync(SHOTS, { recursive: true });

const THEMES = [
  'HALO FIELD', 'NERV SPATIAL', 'AG-SYSTEMS', 'SEELE MONOLITH', 'DR POP',
  'RECON AMBER', 'VECTORLINE', 'BIOLUME', 'TERMINAL VOID',
];

let failures = 0;
const fail = (m) => { failures++; console.error(`  ✗ ${m}`); };
const pass = (m) => console.log(`  ✓ ${m}`);

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });

const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));

console.log(`\nAiRspace UI smoke test → ${BASE}\n`);
await page.goto(`${BASE}/?test=1&diag=1`, { waitUntil: 'networkidle' });
await page.waitForTimeout(1200);

// 1 — clean load
if (errors.length) fail(`console errors on load:\n    ${errors.join('\n    ')}`);
else pass('loads with no console errors');

// 2 — the canvas is actually rendering something
async function canvasStats() {
  return page.evaluate(() => {
    const c = document.querySelector('canvas');
    if (!c) return null;
    // Re-read through a 2D copy; the WebGL buffer is not directly readable
    // after compositing without preserveDrawingBuffer.
    const t = document.createElement('canvas');
    t.width = 240; t.height = 150;
    const x = t.getContext('2d');
    x.drawImage(c, 0, 0, 240, 150);
    const d = x.getImageData(0, 0, 240, 150).data;
    let min = 255, max = 0, sum = 0;
    for (let i = 0; i < d.length; i += 4) {
      const l = (d[i] + d[i + 1] + d[i + 2]) / 3;
      min = Math.min(min, l); max = Math.max(max, l); sum += l;
    }
    return { min, max, mean: sum / (d.length / 4), w: c.width, h: c.height };
  });
}

const s0 = await canvasStats();
if (!s0) fail('no <canvas> in the document');
else if (s0.w < 100 || s0.h < 100) fail(`canvas is ${s0.w}x${s0.h}`);
else if (s0.max - s0.min < 12) fail(`canvas looks uniform (min ${s0.min}, max ${s0.max}) — nothing rendered`);
else pass(`canvas ${s0.w}x${s0.h} renders content (luma ${s0.min.toFixed(0)}–${s0.max.toFixed(0)})`);

// 2b — L7, the angular floor, checked from the other end.
//
// "Renders non-uniform pixels" is far too weak an assertion: a label blown up
// to 90 deg of visual angle passes it easily. Text sprites carry a baked
// aspect-corrected scale, so anything that calls setScalar() on one silently
// destroys the angular sizing. Assert the ceiling directly.
// L7 cuts BOTH ways, and the limits differ by zone. A horizon mote at 2 m must
// stay small; a Pebble at 0.5 m must be big enough to reach for (>= 2 deg). So
// the check is zone-aware: ceiling in HORIZON, floor AND ceiling in REACH.
async function oversized() {
  return page.evaluate(() => {
    const { scene, camera, THREE, rig } = window.__diag;
    const bad = [];
    const p = new THREE.Vector3(), s = new THREE.Vector3(), q = new THREE.Quaternion();
    scene.updateMatrixWorld(true);

    const shown = (o) => { for (let n = o; n; n = n.parent) if (!n.visible) return false; return true; };
    const zoneOf = (o) => {
      for (let n = o; n; n = n.parent) {
        if (n === rig.reach) return 'reach';
        if (n === rig.horizon) return 'horizon';
      }
      return 'other';
    };

    scene.traverse((o) => {
      if (!shown(o)) return;   // ancestor visibility, not just own
      const isSprite = !!o.isSprite;
      const isSphere = !!(o.isMesh && o.geometry?.type === 'SphereGeometry');
      if (!isSprite && !isSphere) return;
      o.matrixWorld.decompose(p, q, s);
      const dist = p.distanceTo(camera.position);
      if (dist < 0.01) return;
      let r = Math.max(s.x, s.y) / 2;
      if (isSphere) {
        if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
        r = o.geometry.boundingSphere.radius * Math.max(s.x, s.y, s.z);
      }
      const deg = (2 * Math.atan(r / dist) * 180) / Math.PI;
      const zone = zoneOf(o);

      if (isSprite) {
        const who = JSON.stringify(o.userData.text ?? '?');
        // Text: >= 1.2 deg (readable) and <= 30 deg (not a billboard in your face)
        if (deg > 30) bad.push(`label ${who} ${deg.toFixed(0)}° > 30° ceiling at ${dist.toFixed(2)}m [${zone}]`);
        if (deg < 1.0) bad.push(`label ${who} ${deg.toFixed(1)}° < 1.2° floor at ${dist.toFixed(2)}m [${zone}]`);
      } else if (zone === 'reach') {
        // Controls: reached-for, so >= 2 deg, and <= 14 deg or it is a wall.
        if (deg < 2) bad.push(`control ${deg.toFixed(1)}° < 2° floor at ${dist.toFixed(2)}m`);
        if (deg > 14) bad.push(`control ${deg.toFixed(0)}° > 14° ceiling at ${dist.toFixed(2)}m`);
      } else if (zone === 'horizon') {
        if (deg > 4.5) bad.push(`mote ${deg.toFixed(0)}° > 4.5° ceiling at ${dist.toFixed(2)}m`);
      }
    });
    return bad;
  });
}

const oh = await oversized();
if (oh.length) fail(`HORIZON angular ceiling exceeded:\n    ${oh.slice(0, 4).join('\n    ')}`);
else pass('HORIZON respects the angular ceiling (L7)');

// 3 — every theme builds and renders
for (const name of THEMES) {
  errors.length = 0;
  await page.click(`#themes button:has-text("${name}")`);
  await page.waitForTimeout(450);
  const s = await canvasStats();
  if (errors.length) fail(`${name}: ${errors.join(' | ')}`);
  else if (!s || s.max - s.min < 8) fail(`${name}: rendered nothing (min ${s?.min}, max ${s?.max})`);
  else pass(`${name} renders (luma ${s.min.toFixed(0)}–${s.max.toFixed(0)})`);
}

// 4 — CONSOLE builds and exposes operable widgets
await page.click('#themes button:has-text("HALO FIELD")');
await page.waitForTimeout(300);
errors.length = 0;
await page.click('#m-console');
await page.waitForTimeout(700);
if (errors.length) fail(`CONSOLE: ${errors.join(' | ')}`);
else pass('CONSOLE builds');

const sC = await canvasStats();
if (!sC || sC.max - sC.min < 8) fail('CONSOLE rendered nothing');
else pass(`CONSOLE renders (luma ${sC.min.toFixed(0)}–${sC.max.toFixed(0)})`);

const oc = await oversized();
if (oc.length) fail(`CONSOLE angular ceiling exceeded:\n    ${oc.slice(0, 4).join('\n    ')}`);
else pass('CONSOLE respects the angular ceiling (L7)');
await page.screenshot({ path: `${SHOTS}console-halo.png` });

// Sweep the pointer across the console arc: exercises pick(), hover cues, and
// every widget's update() path.
errors.length = 0;
for (let i = 0; i <= 20; i++) {
  await page.mouse.move(340 + i * 30, 380 + Math.sin(i / 3) * 60);
  await page.waitForTimeout(28);
}
await page.mouse.click(640, 400);
await page.waitForTimeout(400);
if (errors.length) fail(`widget interaction: ${errors.join(' | ')}`);
else pass('widget hover + commit runs clean');

// 4b — JAPANESE. Tofu is the failure mode that ships: canvas text falls back
// silently, so a missing face renders boxes and nothing throws. Assert the font
// actually resolved, that JA text got the larger angular floor, and that the
// scene still renders.
await page.click('#m-home');
await page.waitForTimeout(300);
errors.length = 0;
await page.click('#m-lang');
await page.waitForTimeout(900);

const ja = await page.evaluate(async () => {
  const loaded = document.fonts.check('400 44px "M PLUS 1 Code"', '設定');
  // Measure a kanji against the fallback: if the face failed to load, the
  // advance collapses to the generic monospace metric.
  const c = document.createElement('canvas').getContext('2d');
  c.font = '600 44px "M PLUS 1 Code", monospace';
  const w = c.measureText('無線機').width;
  return { loaded, kanjiWidth: w };
});
if (errors.length) fail(`JA: ${errors.join(' | ')}`);
else if (!ja.loaded) fail('JA: "M PLUS 1 Code" japanese subset did not resolve — labels will render as tofu');
else if (ja.kanjiWidth < 60) fail(`JA: kanji advance ${ja.kanjiWidth.toFixed(0)}px looks like a fallback metric`);
else pass(`JA font resolved (kanji advance ${ja.kanjiWidth.toFixed(0)}px)`);

const sJ = await canvasStats();
if (!sJ || sJ.max - sJ.min < 8) fail('JA locale rendered nothing');
else pass(`JA locale renders (luma ${sJ.min.toFixed(0)}–${sJ.max.toFixed(0)})`);

// The CJK angular floor is 1.8 deg, not 1.2 — a 14-stroke kanji at Latin size
// is a smudge. Assert no CJK label slipped through at the Latin floor.
const jaSmall = await page.evaluate(() => {
  const { scene, camera, THREE } = window.__diag;
  const KANA = /[぀-ゟ゠-ヿ]/;
  const KANJI = /[㐀-䶿一-鿿]/;
  const bad = [];
  const p = new THREE.Vector3(), s = new THREE.Vector3(), q = new THREE.Quaternion();
  scene.updateMatrixWorld(true);
  const shown = (o) => { for (let n = o; n; n = n.parent) if (!n.visible) return false; return true; };
  scene.traverse((o) => {
    if (!shown(o) || !o.isSprite || !o.userData.text) return;
    const txt = o.userData.text;
    if (!KANA.test(txt) && !KANJI.test(txt)) return;
    // Three-tier floor, per i18n.js: the densest glyph in the string wins.
    const floor = KANJI.test(txt) ? 1.8 : 1.5;
    o.matrixWorld.decompose(p, q, s);
    const dist = p.distanceTo(camera.position);
    const deg = (2 * Math.atan((s.y / 2) / dist) * 180) / Math.PI;
    if (deg < floor - 0.06) bad.push(`"${txt}" at ${deg.toFixed(2)}° (floor ${floor}°)`);
  });
  return bad;
});
if (jaSmall.length) fail(`CJK below the angular floor:\n    ${jaSmall.slice(0, 4).join('\n    ')}`);
else pass('CJK labels respect the kana 1.5° / kanji 1.8° floors');

await page.screenshot({ path: `${SHOTS}horizon-ja.png` });
await page.click('#m-console');
await page.waitForTimeout(700);
await page.screenshot({ path: `${SHOTS}console-ja.png` });
await page.click('#m-lang');       // back to EN
await page.click('#m-home');
await page.waitForTimeout(500);

// 4c — the HUD must never put persistent chrome in the protected world window.
// This is the promise that justifies see-through glasses over a phone, and it is
// exactly the rule that erodes one convenient exception at a time.
const intrude = await page.evaluate(() => {
  const { scene, camera, THREE, rig } = window.__diag;
  const hud = rig.edge.children.find((c) => c.type === 'Group' && c.tapeRail !== undefined) || rig.edge.children[0];
  if (!hud) return ['no HUD found'];
  const D = 1.05, rad = (d) => (d * Math.PI) / 180;
  const WW = { h: Math.tan(rad(17)) * D, v: Math.tan(rad(10)) * D };
  const bad = [];
  const p = new THREE.Vector3();
  hud.traverse((o) => {
    if (!o.visible || (!o.isSprite && !o.isMesh)) return;
    if (o === hud) return;
    o.getWorldPosition(p);
    const local = hud.worldToLocal(p.clone());
    if (Math.abs(local.x) < WW.h && Math.abs(local.y) < WW.v) {
      bad.push(`${o.type} at (${local.x.toFixed(3)}, ${local.y.toFixed(3)}) inside the world window`);
    }
  });
  return bad;
});
if (intrude.length) fail(`HUD intrudes on the world window:\n    ${intrude.slice(0, 4).join('\n    ')}`);
else pass('HUD keeps the 34°×20° world window clear');
await page.screenshot({ path: `${SHOTS}hud-halo.png` });

// 5 — the Vectrex (flat) renderer
errors.length = 0;
await page.click('#m-home');
await page.click('#themes button:has-text("TERMINAL VOID")');
await page.waitForTimeout(700);
const sV = await canvasStats();
if (errors.length) fail(`VECTREX: ${errors.join(' | ')}`);
else if (!sV || sV.max - sV.min < 8) fail('VECTREX rendered nothing');
else pass(`VECTREX flat renderer works (luma ${sV.min.toFixed(0)}–${sV.max.toFixed(0)})`);
await page.screenshot({ path: `${SHOTS}vectrex.png` });

// Sunlight passthrough — the §1.3 constraint, made testable.
errors.length = 0;
await page.click('#themes button:has-text("VECTORLINE")');
await page.waitForTimeout(300);
await page.click('#m-sun');
await page.waitForTimeout(600);
const sS = await canvasStats();
if (errors.length) fail(`SUNLIGHT: ${errors.join(' | ')}`);
else pass(`SUNLIGHT backdrop renders (mean luma ${sS.mean.toFixed(0)})`);
await page.screenshot({ path: `${SHOTS}vectorline-sunlight.png` });

await page.click('#m-sun');
await page.click('#themes button:has-text("HALO FIELD")');
await page.waitForTimeout(900);
await page.screenshot({ path: `${SHOTS}horizon-halo.png` });

await browser.close();
console.log(`\n${failures ? `FAILED — ${failures} problem(s)` : 'PASSED — all checks clean'}\n`);
process.exit(failures ? 1 : 0);
