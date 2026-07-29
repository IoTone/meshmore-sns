// AiRspace UI — the widget set.
//
// Every widget obeys the seven laws. Critically: NO WIDGET KNOWS A COLOUR, A
// FONT, OR A SOUND. Each takes a theme token and a Cue sink. That is what makes
// nine themes cost styling instead of nine implementations.
//
// Material equivalents, for the migration table:
//   Pebble  <- Button/FAB      Detent <- Switch/Checkbox   Rail   <- Slider
//   Tumbler <- RadioGroup      Column <- ProgressIndicator Ember  <- Snackbar
//   Slate   <- TextField (display half)

import * as THREE from 'three';
import { makeLabel, scaleLabel } from './label.js';
import { angularSize } from './Billboard.js';
import { REACH, LABEL_DEG, LABEL_SUB_DEG, LABEL_FACE_DEG } from './constants.js';
import { volumetric, halo, setColor, setOpacity } from './materials.js';

const col = (h) => new THREE.Color(h);

class Widget extends THREE.Group {
  constructor(theme, cue, label) {
    super();
    this.theme = theme; this.cue = cue; this.label = label;
    this.hot = false;        // hover
    this.near = false;       // PROXIMATE — responds BEFORE contact
    this.enabled = true;
    this.hitRadius = 0.05;
    this.dwell = 0;          // L6 — gaze+dwell parity with pinch
  }
  // Subclasses override. Returns true if the widget consumed the commit.
  commit() { return false; }
  setHot(v) {
    if (v === this.hot) return;
    this.hot = v;
    if (v && this.enabled) this.cue.fire(this.theme, 'HOVER');
  }
  setNear(v) {
    if (v === this.near) return;
    this.near = v;
    if (v && this.enabled) this.cue.fire(this.theme, 'PROXIMATE');
  }
  update() {}
}

// ---------------------------------------------------------------- PEBBLE ----
// A weighted oblate spheroid. A SPHERE IS THE IDEAL CONTROL SURFACE — identical
// from every angle, so it can never foreshorten (L2).
//
// `proximate` is the state Material has no equivalent for: the pebble swells ~4%
// when the hand is still 15 cm away. It is what makes spatial controls feel
// alive and is the cheapest "wow" in the library.
export class Pebble extends Widget {
  constructor(theme, cue, label, onCommit, { r = 0.026 } = {}) {
    super(theme, cue, label);
    this.onCommit = onCommit;
    this.r = Math.max(r, angularSize(2, 0.5) / 2); // L7: reached-for >= 2 deg
    this.hitRadius = this.r * 2.6;

    const geo = new THREE.SphereGeometry(this.r, 28, 20);
    geo.scale(1, 0.82, 1); // oblate — reads as a button, not a marble
    // Volumetric: a fresnel rim makes the sphere read as a lit orb rather than
    // the flat coloured circle MeshBasicMaterial would give us.
    this.body = new THREE.Mesh(geo, volumetric(theme.accent, { core: 0.45, rimStrength: 0.7 }));
    this.add(this.body);

    // The rim ignites on hover — a real TORUS encircling the pebble, so the
    // hover state has depth and survives being viewed edge-on.
    this.rim = halo(this.r * 1.38, this.r * 0.10, theme.text, { core: 0.9, opacity: 0, rimStrength: 0.5 });
    this.add(this.rim);

    // L6 — the dwell ring is an ANNULUS that fills, not a stroke that grows.
    this.dwellRing = new THREE.Mesh(
      new THREE.TorusGeometry(this.r * 1.75, this.r * 0.09, 8, 48, 0.0001),
      volumetric(theme.alt, { core: 0.85, rimStrength: 0.4 })
    );
    this.add(this.dwellRing);

    if (label) {
      const l = makeLabel(label, theme.text, { deg: LABEL_DEG, dist: REACH, backing: null });
      l.position.set(0, -this.r * 2.6, 0);
      this.add(l);
    }
    this.press = 0;
  }
  commit() {
    if (!this.enabled) { this.cue.fire(this.theme, 'DENY'); return true; }
    this.press = 1;
    this.cue.fire(this.theme, 'COMMIT');
    if (this.onCommit) this.onCommit();
    return true;
  }
  update(dt) {
    this.press = Math.max(0, this.press - dt * 4.5);
    const swell = 1 + (this.near ? 0.04 : 0) + (this.hot ? 0.09 : 0);
    // Depress ALONG THE HEAD VECTOR (local +z after billboarding), with overshoot.
    const sink = -this.press * this.r * 0.7 + Math.sin(this.press * Math.PI) * this.r * 0.12;
    this.body.scale.setScalar(swell);
    this.body.position.z = sink;
    setOpacity(this.rim.material, this.hot ? 0.9 : this.near ? 0.3 : 0);
    this.rim.visible = this.hot || this.near;
    this.rim.scale.setScalar(swell);

    if (this.hot && this.enabled) this.dwell = Math.min(1, this.dwell + dt / 0.9);
    else this.dwell = Math.max(0, this.dwell - dt * 3);
    this.dwellRing.geometry.dispose();
    this.dwellRing.geometry = new THREE.TorusGeometry(
      this.r * 1.75, this.r * 0.09, 8, 48, Math.max(0.0001, this.dwell * Math.PI * 2)
    );
    this.dwellRing.visible = this.dwell > 0.02;
  }
}

