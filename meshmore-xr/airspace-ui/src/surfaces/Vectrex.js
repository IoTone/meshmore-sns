// THE VECTREX EXCEPTION — TERMINAL VOID's flat renderer.
//
// Low power means NOT LIGHTING A VOLUME. A theme that claims low power while
// rendering a particle field is lying. So this theme drops the volumetric layer
// entirely and renders a flat vector overlay on a single head-locked plane at
// 1.6 m: stroke geometry only, one hue, no particles, no glow, one draw plane.
//
// The reference is exact rather than decorative: the Vectrex was a vector CRT
// whose colour came from a TRANSLUCENT PLASTIC SCREEN OVERLAY slotted in front
// of the tube. That maps perfectly onto an additive see-through display — our
// "overlay" is a single tinted plane and the real world is the phosphor
// darkness behind it. The 1982 hack and the 2026 constraint are the same hack.
//
// Widget SEMANTICS, focus order, audio and haptics are unchanged. Only the
// renderer swaps. That is the whole argument for having a widget library.

import * as THREE from 'three';
import { makeLabel } from '../airspace/label.js';
import { t } from '../airspace/i18n.js';

const col = (h) => new THREE.Color(h);

export class Vectrex extends THREE.Group {
  constructor(theme, nodes) {
    super();
    this.theme = theme; this.nodes = nodes;
    this.t = 0;
    this.build();
  }

  strokes(pts, opacity = 1, width = 1) {
    const g = new THREE.BufferGeometry().setFromPoints(pts);
    return new THREE.LineSegments(
      g,
      new THREE.LineBasicMaterial({
        color: col(this.theme.accent), transparent: true, opacity,
        blending: THREE.AdditiveBlending, depthWrite: false, linewidth: width,
      })
    );
  }

  build() {
    const th = this.theme;
    const S = 0.62; // half-extent of the flat screen at 1.6 m

    // The "screen overlay": one tinted plane, exactly as the Vectrex shipped.
    const overlay = new THREE.Mesh(
      new THREE.PlaneGeometry(S * 2.1, S * 1.6),
      new THREE.MeshBasicMaterial({
        color: col(th.alt), transparent: true, opacity: 0.10,
        blending: THREE.AdditiveBlending, depthWrite: false,
      })
    );
    this.add(overlay);

    // Range rings, drawn as actual vector strokes.
    const ring = [];
    [0.26, 0.44, 0.60].forEach((r) => {
      for (let i = 0; i < 64; i++) {
        const a0 = (i / 64) * Math.PI * 2, a1 = ((i + 1) / 64) * Math.PI * 2;
        ring.push(new THREE.Vector3(Math.cos(a0) * r, Math.sin(a0) * r * 0.72, 0));
        ring.push(new THREE.Vector3(Math.cos(a1) * r, Math.sin(a1) * r * 0.72, 0));
      }
    });
    this.add(this.strokes(ring, 0.32));

    // Nodes as vector glyphs plus a monospace readout. In TERMINAL VOID the
    // primitives are REPLACED BY GLYPHS: a node is text, not a dot.
    const marks = [];
    this.nodes.forEach((n) => {
      const r = 0.20 + n.dist * 0.42;
      const x = Math.cos(n.bearing) * r;
      const y = Math.sin(n.bearing) * r * 0.72;
      const s = 0.018;
      marks.push(new THREE.Vector3(x - s, y, 0), new THREE.Vector3(x + s, y, 0));
      marks.push(new THREE.Vector3(x, y - s, 0), new THREE.Vector3(x, y + s, 0));

      const deg = String(Math.round(((n.bearing * 180) / Math.PI + 360) % 360)).padStart(3, '0');
      const txt = `${n.located ? '' : '?'}${n.name} ${Math.round(n.dist * 3400)}m ${deg}`;  // callsigns/units stay Latin in every locale
      const lab = makeLabel(txt, th.accent, { deg: 1.25, dist: 1.6 });
      lab.position.set(x + 0.02, y - 0.028, 0);
      lab.material.opacity = Math.max(0.4, 1 - n.age * 0.7);
      this.add(lab);
    });
    this.add(this.strokes(marks, 0.95));

    // Centre reticle — you.
    const you = [];
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI * 2;
      you.push(new THREE.Vector3(Math.cos(a) * 0.012, Math.sin(a) * 0.012, 0));
      you.push(new THREE.Vector3(Math.cos(a) * 0.03, Math.sin(a) * 0.03, 0));
    }
    this.add(this.strokes(you, 0.8));

    const hdr = makeLabel(`${t('hud.tier1')} · 12 ${t('hud.peers')} · ${t('hud.channel')}`, th.accent, { deg: 1.3, dist: 1.6 });
    hdr.position.set(0, 0.50, 0);
    this.add(hdr);

    const foot = makeLabel(t('vectrex.foot'), th.alt, { deg: 1.2, dist: 1.6 });
    foot.position.set(0, -0.50, 0);
    this.add(foot);
  }

  // Head-locked: the whole point is that it is ONE PLANE in front of you.
  update(dt, camera) {
    this.t += dt;
    const fwd = new THREE.Vector3();
    camera.getWorldDirection(fwd);
    this.position.copy(camera.position).add(fwd.multiplyScalar(1.6));
    this.quaternion.copy(camera.quaternion);
  }
}
