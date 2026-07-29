// THE HUD — head-locked persistent status, calibrated to a 70 deg optic.
//
// FOV BUDGET (XREAL Aura class, 70 deg diagonal on a 16:9 panel):
//     ~61 deg horizontal  x  ~34 deg vertical
//
// That is nearly double the horizontal budget the earlier field notes assumed
// (45–50 deg), and the temptation it creates is exactly the wrong instinct:
// more room does NOT mean more HUD. It means a bigger protected world window.
//
//     +---------------------------------------------------------------+  ^
//     |            C O M P A S S   T A P E  (full width, 3 deg)        |  |
//     +---------------------------------------------------------------+  |
//     |  tier  |                                             | channel |  |
//     |  link  |          W O R L D   W I N D O W            | unread  | 34
//     |  batt  |          34 deg x 20 deg — NOTHING          | queue   | deg
//     |        |          PERSISTENT MAY ENTER HERE          |         |  |
//     +--------+---------------------------------------------+---------+  |
//     |              transcript line (only while speaking)              |  |
//     +---------------------------------------------------------------+  v
//     <---------------------- ~61 deg ------------------------------->
//
// Two rules make this a HUD and not a dashboard:
//   1. The world window is inviolable. It is why someone wears see-through
//      glasses instead of holding a phone.
//   2. The HUD is never the only channel for anything. It can be dimmed to zero
//      and every piece of information remains reachable elsewhere.

import * as THREE from 'three';
import { makeLabel } from '../airspace/label.js';
import { volumetric, segBar, caret } from '../airspace/materials.js';
import { t } from '../airspace/i18n.js';

const col = (h) => new THREE.Color(h);
const D = 1.05;                 // HUD plane distance, metres
const rad = (d) => (d * Math.PI) / 180;
// Half-extents of the 70 deg diagonal optic at distance D.
const HALF_H = Math.tan(rad(61 / 2)) * D;
const HALF_V = Math.tan(rad(34 / 2)) * D;
// The protected centre. Nothing persistent inside this.
export const WORLD_WINDOW = { h: Math.tan(rad(34 / 2)) * D, v: Math.tan(rad(20 / 2)) * D };
// A label sized for the HUD plane distance D shrinks as it slides toward the
// edge of the tape, because the corner of the viewport is FURTHER AWAY than the
// centre. Size every HUD label for the worst case so the angular floor holds
// everywhere, not just dead ahead. Floors are floors, not targets.
const HUD_FAR = Math.sqrt(D * D + HALF_H * HALF_H + HALF_V * HALF_V);

export class Hud extends THREE.Group {
  constructor(theme, nodes) {
    super();
    this.theme = theme;
    this.nodes = nodes;
    this.dim = 1;
    this.ticks = [];
    this.build();
  }

  build() {
    const th = this.theme;
    const add = (o, x, y, z = 0) => { o.position.set(x, y, z); this.add(o); return o; };

    // ---- COMPASS TAPE ----------------------------------------------------
    // The hero element, and the only one that could not exist on a phone: a
    // bearing ribbon showing true north and every peer at its ACTUAL bearing.
    // It is the HUD's tie to the HORIZON — glance up, see who is where, without
    // turning your head.
    this.tape = new THREE.Group();
    this.tape.position.set(0, HALF_V * 0.87, 0);
    this.add(this.tape);

    this.tapeRail = new THREE.Mesh(
      new THREE.BoxGeometry(HALF_H * 2, 0.004, 0.004),
      volumetric(th.alt, { core: 0.4, opacity: 0.5, rimStrength: 0.3 })
    );
    this.tape.add(this.tapeRail);

    // Cardinal marks are CARET cones — volumetric, legible edge-on.
    this.cardinals = ['hud.n', 'hud.e', 'hud.s', 'hud.w'].map((k, i) => {
      const g = new THREE.Group();
      const c = caret(0.014, th.accent, { core: 0.6 });
      c.rotation.x = Math.PI / 2; // point down at the rail
      g.add(c);
      const l = makeLabel(t(k), th.text, { deg: 1.3, dist: HUD_FAR });
      l.position.y = 0.030;
      g.add(l);
      g.userData.bearing = (i * Math.PI) / 2;
      this.tape.add(g);
      return g;
    });

    // Peer ticks ride the same tape at their true bearing.
    this.ticks = this.nodes.filter((n) => n.located).map((n) => {
      const m = new THREE.Mesh(
        new THREE.BoxGeometry(0.005, 0.014, 0.005),
        volumetric(th.accent, { core: 0.55, rimStrength: 0.5 })
      );
      m.userData.node = n;
      m.position.y = -0.014;
      this.tape.add(m);
      return m;
    });

    // ---- LEFT RAIL: link state ------------------------------------------
    const L = -HALF_H * 0.88;
    this.tierLab = add(makeLabel(t('hud.tier1'), th.accent, { deg: 1.35, dist: HUD_FAR }), L + 0.10, HALF_V * 0.42);
    add(makeLabel(t('hud.link'), th.alt, { deg: 1.15, dist: HUD_FAR }), L + 0.045, HALF_V * 0.16);
    this.linkBar = add(segBar(5, 4, th.accent, th.panel), L + 0.115, HALF_V * 0.16);
    add(makeLabel(t('hud.batt'), th.alt, { deg: 1.15, dist: HUD_FAR }), L + 0.045, HALF_V * -0.02);
    this.battBar = add(segBar(5, 3, th.warn, th.panel), L + 0.115, HALF_V * -0.02);

    // ---- RIGHT RAIL: traffic --------------------------------------------
    const R = HALF_H * 0.88;
    this.chanLab = add(makeLabel(t('hud.channel'), th.text, { deg: 1.3, dist: HUD_FAR }), R - 0.11, HALF_V * 0.42);
    this.peersLab = add(makeLabel(`${t('hud.peers')} 12`, th.text, { deg: 1.3, dist: HUD_FAR }), R - 0.09, HALF_V * 0.16);
    add(makeLabel(t('hud.queue'), th.alt, { deg: 1.15, dist: HUD_FAR }), R - 0.05, HALF_V * -0.02);
    this.queueBar = add(segBar(5, 1, th.alt, th.panel), R - 0.12, HALF_V * -0.02);

    // ---- BOTTOM: transcript ---------------------------------------------
    // The one element permitted near the lower world window, because the user
    // looks down less than up and a live transcript must be readable without
    // hunting. Hidden unless speaking.
    this.transcript = add(makeLabel('　', th.text, { deg: 1.5, dist: HUD_FAR }), 0, -HALF_V * 0.80);
    this.transcript.visible = false;
  }