// ---------------------------------------------------------------- DETENT ----
// The toggle. A slug that travels a short track and SEATS into one of two wells.
//
// State is read from POSITION AND DEPTH, never colour. A coloured pill fails for
// colour-blind users, in direct sun, and in the single-hue themes (RECON,
// TERMINAL VOID). Position + depth never fails, and it is legible in silhouette
// from any angle — which a Material switch is not.
export class Detent extends Widget {
  constructor(theme, cue, label, value, onChange) {
    super(theme, cue, label);
    this.value = !!value; this.onChange = onChange;
    this.travel = 0.032;
    this.hitRadius = 0.05;

    this.track = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.011, this.travel * 2, 8, 18),
      volumetric(theme.panel, { core: 0.55, rimStrength: 0.35 })
    );
    this.track.rotation.z = Math.PI / 2;
    this.add(this.track);

    this.slug = new THREE.Mesh(
      new THREE.SphereGeometry(0.017, 26, 18),
      volumetric(theme.accent, { core: 0.45, rimStrength: 0.75 })
    );
    this.add(this.slug);

    if (label) {
      const l = makeLabel(label, theme.text, { deg: LABEL_DEG, dist: REACH });
      l.position.set(0, -0.045, 0);
      this.add(l);
    }
    this.x = this.value ? this.travel : -this.travel;
  }
  commit() {
    this.value = !this.value;
    this.cue.fire(this.theme, 'SEAT', { on: this.value });
    if (this.onChange) this.onChange(this.value);
    return true;
  }
  update(dt) {
    const target = this.value ? this.travel : -this.travel;
    this.x += (target - this.x) * Math.min(1, dt * 14);
    this.slug.position.x = this.x;
    // On = raised and lit. Off = seated far, low, dim. Depth carries the state.
    this.slug.position.z = this.value ? 0.012 : -0.006;
    this.slug.scale.setScalar((this.value ? 1.12 : 0.92) * (this.hot ? 1.1 : 1));
    setColor(this.slug.material, this.value ? this.theme.accent : this.theme.alt);
  }
}

