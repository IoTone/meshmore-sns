// AiRspace UI — prototype driver.
//
// Drag to look (stands in for head tracking). Hover + click operates widgets
// (stands in for gaze + pinch). Everything else is the real library.

import * as THREE from 'three';
import { THEMES } from './airspace/theme.js';
import { Cue } from './airspace/Cue.js';
import { Rig } from './airspace/Rig.js';
import { Ember } from './airspace/widgets.js';
import { Horizon } from './surfaces/Horizon.js';
import { Console } from './surfaces/Console.js';
import { Vectrex } from './surfaces/Vectrex.js';
import { makeMesh } from './mesh/fakeMesh.js';
import { Hud } from './surfaces/Hud.js';
import { setLocale, getLocale, loadFonts, t } from './airspace/i18n.js';
import '@fontsource/m-plus-1-code/latin-400.css';
import '@fontsource/m-plus-1-code/japanese-400.css';

// `?test=1` keeps the drawing buffer readable so the Playwright smoke test can
// sample rendered pixels. Off by default — it costs bandwidth in production.
const TEST = new URLSearchParams(location.search).has('test');
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, preserveDrawingBuffer: TEST });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
// The target optic is 70 deg DIAGONAL (XREAL Aura class, FHD 16:9) = ~61 deg
// horizontal x ~34 deg vertical. three.js PerspectiveCamera fov is VERTICAL, so
// 34 is the correct number — not 70.
//
// And the viewport is LETTERBOXED to 16:9. A browser window is whatever shape
// the user dragged it to, and rendering the device's vertical FOV into a wider
// window silently widens the horizontal FOV — which pushed the HUD rails, sized
// for a real 61 deg, off the edge of the screen. Letterboxing means what you see
// here is what the optic shows, and the world-window claim is verifiable rather
// than aspirational.
const DEVICE_ASPECT = 16 / 9;
const camera = new THREE.PerspectiveCamera(34, DEVICE_ASPECT, 0.05, 60);
camera.position.set(0, 0, 0);

const cue = new Cue();
const nodes = makeMesh();
let themeIndex = 0;
let theme = THEMES[0];
let mode = 'home';
let sunlight = false;

let rig, horizon, consoleSurface, vectrex, hud;
let hudOn = true;
const embers = [];

// ---- the passthrough backdrop --------------------------------------------
// On an additive display BLACK IS TRANSPARENT — you cannot draw dark, only add
// light. "Sunlight" swaps the void for a bright real-world backdrop so the
// additive themes visibly wash out and the panel-led ones hold. This is the
// design brief's §1.3 constraint, made testable.
const sky = new THREE.Mesh(
  new THREE.SphereGeometry(40, 32, 20),
  new THREE.MeshBasicMaterial({ color: 0xbcd2e8, side: THREE.BackSide })
);
sky.visible = false;
scene.add(sky);

function build() {
  if (rig) {
    scene.remove(rig.horizon, rig.reach, rig.read, rig.edge, rig.ground);
  }
  rig = new Rig(scene);
  horizon = null; consoleSurface = null; vectrex = null; hud = null;

  scene.background = new THREE.Color(sunlight ? 0xbcd2e8 : theme.ground);
  sky.visible = sunlight;

  if (theme.render === 'flat') {
    // The Vectrex exception replaces every surface, not just the home one — and
    // that includes the HUD. A flat vector overlay IS the HUD in this theme.
    vectrex = new Vectrex(theme, nodes);
    rig.read.add(vectrex);
    return;
  }

  // The HUD is head-locked chrome and rides above whichever surface is active.
  if (hudOn) { hud = new Hud(theme, nodes); rig.edge.add(hud); }
  if (mode === 'home') {
    horizon = new Horizon(theme, cue, nodes);
    rig.horizon.add(horizon);
  } else {
    consoleSurface = new Console(theme, cue, {
      themeNames: THEMES.map((t) => t.name),
      themeIndex,
      onTheme: (i) => setTheme(i, true),
    });
    rig.reach.add(consoleSurface);
  }
}

