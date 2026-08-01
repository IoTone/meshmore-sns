// AiRspace UI — THE RACK. Instruments for editing the radio itself.
//
// The rest of the library is deliberately soft: pebbles, beads, haloes. This
// module is deliberately HARD, and the difference is the point.
//
// Everywhere else you are reading the mesh — a thing you cannot break by
// looking at it. Here you are editing the radio's own configuration, where four
// of the fields can leave the hardware silent in the field with no on-device
// way back. The controls should feel like they have consequences, and the
// 1980s rack is the honest vocabulary for that: a detented encoder resists you,
// a guarded switch has to be uncovered before it can be thrown, a lamp is lit
// or it is not. Nothing here is a row in a list with a chevron.
//
// THE ADDITIVE TRAP, and the one thing that makes this not a straight port of
// a real rack panel. On optical see-through glasses BLACK IS TRANSPARENT: the
// display adds light, it cannot subtract it. A 19-inch rack face is mostly dark
// anodised metal, which on an Aura renders as NOTHING — you would be left with
// LEDs and silkscreen floating in the room with no instrument under them.
//
// So the chassis is drawn as EDGES AND LIGHT, never as a filled face. Rails,
// bezels, screw bosses and unit seams are extruded and lit; the "metal" between
// them is implied by the frame around it, exactly as a wireframe implies a
// solid. On a panel-substrate theme the face is painted in as well and the
// result reads as a solid instrument; on additive it reads as the ghost of one.
// Both are correct — but only the second one survives daylight.

import * as THREE from 'three';
import { makeLabel } from './label.js';
import { REACH, LABEL_DEG, LABEL_SUB_DEG } from './constants.js';
import { volumetric, halo, shard, setColor, setOpacity } from './materials.js';

const col = (h) => new THREE.Color(h);
const RAD = Math.PI / 180;

// Past this many positions a lamp-per-value ring becomes a fog, not a scale.
const LED_MAX = 12;

// The rack ears eat this much on each side; nothing functional may sit under them.
const INSET = 0.036;

// SIZED BY VISUAL ANGLE, THEN PROPORTIONED.
//
// A real 19-inch face is 482.6 mm wide with 44.45 mm units — 10.9:1. Built at
// true scale and placed at REACH it subtends 49 degrees, which is wider than
// the comfortable field and forces the user to scan their head across their own
// instrument. So the WIDTH is chosen first, from the angle we are willing to
// spend, and the unit height falls out of the real ratio:
//
//   0.44 m at 0.62 m  ->  ~39 deg wide, 6U -> ~22 deg tall
//
// Six units, three functional rows, two units each. The 2U row is what buys the
// space an encoder needs: a knob with a caption below it and a readout above is
// three stacked elements, and cramming those into 1U is what produced the first
// render, where every label printed through its neighbour.
export const RACK_W = 0.44;
export const U = RACK_W / 10.9;
export const ROW_U = 2;

