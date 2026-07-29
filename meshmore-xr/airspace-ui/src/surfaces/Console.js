// THE CONSOLE — settings, spatially.
//
// The Material answer is a LazyColumn of ListItems with trailing Switches.
// Floating that in space is the exact thing we are rejecting.
//
// SETTINGS IS A PLACE, NOT A LIST. An instrument console curved around you at
// reach height — the thing a pilot turns to, not a document they scroll.
//
// Seven stations on a 140 deg arc. You turn to face one; the others dim and
// recede but STAY VISIBLE — you never lose your place, which is the thing a
// navigation stack always costs you. No search field. No scroll.

import * as THREE from 'three';
import { makeLabel } from '../airspace/label.js';
import { billboard } from '../airspace/Billboard.js';
import { Pebble, Detent, Rail, Tumbler } from '../airspace/widgets.js';
import { REACH, LABEL_DEG } from '../airspace/constants.js';
import { shard, volumetric, setColor } from '../airspace/materials.js';
import { t } from '../airspace/i18n.js';

const col = (h) => new THREE.Color(h);
// REACH now lives in constants.js so widgets and their host cannot drift.

export class Console extends THREE.Group {
  constructor(theme, cue, opts = {}) {
    super();
    this.theme = theme; this.cue = cue;
    this.widgets = [];
    this.stations = [];
    this.onTheme = opts.onTheme;
    this.themeNames = opts.themeNames || [];
    this.themeIndex = opts.themeIndex || 0;
    this.build();
  }

  station(name, angleDeg, builder) {
    const th = this.theme;
    const g = new THREE.Group();
    const a = (angleDeg * Math.PI) / 180;
    g.position.set(Math.sin(a) * REACH, 0, -Math.cos(a) * REACH);
    g.userData.angle = a;

    // Each station is a physical place. The backing is painted, not assumed —
    // panel surfaces are not alpha-transparent (field-confirmed).
    // Seven stations across 140 deg is ~23 deg apart, which at REACH is only
    // ~0.25 m of arc — so a 0.30 m plate overlaps its neighbours into one
    // continuous band and the "stations are places" reading collapses. Keep the
    // plate narrower than the spacing.
    // A SHARD, not a plane: real thickness and a lit edge, so a station reads
    // as a physical place you turn to rather than a decal hanging in the air.
    const plate = shard(0.215, 0.23, th.panel, {
      depth: 0.018, opacity: th.substrate === 'additive' ? 0.30 : 0.80,
    });
    plate.position.z = -0.025;
    g.add(plate);
    g.userData.plate = plate;

    const title = makeLabel(name, th.alt, { deg: LABEL_DEG, dist: REACH });
    title.position.set(0, 0.098, 0);
    g.add(title);
    g.userData.title = title;

    builder(g);
    this.stations.push(g);
    this.add(g);
    return g;
  }

  add3(g, w, x, y) {
    w.position.set(x, y, 0.01);
    g.add(w);
    this.widgets.push(w);
    return w;
  }

  build() {
    const th = this.theme;

    // Radio TX power is a RAIL you slide. Region is a TUMBLER you spin.
    // TTS is a DETENT you seat. Nothing here is a row in a list.
    this.station(t('station.identity'), -60, (g) => {
      this.add3(g, new Detent(th, this.cue, t('w.advertLoc'), true), -0.05, 0.03);
      this.add3(g, new Pebble(th, this.cue, t('w.rename'), () => {}), 0.058, 0.03);
    });

    this.station(t('station.radio'), -35, (g) => {
      this.add3(g, new Rail(th, this.cue, t('w.txPower'), { min: 0, max: 22, value: 17, steps: 11, unit: ' dBm' }), 0, 0.045);
      this.add3(g, new Tumbler(th, this.cue, t('w.sf'), ['SF7', 'SF8', 'SF9', 'SF10', 'SF11'], 0), 0, -0.052);
    });

    this.station(t('station.voice'), -12, (g) => {
      this.add3(g, new Detent(th, this.cue, t('w.tts'), false), -0.05, 0.045);
      this.add3(g, new Detent(th, this.cue, t('w.pttOnly'), true), 0.052, 0.045);
      this.add3(g, new Rail(th, this.cue, t('w.rate'), { min: 0.6, max: 1.6, value: 1, steps: 10 }), 0, -0.058);
    });

    // Theme is a TUMBLER whose rotation restyles the ACTUAL HORIZON behind you,
    // live. You pick by living in it for five seconds, not by reading a swatch.
    this.station(t('station.theme'), 12, (g) => {
      this.add3(g, new Tumbler(th, this.cue, t('w.theme'), this.themeNames, this.themeIndex,
        (_v, i) => { if (this.onTheme) this.onTheme(i); }), 0, 0.01);
    });

    // Accessibility is a STATION, not a submenu, and is reachable from every
    // surface with one gesture.
    this.station(t('station.access'), 35, (g) => {
      this.add3(g, new Detent(th, this.cue, t('w.reduceMotion'), false), -0.05, 0.045);
      this.add3(g, new Detent(th, this.cue, t('w.seated'), false), 0.052, 0.045);
      this.add3(g, new Rail(th, this.cue, t('w.textScale'), { min: 1, max: 2, value: 1.2, steps: 10, unit: '×' }), 0, -0.058);
    });

    this.station(t('station.uplink'), 60, (g) => {
      this.add3(g, new Pebble(th, this.cue, t('w.grabRegion'), () => {
        this.cue.fire(th, 'TIER_CHANGE');
      }), -0.05, 0.03);
      this.add3(g, new Detent(th, this.cue, t('w.autoSync'), true), 0.058, 0.03);
    });

    // Safety confirmations use a PUSH-THROUGH commit and are IDENTICAL in all
    // nine themes. A safety signal is not themeable and not a preference.
    this.station(t('station.safety'), 84, (g) => {
      const p = new Pebble(th, this.cue, t('w.halt'), () => this.cue.fire(th, 'CRITICAL'), { r: 0.032 });
      setColor(p.body.material, th.alert);  // ShaderMaterial: no .color to copy into
      this.add3(g, p, 0, 0.01);
    });
  }

  update(dt, camera) {
    const fwd = new THREE.Vector3();
    camera.getWorldDirection(fwd);
    const yaw = Math.atan2(fwd.x, -fwd.z);

    this.stations.forEach((s) => {
      billboard(s, camera);
      // The station you face is lit; the others dim and recede but never vanish.
      let d = Math.abs(((s.userData.angle - yaw + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
      const focus = Math.max(0, 1 - d / 0.85);
      s.userData.plate.material.uniforms.uOpacity.value = (this.theme.substrate === 'additive' ? 0.12 : 0.35) + focus * 0.5;
      s.userData.title.material.opacity = 0.35 + focus * 0.65;
      s.scale.setScalar(0.86 + focus * 0.18);
    });
    this.widgets.forEach((w) => { billboard(w, camera); w.update(dt); });
  }
}