function setTheme(i, fromConsole) {
  themeIndex = i; theme = THEMES[i];
  document.documentElement.style.setProperty('--ac', `#${theme.accent.toString(16).padStart(6, '0')}`);
  [...document.querySelectorAll('#themes button')].forEach((b, k) => b.setAttribute('aria-pressed', k === i));
  status();
  // Restyling the live HORIZON is the point of the THEME tumbler; rebuilding
  // the console under the user's hand mid-spin is not.
  if (fromConsole && mode === 'console') {
    scene.background = new THREE.Color(sunlight ? 0xbcd2e8 : theme.ground);
    return;
  }
  build();
  cue.fire(theme, 'TIER_CHANGE');
}

function setMode(m) {
  mode = m;
  document.getElementById('m-home').setAttribute('aria-pressed', m === 'home');
  document.getElementById('m-console').setAttribute('aria-pressed', m === 'console');
  build(); status();
}

function status() {
  const sub = { panel: 'panel-led · survives sunlight', additive: 'additive-led · black is transparent', hybrid: 'hybrid' }[theme.substrate];
  document.getElementById('status').innerHTML =
    `<b>${theme.name}</b> &nbsp;<span class="k">${sub}</span><br>` +
    `<span class="k">pack</span> ${theme.pack} &nbsp; <span class="k">tts</span> ${theme.tts}<br>` +
    `<span class="k">${theme.note}</span>`;
}

// ---- HUD ------------------------------------------------------------------
const themeRow = document.getElementById('themes');
THEMES.forEach((t, i) => {
  const b = document.createElement('button');
  b.innerHTML = `<span class="sw" style="background:#${t.accent.toString(16).padStart(6, '0')}"></span>${t.name}`;
  b.onclick = () => { cue.audio.init(); setTheme(i); };
  themeRow.appendChild(b);
});
document.getElementById('m-home').onclick = () => { cue.audio.init(); setMode('home'); };
document.getElementById('m-console').onclick = () => { cue.audio.init(); setMode('console'); };
document.getElementById('m-hud').onclick = (e) => {
  hudOn = !hudOn;
  e.currentTarget.setAttribute('aria-pressed', hudOn);
  build();
};
document.getElementById('m-lang').onclick = async (e) => {
  const next = getLocale() === 'en' ? 'ja' : 'en';
  setLocale(next);
  await loadFonts();
  e.currentTarget.textContent = next === 'ja' ? '日本語' : 'EN';
  build(); status();
};
document.getElementById('m-sun').onclick = (e) => {
  sunlight = !sunlight;
  e.currentTarget.setAttribute('aria-pressed', sunlight);
  build();
};

// ---- look + pointer -------------------------------------------------------
// Open facing a populated arc rather than straight ahead. HORIZON deliberately
// keeps the forward FOV clear, so a dead-ahead start shows an empty room and
// reads as broken — the paradigm has to introduce itself.
let yaw = -1.15, pitch = -0.08, dragging = false, lastX = 0, lastY = 0, dragWidget = null;
const ptr = new THREE.Vector2(0, 0);
const ray = new THREE.Raycaster();

renderer.domElement.addEventListener('pointerdown', (e) => {
  cue.audio.init();
  const w = pick();
  if (w && w.draggable) { dragWidget = w; return; }
  dragging = true; lastX = e.clientX; lastY = e.clientY;
});
addEventListener('pointerup', () => {
  if (dragWidget) { dragWidget = null; return; }
  dragging = false;
});
renderer.domElement.addEventListener('pointermove', (e) => {
  const r = renderer.domElement.getBoundingClientRect();
  ptr.x = ((e.clientX - r.left) / r.width) * 2 - 1;
  ptr.y = -((e.clientY - r.top) / r.height) * 2 + 1;
  if (dragWidget) { scrub(dragWidget); return; }
  if (!dragging) return;
  yaw -= (e.clientX - lastX) * 0.0032;
  pitch = Math.max(-0.9, Math.min(0.9, pitch - (e.clientY - lastY) * 0.0032));
  lastX = e.clientX; lastY = e.clientY;
});
renderer.domElement.addEventListener('click', () => {
  const w = pick();
  if (w && !w.draggable) w.commit();
});

function widgets() { return consoleSurface ? consoleSurface.widgets : []; }

function pick() {
  const ws = widgets();
  if (!ws.length) return null;
  ray.setFromCamera(ptr, camera);
  let best = null, bestD = Infinity;
  const p = new THREE.Vector3();
  ws.forEach((w) => {
    w.getWorldPosition(p);
    const d = ray.ray.distanceToPoint(p);
    if (d < (w.hitRadius || 0.05) && d < bestD) { best = w; bestD = d; }
  });
  return best;
}