// ------------------------------------------------------------------ CHASSIS -
// The frame every instrument bolts into.
//
// Built from bars, not from a box with a texture. Twelve extrusions cost
// nothing and they are the only part of the instrument that is legible on an
// additive display, so they carry the whole silhouette.
export class Chassis extends THREE.Group {
  constructor(theme, units = 3, { label = '' } = {}) {
    super();
    const h = U * units;
    const additive = theme.substrate === 'additive';

    // The face. Painted on panel substrates, a whisper on additive — where the
    // rails below are doing the actual work of saying "there is an instrument
    // here".
    const face = shard(RACK_W, h, theme.panel, {
      depth: 0.014,
      opacity: additive ? 0.16 : 0.86,
    });
    face.position.z = -0.012;
    this.add(face);

    const edge = volumetric(theme.alt, { core: 0.62, rimStrength: 0.8, opacity: 0.95 });
    const bar = (w, hh, x, y) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, hh, 0.016), edge);
      m.position.set(x, y, 0);
      this.add(m);
      return m;
    };
    // Top and bottom rails, then the two rack EARS — the flanges with the
    // mounting holes. The ears are what make it rack-mounted rather than merely
    // rectangular, so they are drawn even though nothing bolts to them.
    bar(RACK_W, 0.004, 0, h / 2);
    bar(RACK_W, 0.004, 0, -h / 2);
    bar(0.004, h, -RACK_W / 2, 0);
    bar(0.004, h, RACK_W / 2, 0);
    [-1, 1].forEach((s) => {
      bar(0.030, h, s * (RACK_W / 2 - 0.015), 0).material =
        volumetric(theme.alt, { core: 0.4, opacity: additive ? 0.5 : 0.8, rimStrength: 0.6 });
      // Screw bosses: two per ear, at the standard 1U spacing.
      for (let i = 0; i < units / ROW_U; i++) {
        const y = h / 2 - (U * ROW_U) / 2 - i * U * ROW_U;
        const screw = new THREE.Mesh(
          new THREE.TorusGeometry(0.0055, 0.0018, 8, 18),
          volumetric(theme.text, { core: 0.5, opacity: 0.75, rimStrength: 0.5 })
        );
        screw.position.set(s * (RACK_W / 2 - 0.015), y, 0.008);
        this.add(screw);
      }
    });
    // Unit seams. A 3U instrument that is one unbroken face reads as a slab;
    // the seams are what say "three units of rack".
    for (let i = 1; i < units / ROW_U; i++) {
      const y = h / 2 - i * U * ROW_U;
      const s = new THREE.Mesh(
        new THREE.BoxGeometry(RACK_W - 0.036, 0.0015, 0.014),
        volumetric(theme.alt, { core: 0.3, opacity: 0.35, rimStrength: 0.4 })
      );
      s.position.set(0, y, 0.004);
      this.add(s);
    }

    if (label) {
      const l = makeLabel(label, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
      l.position.set(-RACK_W / 2 + 0.075, h / 2 + 0.020, 0.01);
      this.add(l);
    }
    this.units = units;
    this.h = h;
  }

  /** Centre-line of functional row [i] (ROW_U units tall), counting from the top. */
  row(i) { return this.h / 2 - (U * ROW_U) / 2 - i * U * ROW_U; }

  /** Fractional column: 0 is the left edge of the usable face, 1 the right. */
  col(f) { return -RACK_W / 2 + INSET + f * (RACK_W - INSET * 2); }
}