  setTranscript(text) {
    this.remove(this.transcript);
    this.transcript = makeLabel(text, this.theme.text, { deg: 1.5, dist: HUD_FAR });
    this.transcript.position.set(0, -HALF_V * 0.80, 0);
    this.transcript.visible = !!text;
    this.add(this.transcript);
  }

  relocalize() {
    const th = this.theme;
    const swap = (sp, key, colr, deg) => {
      this.remove(sp);
      const n = makeLabel(t(key), colr, { deg, dist: HUD_FAR });
      n.position.copy(sp.position);
      this.add(n);
      return n;
    };
    this.tierLab = swap(this.tierLab, 'hud.tier1', th.accent, 1.35);
    this.chanLab = swap(this.chanLab, 'hud.channel', th.text, 1.3);
    const p = this.peersLab.position.clone();
    this.remove(this.peersLab);
    this.peersLab = makeLabel(`${t('hud.peers')} 12`, th.text, { deg: 1.3, dist: HUD_FAR });
    this.peersLab.position.copy(p);
    this.add(this.peersLab);
    this.cardinals.forEach((g, i) => {
      const old = g.children[1];
      g.remove(old);
      const l = makeLabel(t(['hud.n', 'hud.e', 'hud.s', 'hud.w'][i]), th.text, { deg: 1.3, dist: HUD_FAR });
      l.position.y = 0.030;
      g.add(l);
    });
  }

  // Head-locked: the HUD rides the head rigidly. A lazy-follow HUD reads as a
  // "tiny window off in the distance at a strange angle" (field, 2026-07-09).
  update(dt, camera) {
    const fwd = new THREE.Vector3();
    camera.getWorldDirection(fwd);
    this.position.copy(camera.position).add(fwd.multiplyScalar(D));
    this.quaternion.copy(camera.quaternion);

    const yaw = Math.atan2(fwd.x, -fwd.z);
    // Compass tape scrolls under the head: a bearing maps to a horizontal
    // offset, and anything outside the FOV is culled rather than clamped (a
    // clamped marker piles up at the edge and lies about direction).
    const place = (obj, bearing) => {
      let d = ((bearing - yaw + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
      const x = (d / rad(61 / 2)) * HALF_H;
      const off = Math.abs(x) > HALF_H * 0.97;
      // Park at the edge rather than letting x run to several metres for a
      // bearing behind the user. It is culled either way, but an object flung
      // 3.5 m off-axis pollutes every distance-based measurement of the scene.
      obj.position.x = off ? Math.sign(x) * HALF_H : x;
      obj.visible = !off;
    };
    this.cardinals.forEach((g) => place(g, g.userData.bearing));
    this.ticks.forEach((m) => {
      place(m, m.userData.node.bearing);
      const lum = 1 - m.userData.node.age * 0.7;
      m.material.uniforms.uOpacity.value = lum * this.dim;
    });

    this.traverse((o) => {
      if (o.isSprite) o.material.opacity = this.dim;
    });
  }
}