function scrub(w) {
  const p = new THREE.Vector3();
  w.getWorldPosition(p);
  ray.setFromCamera(ptr, camera);
  const hit = new THREE.Vector3();
  const plane = new THREE.Plane();
  const n = new THREE.Vector3();
  camera.getWorldDirection(n);
  plane.setFromNormalAndCoplanarPoint(n, p);
  if (!ray.ray.intersectPlane(plane, hit)) return;
  const local = w.worldToLocal(hit.clone());
  w.scrub(Math.max(0, Math.min(1, local.x / w.len + 0.5)));
}

// ---- simulated mesh traffic ----------------------------------------------
let acc = 0, tick = 0;
function traffic(dt) {
  acc += dt;
  if (acc < 0.55) return;
  acc = 0; tick++;
  if (!horizon) return;
  const g = horizon.motes[Math.floor(Math.random() * horizon.motes.length)];
  if (!g) return;
  horizon.pulse(g);
  const n = g.userData.node;
  const bearing = n.located ? n.bearing : null;
  cue.fire(theme, 'PACKET', { now: performance.now() / 1000, step: tick % 5, bearing, headYaw: yaw });

  // A DIRECTIONAL notification: spatialized to the sender's true bearing, with
  // an EMBER at the matching viewport edge. Never in front of your face.
  if (tick % 7 === 0) {
    cue.fire(theme, tick % 14 === 0 ? 'MSG_DIRECT' : 'MSG_CHANNEL', { bearing, headYaw: yaw });
    const em = new Ember(theme, `${n.name}: on my way`, bearing);
    embers.push(em);
    rig.edge.add(em);
  }
}

// ---- loop -----------------------------------------------------------------
function fitViewport() {
  let w = innerWidth, h = Math.round(w / DEVICE_ASPECT);
  if (h > innerHeight) { h = innerHeight; w = Math.round(h * DEVICE_ASPECT); }
  camera.aspect = DEVICE_ASPECT;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h);
  const c = renderer.domElement;
  c.style.position = 'absolute';
  c.style.left = `${Math.round((innerWidth - w) / 2)}px`;
  c.style.top = `${Math.round((innerHeight - h) / 2)}px`;
}
addEventListener('resize', fitViewport);
fitViewport();

const clock = new THREE.Clock();
function loop() {
  const dt = Math.min(0.05, clock.getDelta());
  camera.quaternion.setFromEuler(new THREE.Euler(pitch, yaw, 0, 'YXZ'));

  traffic(dt);
  if (horizon) horizon.update(dt, camera);
  if (vectrex) vectrex.update(dt, camera);
  if (hud) hud.update(dt, camera);
  if (consoleSurface) {
    consoleSurface.update(dt, camera);
    const hot = pick();
    widgets().forEach((w) => { w.setHot(w === hot); w.setNear(w === hot); });
  }

  // EMBERs ride the viewport edge on the bearing of their cause and decay in
  // ~3 s. Transient signal; the panel log is the durable record.
  const fwd = new THREE.Vector3(); camera.getWorldDirection(fwd);
  const right = new THREE.Vector3().crossVectors(fwd, new THREE.Vector3(0, 1, 0)).normalize();
  for (let i = embers.length - 1; i >= 0; i--) {
    const em = embers[i];
    const side = em.bearing == null ? 0 : Math.sign(Math.sin(em.bearing - yaw)) || 1;
    em.position.copy(camera.position).add(fwd.clone().multiplyScalar(1.1))
      .add(right.clone().multiplyScalar(side * 0.62)).add(new THREE.Vector3(0, -0.22, 0));
    em.quaternion.copy(camera.quaternion);
    if (!em.update(dt)) { rig.edge.remove(em); embers.splice(i, 1); }
  }

  cue.audio.relaxPackets();
  renderer.render(scene, camera);
  requestAnimationFrame(loop);
}

(async function boot() {
  // Canvas text silently falls back to tofu if the face is not resolved yet,
  // and never repaints — so resolve the Japanese subset BEFORE the first build.
  await loadFonts();
  setTheme(0);
  build();
  status();
  loop();
})();

// `?diag=1` exposes the scene graph to test/diag.mjs.
if (new URLSearchParams(location.search).has('diag')) {
  window.__diag = { scene, camera, THREE, get rig() { return rig; } };
}