// --------------------------------------------------------------------- LAMP -
// One indicator. The whole vocabulary of this panel rests on it, so it is worth
// being strict: a lamp is LIT or it is NOT. No half states, no animation to say
// "sort of". An instrument whose lamps equivocate is an instrument you stop
// trusting, and this one is reporting whether your radio is on the air.
export class Lamp extends THREE.Group {
  constructor(theme, legend, color, { r = 0.0085, on = false } = {}) {
    super();
    this.theme = theme;
    this.color = color;
    this.dome = new THREE.Mesh(
      new THREE.SphereGeometry(r, 20, 14),
      volumetric(color, { core: 0.5, rimStrength: 0.9 })
    );
    this.dome.scale.z = 0.6;
    this.add(this.dome);
    // The bezel stays visible when the lamp is dark, so an unlit lamp still
    // reads as a lamp rather than as empty panel.
    const bez = new THREE.Mesh(
      new THREE.TorusGeometry(r * 1.5, r * 0.28, 8, 20),
      volumetric(theme.alt, { core: 0.4, opacity: 0.7, rimStrength: 0.5 })
    );
    this.add(bez);
    this.glow = halo(r * 2.4, r * 0.5, color, { opacity: 0.5 });
    this.add(this.glow);
    if (legend) {
      const l = makeLabel(legend, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
      l.position.set(0, -r * 3.4, 0);
      this.add(l);
    }
    this.set(on);
  }
  set(on) {
    this.on = on;
    setOpacity(this.dome.material, on ? 1 : 0.14);
    this.glow.visible = on;
  }
}

// ------------------------------------------------------------------ SEGMENT -
// A seven-segment readout, built as seven bars.
//
// Not a text label styled to look digital. A real segment display has DARK
// SEGMENTS as well as lit ones — the ghost of the 8 behind every digit — and
// that ghost is most of why it reads as an instrument. A canvas sprite could
// fake the lit segments but never the unlit ones.
const SEGMENTS = {
  //      a      b      c      d      e      f      g
  '0': 0b1111110, '1': 0b0110000, '2': 0b1101101, '3': 0b1111001,
  '4': 0b0110011, '5': 0b1011011, '6': 0b1011111, '7': 0b1110000,
  '8': 0b1111111, '9': 0b1111011, '-': 0b0000001, ' ': 0,
};

class Digit extends THREE.Group {
  constructor(color, dim, s = 0.011) {
    super();
    const t = s * 0.16;            // stroke
    const w = s * 0.9, h = s * 1.5;
    const geo = {
      h: new THREE.BoxGeometry(w - t, t, t),
      v: new THREE.BoxGeometry(t, h / 2 - t, t),
    };
    // a b c d e f g, in the classic order.
    const spec = [
      ['h', 0, h / 2], ['v', w / 2 - t / 2, h / 4], ['v', w / 2 - t / 2, -h / 4],
      ['h', 0, -h / 2], ['v', -w / 2 + t / 2, -h / 4], ['v', -w / 2 + t / 2, h / 4],
      ['h', 0, 0],
    ];
    this.segs = spec.map(([kind, x, y]) => {
      const m = new THREE.Mesh(geo[kind], volumetric(color, { core: 0.8, rimStrength: 0.5 }));
      m.position.set(x, y, 0);
      this.add(m);
      return m;
    });
    this.color = color; this.dim = dim;
    this.w = w;
  }
  set(ch) {
    const bits = SEGMENTS[ch] ?? 0;
    this.segs.forEach((m, i) => {
      const on = (bits >> (6 - i)) & 1;
      setColor(m.material, on ? this.color : this.dim);
      setOpacity(m.material, on ? 1 : 0.13);
    });
  }
}

export class Segment extends THREE.Group {
  constructor(theme, digits, { s = 0.011, unit = '', color = null } = {}) {
    super();
    const c = color ?? theme.accent;
    this.digits = [];
    const pitch = s * 1.14;
    for (let i = 0; i < digits; i++) {
      const d = new Digit(c, theme.panel, s);
      d.position.x = (i - (digits - 1) / 2) * pitch;
      this.add(d);
      this.digits.push(d);
    }
    this.width = digits * pitch;
    if (unit) {
      const l = makeLabel(unit, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
      l.position.set(this.width / 2 + 0.016, 0, 0);
      this.add(l);
    }
    // The decimal point is a separate lamp, as it is on real hardware.
    this.dp = new THREE.Mesh(
      new THREE.BoxGeometry(s * 0.16, s * 0.16, s * 0.16),
      volumetric(c, { core: 0.9 })
    );
    this.dp.visible = false;
    this.add(this.dp);
  }
  /** [text] is right-aligned and may contain one '.'. */
  set(text) {
    const dot = text.indexOf('.');
    const chars = text.replace('.', '');
    const n = this.digits.length;
    const padded = chars.slice(-n).padStart(n, ' ');
    this.digits.forEach((d, i) => d.set(padded[i]));
    if (dot > 0) {
      const idx = n - (chars.length - dot);
      this.dp.visible = idx >= 0 && idx < n;
      const pitch = this.width / n;
      this.dp.position.set((idx - (n - 1) / 2) * pitch + pitch * 0.48, -0.0082, 0);
    } else {
      this.dp.visible = false;
    }
  }
}

// ------------------------------------------------------------------ ENCODER -
// A detented rotary encoder.
//
// The knob TURNS and the detents are geometry you can count — twelve flutes
// around the body, a witness mark, and a ring of position LEDs. Turning it is
// the interaction; the value is read from the LEDs and the segment display it
// drives, never from a number printed on the knob, because a number on a knob
// has to face you and a knob that always faces you cannot look turned.
export class Encoder extends THREE.Group {
  constructor(theme, cue, label, { values, index = 0, r = 0.021, fmt = String }, onChange) {
    super();
    // A caller asking for a value the encoder does not have is a bug in the
    // caller, but crashing the panel over it helps nobody -- and this exact
    // thing happened: 910.525 MHz was not on the 125 kHz grid the frequency
    // encoder was built with, indexOf returned -1, and every readout downstream
    // tried to format `undefined`.
    const i0 = Math.max(0, Math.min(values.length - 1, index));
    Object.assign(this, { theme, cue, label, values, index: i0, r, fmt, onChange });
    this.draggable = true;
    this.hitRadius = r * 2.4;
    // The host scrubs draggables across `len`. A knob is only ~4 cm across, so
    // scrubbing over its own width would make a 200-position encoder move ten
    // steps per millimetre. The grab range is deliberately much wider than the
    // control: you reach for the knob, then your hand has room to turn it.
    this.len = 0.5;

    this.body = new THREE.Mesh(
      new THREE.CylinderGeometry(r, r * 0.92, r * 0.7, 24),
      volumetric(theme.panel, { core: 0.55, rimStrength: 0.9 })
    );
    this.body.rotation.x = Math.PI / 2;
    this.add(this.body);

    // Knurling: the flutes are what let you SEE that it turned.
    this.knurl = new THREE.Group();
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2;
      const f = new THREE.Mesh(
        new THREE.BoxGeometry(r * 0.11, r * 0.11, r * 0.72),
        volumetric(theme.alt, { core: 0.5, opacity: 0.85, rimStrength: 0.6 })
      );
      f.position.set(Math.cos(a) * r, Math.sin(a) * r, 0);
      this.knurl.add(f);
    }
    this.add(this.knurl);

