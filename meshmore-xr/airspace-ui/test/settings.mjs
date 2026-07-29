// Settings-model invariants. Pure logic, no browser needed.
//
// The valuable assertion here is the CLAMP one: without it, "themes set
// defaults" and "the user needs reduced motion" are in direct conflict, and
// whichever runs last wins by accident. That is an accessibility regression
// nobody would notice until a user reported nausea.

import { THEMES } from '../src/airspace/theme.js';
import { SCHEMA, CLASS, resolve, missingThemeDefaults, illegalThemeKeys, themeOwnedKeys } from '../src/airspace/settings.js';

let fail = 0;
const ok = (m) => console.log(`  ✓ ${m}`);
const no = (m) => { fail++; console.error(`  ✗ ${m}`); };

console.log('\nAiRspace settings invariants\n');

// 1 — every theme supplies every THEME-class key
const owned = themeOwnedKeys();
let gaps = [];
for (const t of THEMES) {
  const m = missingThemeDefaults(t);
  if (m.length) gaps.push(`${t.key}: missing ${m.join(', ')}`);
}
gaps.length ? no(`incomplete theme defaults:\n    ${gaps.join('\n    ')}`)
            : ok(`all ${THEMES.length} themes supply all ${owned.length} theme-owned keys`);

// 2 — no theme tries to own a user- or a11y-class key
let illegal = [];
for (const t of THEMES) {
  const i = illegalThemeKeys(t);
  if (i.length) illegal.push(`${t.key}: ${i.join(', ')}`);
}
illegal.length ? no(`themes claiming non-theme keys:\n    ${illegal.join('\n    ')}`)
               : ok('no theme claims a user- or a11y-owned key');

// 3 — THE CLAMP. reduce-motion must survive every theme, including the ones
//     whose whole identity is motion.
let broke = [];
for (const t of THEMES) {
  const r = resolve(t, { 'a11y.reduceMotion': true });
  if (r['motion.amount'] !== 'none') broke.push(`${t.key} -> motion.amount=${r['motion.amount']}`);
  if (r['audio.packetDensity'] === 'dense') broke.push(`${t.key} -> packetDensity stayed dense`);
}
broke.length ? no(`reduce-motion overridden by theme:\n    ${broke.join('\n    ')}`)
             : ok('reduce-motion clamps motion.amount=none across all 9 themes');

// 4 — a user pin must survive a theme switch (that is its whole purpose)
{
  const pin = { 'reel.depth': 7 };
  const bad = THEMES.filter((t) => resolve(t, pin)['reel.depth'] !== 7).map((t) => t.key);
  bad.length ? no(`user pin lost on themes: ${bad.join(', ')}`)
             : ok('a user pin survives every theme switch');
}

// 5 — but an UNPINNED key must follow the theme, or theme profiles are pointless
{
  const depths = new Set(THEMES.map((t) => resolve(t)['reel.depth']));
  depths.size > 1 ? ok(`unpinned keys follow the theme (reel.depth spans ${[...depths].sort((a,b)=>a-b).join('/')})`)
                  : no('every theme resolved the same reel.depth — theme defaults are not applying');
}

// 6 — visual+haptic-only silences audio whatever the pack
{
  const loud = THEMES.filter((t) => resolve(t, { 'a11y.visualHapticOnly': true })['audio.enabled'] !== false);
  loud.length ? no(`audio still enabled on: ${loud.map((t) => t.key).join(', ')}`)
              : ok('visual+haptic-only disables audio across all 9 themes');
}

// 7 — seated 120 arc cannot leave the HUD off (it would strand the user)
{
  const off = THEMES.filter((t) => resolve(t, { 'a11y.seatedArc': '120' })['hud.density'] === 'off');
  off.length ? no(`HUD left off in seated mode on: ${off.map((t) => t.key).join(', ')}`)
             : ok('seated 120° arc forces the HUD on (TERMINAL VOID included)');
}

// 8 — every schema entry is presentable: a station and an AiRspace widget
{
  const orphan = Object.entries(SCHEMA).filter(([, d]) => !d.station || !d.widget).map(([k]) => k);
  orphan.length ? no(`settings with no CONSOLE home: ${orphan.join(', ')}`)
                : ok(`all ${Object.keys(SCHEMA).length} settings map to a station + widget`);
}

// 9 — class census, for the record
{
  const c = { theme: 0, user: 0, a11y: 0 };
  for (const d of Object.values(SCHEMA)) c[d.cls]++;
  ok(`class split — theme ${c.theme}, user ${c.user}, a11y ${c.a11y}`);
}

console.log(`\n${fail ? `FAILED — ${fail} problem(s)` : 'PASSED — all invariants hold'}\n`);
process.exit(fail ? 1 : 0);