// ------------------------------------------------------------------ RAIL ----
// The slider. A TUBE (never a line — L2) with a spherical bead, and physical
// notches rather than tick marks.
//
// Audio pitch tracks the value continuously while dragging: THE SLIDER IS
// AUDIBLE, which makes eyes-free adjustment possible.
export class Rail extends Widget {
  constructor(theme, cue, label, { min = 0, max = 10, value = 5, steps = 10, unit = '' } = {}, onChange) {
    super(theme, cue, label);
    Object.assign(this, { min, max, value, steps, unit, onChange });
    this.len = 0.155;
    this.hitRadius = 0.05;
    this.draggable = true;

    this.rod = new THREE.Mesh(
      new THREE.CylinderGeometry(0.005, 0.005, this.len, 16),
      volumetric(theme.panel, { core: 0.5, rimStrength: 0.4 })
    );
    this.rod.rotation.z = Math.PI / 2;
    this.add(this.rod);

    // Notches are geometry, not marks.
    for (let i = 0; i <= steps; i++) {
      const n = new THREE.Mesh(
        new THREE.CylinderGeometry(0.0075, 0.0075, 0.0035, 12),
        volumetric(theme.alt, { core: 0.5, opacity: 0.7, rimStrength: 0.4 })
      );
      n.rotation.z = Math.PI / 2;
      n.position.x = -this.len / 2 + (i / steps) * this.len;
      this.add(n);
    }

    this.bead = new THREE.Mesh(
      new THREE.SphereGeometry(0.016, 26, 18),
      volumetric(theme.accent, { core: 0.45, rimStrength: 0.75 })
    );
    this.add(this.bead);

    this.readout = makeLabel(this.fmt(), theme.text, { deg: LABEL_DEG, dist: REACH });
    this.readout.position.set(0, 0.042, 0);
    this.add(this.readout);

    if (label) {
      const l = makeLabel(label, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
      l.position.set(0, -0.042, 0);
      this.add(l);
    }
    this.lastStep = this.stepIndex();
  }
  fmt() { return `${this.value}${this.unit}`; }
  stepIndex() { return Math.round(((this.value - this.min) / (this.max - this.min)) * this.steps); }

  // t: 0..1 along the rail
  scrub(t) {
    const raw = this.min + t * (this.max - this.min);
    const snapped = Math.round(raw / ((this.max - this.min) / this.steps)) * ((this.max - this.min) / this.steps);
    const v = Math.max(this.min, Math.min(this.max, Math.round(snapped * 10) / 10));
    if (v !== this.value) {
      this.value = v;
      const si = this.stepIndex();
      if (si !== this.lastStep) {
        this.lastStep = si;
        this.cue.fire(this.theme, 'DETENT', { step: si }); // pitch tracks value
      }
      this.remove(this.readout);
      this.readout = makeLabel(this.fmt(), this.theme.text, { deg: LABEL_DEG, dist: REACH });
      this.readout.position.set(0, 0.042, 0);
      this.add(this.readout);
      if (this.onChange) this.onChange(this.value);
    }
  }
  update(dt) {
    const t = (this.value - this.min) / (this.max - this.min);
    this.bead.position.x = -this.len / 2 + t * this.len;
    this.bead.scale.setScalar(this.hot ? 1.22 : this.near ? 1.06 : 1);
    this.bead.position.z = this.hot ? 0.01 : 0;
  }
}

// --------------------------------------------------------------- TUMBLER ----
// The enum picker. A rotating drum, combination-lock style: one value faces you,
// neighbours curve away above and below.
//
// A radio group is n rectangles competing for attention. A tumbler has exactly
// one focal value and shows adjacency for free.
export class Tumbler extends Widget {
  constructor(theme, cue, label, values, index, onChange) {
    super(theme, cue, label);
    this.values = values; this.index = index || 0; this.onChange = onChange;
    this.hitRadius = 0.062;
    this.radius = 0.052;
    this.angle = 0; this.targetAngle = 0;

    this.drum = new THREE.Mesh(
      new THREE.CylinderGeometry(this.radius, this.radius, 0.052, 36, 1, true),
      volumetric(theme.panel, { core: 0.5, opacity: 0.55, rimStrength: 0.45 })
    );
    this.drum.rotation.z = Math.PI / 2;
    this.add(this.drum);

    this.faces = values.map((v) => {
      const l = makeLabel(String(v), theme.text, { deg: LABEL_FACE_DEG, dist: REACH });
      this.add(l);
      return l;
    });
    if (label) {
      const l = makeLabel(label, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
      l.position.set(0, -0.072, 0);
      this.add(l);
    }
    this.targetAngle = -this.index * ((Math.PI * 2) / values.length);
  }
  commit() { this.step(1); return true; }
  step(d) {
    this.index = (this.index + d + this.values.length) % this.values.length;
    this.targetAngle -= d * ((Math.PI * 2) / this.values.length);
    this.cue.fire(this.theme, 'DETENT', { step: this.index });
    if (this.onChange) this.onChange(this.values[this.index], this.index);
  }
  update(dt) {
    this.angle += (this.targetAngle - this.angle) * Math.min(1, dt * 9);
    const step = (Math.PI * 2) / this.values.length;
    this.faces.forEach((f, i) => {
      const a = this.angle + i * step;
      const y = Math.sin(a) * this.radius;
      const z = Math.cos(a) * this.radius;
      f.position.set(0, y, z);
      const front = Math.max(0, Math.cos(a));
      f.material.opacity = 0.12 + front * 0.88;   // only the facing value is legible
      scaleLabel(f, 0.78 + front * 0.28);         // relative — never setScalar
      f.visible = z > -this.radius * 0.2;
    });
    setOpacity(this.drum.material, this.hot ? 0.8 : 0.5);
  }
}

// ---------------------------------------------------------------- COLUMN ----
// Progress. A vertical VOLUME that fills — readable from any angle, including
// from behind. Always carries step or percentage semantics, NEVER a bare spinner.
export class Column extends Widget {
  constructor(theme, cue, label) {
    super(theme, cue, label);
    this.pct = 0;
    this.shell = new THREE.Mesh(
      new THREE.CylinderGeometry(0.012, 0.012, 0.11, 20, 1, true),
      volumetric(theme.panel, { core: 0.5, opacity: 0.5, rimStrength: 0.45 })
    );
    this.add(this.shell);
    this.fill = new THREE.Mesh(
      new THREE.CylinderGeometry(0.0105, 0.0105, 0.11, 20),
      volumetric(theme.accent, { core: 0.5, rimStrength: 0.6 })
    );
    this.add(this.fill);
    this.readout = null;
    this.setPct(0, label || 'STEP 1/4');
  }
  setPct(p, text) {
    this.pct = Math.max(0, Math.min(1, p));
    if (this.readout) this.remove(this.readout);
    this.readout = makeLabel(text, this.theme.text, { deg: LABEL_DEG, dist: REACH });
    this.readout.position.set(0, -0.078, 0);
    this.add(this.readout);
  }
  update() {
    this.fill.scale.y = Math.max(0.001, this.pct);
    this.fill.position.y = -0.055 + (0.11 * this.pct) / 2;
  }
}

// ----------------------------------------------------------------- EMBER ----
// The notification. A glowing mote at the viewport edge ON THE BEARING OF ITS
// CAUSE, decaying over ~3 s.
//
// A notification is not a card. It is a DIRECTION. Nothing ever appears in front
// of your face uninvited.
export class Ember extends THREE.Group {
  constructor(theme, text, bearing) {
    super();
    this.life = 1; this.bearing = bearing;
    const g = new THREE.Mesh(
      new THREE.SphereGeometry(0.03, 22, 16),
      volumetric(theme.accent, { additive: true, core: 0.55, rimStrength: 0.9 })
    );
    this.add(g); this.orb = g;
    this.tag = makeLabel(text, theme.text, { deg: 1.3, dist: 1.6, backing: theme.panel });
    this.tag.position.set(0, -0.11, 0);
    this.add(this.tag);
  }
  update(dt) {
    this.life -= dt / 3.2;
    const a = Math.max(0, this.life);
    setOpacity(this.orb.material, a);
    this.tag.material.opacity = a;
    this.orb.scale.setScalar(1 + (1 - a) * 0.7);
    return this.life > 0;
  }
}