    // Witness mark — the single line that says which way is up.
    this.mark = new THREE.Mesh(
      new THREE.BoxGeometry(r * 0.09, r * 0.8, r * 0.09),
      volumetric(theme.accent, { core: 0.9, rimStrength: 0.9 })
    );
    this.mark.position.set(0, r * 0.5, r * 0.38);
    this.knurl.add(this.mark);

    // Position LEDs around the body.
    //
    // ONE LAMP PER VALUE, UNTIL THAT STOPS BEING SENSIBLE. For SF7..SF12 a lamp
    // each is ideal: the range is countable at a glance and the position is
    // unambiguous. For a 26 MHz band on a 25 kHz grid it is 1041 lamps, which is
    // not an instrument, it is a fog. Past LED_MAX the ring switches to showing
    // POSITION IN RANGE instead — the same thing a real multi-turn encoder's
    // ring does, and the segment readout carries the exact value anyway.
    this.ledN = Math.min(values.length, LED_MAX);
    this.leds = Array.from({ length: this.ledN }, (_, i) => {
      const a = (-135 + (i / Math.max(1, this.ledN - 1)) * 270) * RAD;
      const led = new THREE.Mesh(
        new THREE.SphereGeometry(r * 0.13, 10, 8),
        volumetric(theme.accent, { core: 0.7, rimStrength: 0.8 })
      );
      led.position.set(Math.sin(a) * r * 1.55, Math.cos(a) * r * 1.55, 0);
      this.add(led);
      return led;
    });

