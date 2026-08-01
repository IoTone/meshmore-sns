// The RADIO rack's commit model, exercised. The staged/live split is the whole
// design, so it is the thing worth a test rather than the thing worth a look.
import { chromium } from 'playwright';
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1280, height: 800 } });
const errs = [];
p.on('pageerror', e => errs.push(String(e)));
await p.goto('http://localhost:5181/?diag=1', { waitUntil: 'networkidle' });
await p.click('#m-radio');
await p.waitForTimeout(600);

const r = async (fn) => p.evaluate(fn);
let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { console.log(`  ✓ ${name}`); ok++; } else { console.log(`  ✗ ${name}`); bad++; } };

check('rack built', await r(() => !!window.__diag.rack));
check('live == pending at rest', await r(() => {
  const k = window.__diag.rack; return JSON.stringify(k.live) === JSON.stringify(k.pending);
}));
check('nothing pending at rest', await r(() => !window.__diag.rack.dirty.on));

// Stage a spreading-factor change.
await r(() => { const k = window.__diag.rack; k.pending.sf = 10; k.refresh(); });
check('staging lights PENDING', await r(() => window.__diag.rack.dirty.on));
check('staging does NOT touch live', await r(() => window.__diag.rack.live.sf === 7));

await r(() => window.__diag.rack.commitAir());
check('commit moves pending -> live', await r(() => window.__diag.rack.live.sf === 10));
check('commit clears PENDING', await r(() => !window.__diag.rack.dirty.on));
check('commit retains the previous set', await r(() => window.__diag.rack.previous?.sf === 7));

await r(() => window.__diag.rack.revertAir());
check('revert restores the previous set', await r(() => window.__diag.rack.live.sf === 7));
check('revert also unstages', await r(() => window.__diag.rack.pending.sf === 7));

// A frequency the 125 kHz grid could not express — the crash that shipped.
check('live frequency is on the encoder grid', await r(() => {
  const k = window.__diag.rack;
  return k.widgets.some(w => w.values && w.values.includes(910.525));
}));
check('no console errors', errs.length === 0);
if (errs.length) console.log(errs.join('\n'));
console.log(bad ? `\nFAILED — ${bad} check(s)` : `\nPASSED — ${ok} checks clean`);
await b.close();
process.exit(bad ? 1 : 0);
