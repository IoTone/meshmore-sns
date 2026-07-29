// S1 HORIZON — the always-on mesh. Tier 1, spatially imagined.
//
// Not a screen and not a list: a VOLUMETRIC SHELL around you, every peer at its
// true bearing, true elevation, and true distance. The forward FOV is
// deliberately kept clear — with a 70 deg optic that protected window gets
// BIGGER, not busier.
//
// Recency is brightness. A node heard 5 s ago is at full luminance; at 30 min it
// is a dim ghost with a visible age. Staleness is never hidden.
//
// Every primitive here is volumetric: torus halos, fresnel-shaded motes,
// expanding shockwave rings, cone carets. Nothing is a flat annulus or a decal.

import * as THREE from 'three';
import { makeLabel } from '../airspace/label.js';
import { billboard } from '../airspace/Billboard.js';
import { volumetric, halo, pulseRing, caret, setOpacity } from '../airspace/materials.js';
import { t } from '../airspace/i18n.js';

const col = (h) => new THREE.Color(h);
const R = 2.5; // HORIZON radius, metres

export class Horizon extends THREE.Group {
  constructor(theme, cue, nodes) {
    super();
    this.theme = theme; this.cue = cue; this.nodes = nodes;
    this.motes = [];
    this.pulses = [];
    this.t = 0;
    this.build();
  }

  build() {
    const th = this.theme;
    const additive = th.substrate === 'additive';

    // HALO — real TORUS geometry. A RingGeometry annulus is a flat disc with a
    // hole: viewed at a grazing angle it collapses to a line and reads as a
    // rendering artefact. A torus has a tube you can see the roundness of, from
    // any angle, which is the whole point of L2.
    [0.4, 0.7, 1.0].forEach((f, i) => {
      const ring = halo(R * f, 0.016, th.accent, {
        additive, core: 0.5, opacity: 0.34 + i * 0.06, rimStrength: 0.55,
      });
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = -0.30;
      this.add(ring);

      const lp = new THREE.Vector3(R * f * 0.72, -0.24, -R * f * 0.69);
      const lab = makeLabel(t(['range.100m', 'range.1km', 'range.10km'][i]), th.text, {
        deg: 1.3, dist: lp.length(), backing: null,
      });
      lab.position.copy(lp);
      lab.material.opacity = 0.55;
      this.add(lab);
    });

    this.nodes.forEach((n) => {
      const g = new THREE.Group();
      const lum = 1 - n.age * 0.72;

      // A node with no position estimate MUST NOT be given a fake bearing. It
      // parks in a dedicated unlocated arc behind the dominant shoulder.
      const bearing = n.located ? n.bearing : Math.PI * 0.78;
      const dist = n.located ? n.dist : 0.42;
      const elev = n.located ? n.elev : -0.3;

      g.position.set(
        Math.sin(bearing) * R * dist,
        elev * R * 0.35 - 0.1,
        -Math.cos(bearing) * R * dist
      );

      // MOTE — sized in CONSTANT VISUAL ANGLE (~1.6 deg), shaded volumetrically.
      const d = g.position.length();
      const moteR = Math.max(0.010, d * 0.0140);
      const mote = new THREE.Mesh(
        new THREE.SphereGeometry(moteR, 22, 16),
        volumetric(n.located ? th.accent : th.warn, {
          additive, core: 0.42, opacity: lum, rimStrength: 0.85,
        })
      );
      g.add(mote);

      // Hop count as an equatorial BAND — a second torus around the mote. Reads
      // as structure on a sphere rather than as a number to parse.
      if (n.hops > 1) {
        const band = halo(moteR * 1.5, moteR * 0.14, th.alt, {
          additive, core: 0.7, opacity: 0.7 * lum, rimStrength: 0.5,
        });
        band.rotation.x = Math.PI / 2.6;
        g.add(band);
      }

      // Elevation CARET — a cone, not a triangle. Points up or down toward the
      // node's true altitude, so "the ridge station is above you" is a fact you
      // can see rather than a number you read.
      if (Math.abs(n.elev) > 0.25 && n.located) {
        const c = caret(moteR * 1.1, th.alt, { additive, core: 0.6, opacity: 0.85 * lum });
        c.rotation.x = n.elev > 0 ? -Math.PI / 2 : Math.PI / 2;
        c.position.y = n.elev > 0 ? moteR * 2.4 : -moteR * 2.4;
        g.add(c);
      }

      // NO SPUR HERE. A spur from the user's eye to every node passes straight
      // through their head, and at ~0.1 m the perspective smears a 6 mm tube
      // into a wedge that fills the lower FOV. SPUR belongs to S3 NODE FOCUS —
      // ONE selected node, drawn from a point out in front of the user.

      const lab = makeLabel(
        n.located ? n.name : `${n.name} · ${t('node.bearingUnknown')}`,
        th.text,
        { deg: 1.35, dist: d, backing: th.substrate === 'panel' ? th.panel : null }
      );
      lab.position.y = -(moteR + d * 0.020);
      lab.material.opacity = Math.max(0.35, lum);
      g.add(lab);

      g.userData = { node: n, mote, lum, label: lab };
      this.motes.push(g);
      this.add(g);
    });
  }

  // PULSE — the one motion primitive. An expanding torus whose TUBE THINS as it
  // grows, so it reads as a shockwave losing energy rather than a donut
  // inflating. The mesh visibly breathes; this is "always-on" made perceptible.
  pulse(moteGroup) {
    const d = moteGroup.position.length();
    const r0 = Math.max(0.012, d * 0.016);
    const p = pulseRing(r0, r0 * 0.30, this.theme.accent);
    p.position.copy(moteGroup.position);
    p.userData.life = 1;
    p.userData.r0 = r0;
    this.pulses.push(p);
    this.add(p);
  }

  update(dt, camera) {
    this.t += dt;
    this.motes.forEach((g, i) => {
      billboard(g.userData.label, camera);
      if (this.theme.key === 'biolume') {
        g.userData.mote.scale.setScalar(1 + Math.sin(this.t * 0.9 + i) * 0.09);
      }
    });
    for (let i = this.pulses.length - 1; i >= 0; i--) {
      const p = this.pulses[i];
      p.userData.life -= dt / 0.7;
      const k = 1 - p.userData.life;              // 0 -> 1
      p.lookAt(camera.position);
      const grow = 1 + k * 2.6;
      // Counter-scale the tube so the band stays ~constant in angular terms.
      p.geometry.dispose();
      p.geometry = new THREE.TorusGeometry(
        p.userData.r0 * grow, Math.max(0.0006, p.userData.r0 * 0.30 / grow), 8, 48
      );
      setOpacity(p.material, Math.max(0, p.userData.life) * 0.55);
      if (p.userData.life <= 0) { this.remove(p); this.pulses.splice(i, 1); }
    }
  }
}