    this.cap = makeLabel(label, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
    this.cap.position.set(0, -r * 2.5, 0);
    this.add(this.cap);
    this.readout = makeLabel(fmt(values[i0]), theme.text, { deg: LABEL_DEG, dist: REACH });
    this.readout.position.set(0, r * 2.4, 0);
    this.add(this.readout);

    this.apply();
  }
  // Encoders sweep 270 degrees, not 360: the dead zone at the bottom is what
  // makes "fully counter-clockwise" and "fully clockwise" distinguishable.
  angleOf(i) {
    const n = Math.max(1, this.values.length - 1);
    return (-135 + (i / n) * 270) * RAD;
  }
  set(i) {
    const next = Math.max(0, Math.min(this.values.length - 1, i));
    if (next === this.index) return;
    this.index = next;
    this.apply();
    this.cue?.fire(this.theme, 'DETENT');
    this.onChange?.(this.values[next], next);
  }
  value() { return this.values[this.index]; }
  apply() {
    this.knurl.rotation.z = -this.angleOf(this.index);
    const lit = Math.round((this.index / Math.max(1, this.values.length - 1)) * (this.ledN - 1));
    this.leds.forEach((l, i) => {
      const on = i === lit;
      setColor(l.material, on ? this.theme.accent : this.theme.panel);
      setOpacity(l.material, on ? 1 : 0.22);
    });
    this.readout.material.map?.dispose?.();
    const next = makeLabel(this.fmt(this.value()), this.theme.text, { deg: LABEL_DEG, dist: REACH });
    this.readout.material.map = next.material.map;
    this.readout.material.needsUpdate = true;
    this.readout.scale.copy(next.scale);
  }
  /** Horizontal scrub, as the host's drag handler supplies it. */
  scrub(u) { this.set(Math.round(u * (this.values.length - 1))); }
  setHot(v) { this.hot = v; setOpacity(this.body.material, v ? 1 : 0.9); }
  setNear() {}
  commit() { return false; }
}

// ----------------------------------------------------------------- BARGRAPH -
// An LED column. Used for TX power, where the top of the scale is a REGULATORY
// limit rather than a device one — so the segments past the cap are drawn in
// the alert colour and lit only if you insist on going there.
export class Bargraph extends THREE.Group {
  constructor(theme, n, { w = 0.010, h = 0.006, gap = 0.0035, redFrom = null } = {}) {
    super();
    this.theme = theme; this.n = n; this.redFrom = redFrom;
    this.cells = [];
    for (let i = 0; i < n; i++) {
      const m = new THREE.Mesh(
        new THREE.BoxGeometry(w, h, 0.006),
        volumetric(theme.accent, { core: 0.75, rimStrength: 0.6 })
      );
      m.position.y = (i - (n - 1) / 2) * (h + gap);
      this.add(m);
      this.cells.push(m);
    }
    this.set(0);
  }
  set(filled) {
    this.cells.forEach((m, i) => {
      const on = i < filled;
      const red = this.redFrom != null && i >= this.redFrom;
      setColor(m.material, red ? this.theme.alert : this.theme.accent);
      setOpacity(m.material, on ? 1 : 0.12);
    });
  }
}

// -------------------------------------------------------------------- GUARD -
// A hinged cover over a switch that must not be thrown by accident.
//
// This is the one interaction in the library with deliberate FRICTION. Every
// other control is designed to be as easy to operate as possible; these two are
// not, because throwing them broadcasts the wearer's position to a public
// channel or changes a parameter that can strand the radio. The cover is a
// physical statement that the control underneath is different in kind, and
// lifting it is an act you cannot perform by brushing past.
export class Guard extends THREE.Group {
  constructor(theme, cue, legend, { on = false, color = null } = {}, onChange) {
    super();
    Object.assign(this, { theme, cue, onChange });
    this.open = false;
    this.on = on;
    const c = color ?? theme.alert;
    this.hitRadius = 0.036;

    this.toggle = new THREE.Mesh(
      new THREE.BoxGeometry(0.012, 0.024, 0.010),
      volumetric(c, { core: 0.6, rimStrength: 0.9 })
    );
    this.add(this.toggle);
    this.base = new THREE.Mesh(
      new THREE.CylinderGeometry(0.010, 0.011, 0.006, 16),
      volumetric(theme.panel, { core: 0.5, rimStrength: 0.7 })
    );
    this.base.rotation.x = Math.PI / 2;
    this.add(this.base);

    // The cover, hinged at the top. Wireframe-ish bars so it does not hide the
    // switch entirely when closed — you can always SEE the state, you just
    // cannot reach it.
    this.cover = new THREE.Group();
    const barMat = volumetric(theme.warn, { core: 0.55, opacity: 0.9, rimStrength: 0.7 });
    [-0.012, 0, 0.012].forEach((x) => {
      const b = new THREE.Mesh(new THREE.BoxGeometry(0.0022, 0.040, 0.0022), barMat);
      b.position.set(x, -0.020, 0);
      this.cover.add(b);
    });
    const lip = new THREE.Mesh(new THREE.BoxGeometry(0.028, 0.0022, 0.0022), barMat);
    lip.position.set(0, -0.040, 0);
    this.cover.add(lip);
    this.cover.position.set(0, 0.020, 0.014);
    this.add(this.cover);

    this.lamp = new Lamp(theme, '', c, { r: 0.006, on });
    this.lamp.position.set(0.026, 0, 0);
    this.add(this.lamp);

    const l = makeLabel(legend, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
    l.position.set(0, -0.036, 0);
    this.add(l);
    this.apply();
  }
  /** First click lifts the cover; the second throws the switch. */
  commit() {
    if (!this.open) {
      this.open = true;
      this.cue?.fire(this.theme, 'DETENT');
    } else {
      this.on = !this.on;
      this.open = false;
      this.cue?.fire(this.theme, 'COMMIT');
      this.onChange?.(this.on);
    }
    this.apply();
    return true;
  }
  apply() {
    this.cover.rotation.x = this.open ? -1.35 : 0;
    this.toggle.position.y = this.on ? 0.006 : -0.006;
    this.toggle.rotation.x = this.on ? -0.35 : 0.35;
    this.lamp.set(this.on);
  }
  setHot(v) { this.hot = v; }
  setNear() {}
}

// ------------------------------------------------------------------- SLATE --
// A small backlit legend plate. Reads a value the user cannot edit here —
// public key, PSK fingerprint, firmware — so it is deliberately styled as a
// PRINTED plate rather than as a display: nothing about it should suggest it
// can be turned.
export class Slate extends THREE.Group {
  constructor(theme, caption, value, { w = 0.16 } = {}) {
    super();
    const plate = shard(w, 0.026, theme.panel, {
      depth: 0.006, opacity: theme.substrate === 'additive' ? 0.2 : 0.75,
    });
    this.add(plate);
    const c = makeLabel(caption, theme.alt, { deg: LABEL_SUB_DEG, dist: REACH });
    c.position.set(-w / 2 + 0.030, 0.020, 0.006);
    this.add(c);
    this.value = makeLabel(value, theme.text, { deg: LABEL_DEG, dist: REACH });
    this.value.position.set(0, 0, 0.006);
    this.add(this.value);
    this.theme = theme;
  }
}
