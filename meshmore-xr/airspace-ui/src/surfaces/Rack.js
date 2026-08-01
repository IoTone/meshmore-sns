// THE RADIO RACK — editing the radio, spatially.
//
// The CONSOLE (Console.js) configures the APP. This configures the RADIO, and
// the difference is not cosmetic: nothing on the console can stop the hardware
// working, and four of the fields here can leave it deaf in the field with no
// on-device way back. That asymmetry is the whole design.
//
// Three units, each a different class of risk, and you can tell which is which
// before reading a word:
//
//   ROW 1  IDENTITY   name, key, what we disclose           reversible
//   ROW 2  AIR        the four LoRa params                  STRANDING
//   ROW 3  COMMIT     live vs pending, commit, revert       the gate
//   ROW 4  CHANNELS   slots, PSK fingerprints               key material
//
// COMMIT IS ITS OWN ROW, and that is not a layout convenience. The first
// version hung the commit apparatus off the end of the channels row, where it
// read as one more button among four and its captions printed through their
// neighbours — a six-character label at this type size is ~0.10 m wide and the
// row had 0.037 m per control. Giving the gate its own unit is what makes the
// staged model legible as a MECHANISM rather than as a stray button.
//
// THE COMMIT MODEL, which is the thing worth reviewing.
//
// Frequency, bandwidth, spreading factor and coding rate are ONE command and
// ONE working configuration. Committing them a control at a time walks the
// radio through combinations that match no mesh at all — you would lose contact
// somewhere in the middle of your own edit. So the AIR row is STAGED: turning
// an encoder changes the PENDING value, the panel shows LIVE and PENDING side
// by side, and nothing reaches the radio until COMMIT is thrown.
//
// And once it is thrown, the app cannot tell you whether it worked. A radio on
// the wrong parameters is still connected over BLE and still perfectly healthy
// — it simply hears nothing, which is indistinguishable from a quiet mesh. So
// the panel keeps the previous set and offers REVERT for as long as the session
// lasts. That is the only honest answer available: not verification, which is
// impossible, but a way back.

import * as THREE from 'three';
import { makeLabel } from '../airspace/label.js';
import { REACH, LABEL_DEG, LABEL_SUB_DEG } from '../airspace/constants.js';
import { volumetric, shard } from '../airspace/materials.js';
import { Pebble } from '../airspace/widgets.js';
import { Chassis, Encoder, Segment, Bargraph, Lamp, Guard, Slate, U, ROW_U, RACK_W } from '../airspace/rack.js';

const RAD = Math.PI / 180;

// Named presets come FIRST, before any raw number. Nobody thinks "SF7" — they
// think "the mesh my region is on", and offering the numbers first is how you
// get someone typing a spreading factor they read on a forum.
export const PRESETS = [
  { name: 'US 915 FAST',   f: 910.525, bw: 62.5,  sf: 7,  cr: 5 },
  { name: 'US 915 LONG',   f: 910.525, bw: 62.5,  sf: 10, cr: 5 },
  { name: 'EU 868',        f: 869.525, bw: 250,   sf: 11, cr: 5 },
  { name: 'ANZ 915',       f: 915.800, bw: 250,   sf: 11, cr: 5 },
  { name: 'CUSTOM',        f: null,    bw: null,  sf: null, cr: null },
];

// The US band on a 25 kHz grid. NOT 125 kHz -- the radio in the room runs
// 910.525, which is not on a 125 kHz grid, and an encoder that cannot express
// the value the hardware is already set to is worse than no encoder at all.
const FREQS = [];
for (let i = 0; i <= 1040; i++) FREQS.push(Math.round((902.0 + i * 0.025) * 1000) / 1000);
const BWS = [7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125, 250, 500];
const SFS = [7, 8, 9, 10, 11, 12];
const CRS = [5, 6, 7, 8];

export class Rack extends THREE.Group {
  constructor(theme, cue, opts = {}) {
    super();
    this.theme = theme; this.cue = cue;
    this.widgets = [];
    this.onLog = opts.onLog || (() => {});

    // LIVE is what the radio is actually running. PENDING is what the encoders
    // are showing. They are separate objects on purpose — the whole staged
    // model falls apart the moment one is a view of the other.
    this.live = { f: 910.525, bw: 62.5, sf: 7, cr: 5, tx: 22, maxTx: 22 };
    this.pending = { ...this.live };
    this.previous = null;
    this.build();
  }

  add3(o, x, y, z = 0.006) { o.position.set(x, y, z); this.root.add(o); return o; }
  reg(w) { this.widgets.push(w); return w; }

  build() {
    const th = this.theme;
    this.root = new THREE.Group();
    // Tilted back like a real console: a vertical face at reach height forces
    // the head down AND the eyes up. 14 degrees is the angle a rack in a desk
    // sits at, and it is not a coincidence that it is comfortable.
    this.root.rotation.x = 14 * RAD;
    this.root.position.set(0, 0, -REACH);
    this.add(this.root);

    const ch = new Chassis(th, 8, { label: 'RADIO — MESHCORE COMPANION' });
    this.root.add(ch);
    this.chassis = ch;

    this.buildIdentity(ch.row(0));
    this.buildAir(ch.row(1));
    this.buildCommit(ch.row(2));
    this.buildChannels(ch.row(3));
  }

  // ---------------------------------------------------------- 1U IDENTITY ---
  buildIdentity(y) {
    const th = this.theme;
    const c = (f) => this.chassis.col(f);

    this.posLamp = this.add3(new Lamp(th, 'FIX', th.alt, { on: true }), c(0.055), y + 0.010);
    this.add3(new Slate(th, 'NODE', 'B727FE05', { w: 0.115 }), c(0.20), y + 0.010);
    this.add3(new Slate(th, 'KEY', 'b727fe05 4a42…', { w: 0.135 }), c(0.50), y + 0.010);

    // The two disclosure switches. Guarded, and guarded SEPARATELY, because
    // they are genuinely different decisions: the first says "use the headset's
    // fix to draw the horizon", which never leaves the glasses; the second says
    // "put that fix in every advert", which broadcasts where the wearer is,
    // unencrypted, to anyone in range. Wiring one to the other would be the
    // single most consequential shortcut available in this panel.
    this.reg(this.add3(
      new Guard(th, this.cue, 'GPS SRC', { on: true, color: th.warn },
        (v) => this.onLog(`headset GPS ${v ? 'ON' : 'OFF'} — local only`)),
      c(0.80), y + 0.010
    ));
    this.reg(this.add3(
      new Guard(th, this.cue, 'BCAST POS', { on: true, color: th.alert },
        (v) => this.onLog(`position in adverts: ${v ? 'SHARED' : 'withheld'}`)),
      c(0.945), y + 0.010
    ));
  }

  // -------------------------------------------------------------- ROW 2 AIR -
  buildAir(y) {
    const th = this.theme;
    const c = (f) => this.chassis.col(f);

    // Preset first, raw parameters after. Turning this writes all four pending
    // values at once, which is also the only way most people should ever touch
    // them.
    this.preset = this.reg(this.add3(
      new Encoder(th, this.cue, 'PRESET', {
        values: PRESETS, index: 0, r: 0.0135, fmt: (p) => p.name,
      }, (p) => this.applyPreset(p)),
      c(0.09), y
    ));

    const enc = (label, values, key, f, fmt) => this.reg(this.add3(
      new Encoder(th, this.cue, label, {
        values, index: values.indexOf(this.live[key]), r: 0.0125, fmt,
      }, (v) => { this.pending[key] = v; this.preset.set(PRESETS.length - 1); this.refresh(); }),
      c(f), y
    ));
    enc('FREQ', FREQS, 'f', 0.29, (v) => v.toFixed(3));
    enc('BW', BWS, 'bw', 0.46, (v) => `${v}`);
    enc('SF', SFS, 'sf', 0.63, (v) => `SF${v}`);
    enc('CR', CRS, 'cr', 0.80, (v) => `4/${v}`);

    // TX power. The bargraph's red zone is a REGULATORY ceiling, not a device
    // one — the radio will happily accept a number the wearer may not lawfully
    // transmit at, so the panel is where that gets said.
    this.txBar = this.add3(new Bargraph(th, 12, { redFrom: 10, h: 0.0026, gap: 0.0016 }), c(0.925), y - 0.002);
    this.txEnc = this.reg(this.add3(
      new Encoder(th, this.cue, 'TX dBm', {
        values: Array.from({ length: 12 }, (_, i) => i * 2), index: 11, r: 0.0125,
        fmt: (v) => `${v}`,
      }, (v) => { this.pending.tx = v; this.refresh(); }),
      c(0.98), y
    ));
  }

  // ----------------------------------------------------------- ROW 3 COMMIT -
  buildCommit(y) {
    const th = this.theme;
    const c = (f) => this.chassis.col(f);

    // LIVE above, PENDING below, always both. A single readout that silently
    // switches meaning between "what the radio is doing" and "what it would do"
    // is how you commit something you did not mean to.
    this.add3(makeLabel('LIVE', th.alt, { deg: LABEL_SUB_DEG, dist: REACH }), c(0.055), y + 0.014);
    this.add3(makeLabel('PEND', th.warn, { deg: LABEL_SUB_DEG, dist: REACH }), c(0.055), y - 0.014);
    this.liveSeg = this.add3(new Segment(th, 7, { s: 0.0075, unit: 'MHz', color: th.alt }),
      c(0.245), y + 0.014);
    this.pendSeg = this.add3(new Segment(th, 7, { s: 0.0075, unit: 'MHz', color: th.warn }),
      c(0.245), y - 0.014);

    this.dirty = this.add3(new Lamp(th, 'PENDING', th.warn, { on: false }), c(0.50), y + 0.012);

    // COMMIT and REVERT. REVERT is not a courtesy: it is the only recovery path
    // that exists once a bad parameter set has made the radio deaf, because at
    // that point the mesh cannot tell you anything.
    this.commitBtn = this.reg(this.add3(
      new Pebble(th, this.cue, 'COMMIT', () => this.commitAir(), { r: 0.016 }),
      c(0.73), y + 0.014
    ));
    this.revertBtn = this.reg(this.add3(
      new Pebble(th, this.cue, 'REVERT', () => this.revertAir(), { r: 0.013 }),
      c(0.95), y + 0.014
    ));
  }

  // --------------------------------------------------------- ROW 4 CHANNELS -
  buildChannels(y) {
    const th = this.theme;
    const c = (f) => this.chassis.col(f);

    // A PSK is never displayed, only fingerprinted. It decrypts every message
    // on the channel, so a panel that prints it is a panel that cannot be
    // photographed, screen-shared, or worn in public.
    this.add3(new Lamp(th, 'PUBLIC', th.alt, { on: true }), c(0.055), y + 0.010);
    this.add3(new Slate(th, 'CH0', 'Public 8b3387e9…', { w: 0.145 }), c(0.30), y + 0.008);
    this.add3(new Slate(th, 'CH1', '— empty —', { w: 0.105 }), c(0.62), y + 0.008);

    this.reg(this.add3(
      new Pebble(th, this.cue, 'IMPORT', () => this.onLog('channel import — QR scan'), { r: 0.013 }),
      c(0.90), y + 0.014
    ));
  }

  applyPreset(p) {
    if (!p || p.f == null) return;
    Object.assign(this.pending, { f: p.f, bw: p.bw, sf: p.sf, cr: p.cr });
    this.refresh();
    this.onLog(`preset ${p.name} staged`);
  }

  changed() {
    return ['f', 'bw', 'sf', 'cr', 'tx'].some((k) => this.pending[k] !== this.live[k]);
  }

  commitAir() {
    if (!this.changed()) { this.onLog('nothing staged'); return; }
    this.previous = { ...this.live };
    this.live = { ...this.pending };
    this.onLog(`COMMIT ${this.live.f.toFixed(3)}MHz BW${this.live.bw} SF${this.live.sf} 4/${this.live.cr} ${this.live.tx}dBm`);
    this.onLog('previous set retained — REVERT available this session');
    this.refresh();
  }

  revertAir() {
    if (!this.previous) { this.onLog('no previous set'); return; }
    this.live = { ...this.previous };
    this.pending = { ...this.previous };
    this.previous = null;
    this.onLog('REVERTED to previous parameter set');
    this.refresh();
  }

  refresh() {
    this.liveSeg.set(this.live.f.toFixed(3));
    this.pendSeg.set(this.pending.f.toFixed(3));
    this.txBar.set(Math.round(this.pending.tx / 2));
    this.dirty.set(this.changed());
  }

  update(dt, camera) {
    if (!this._init) { this.refresh(); this._init = true; }
    // The PENDING lamp breathes while something is staged. The one piece of
    // motion on the panel, and it is doing a job: an instrument with unsaved
    // state that looks identical to one without is how you walk away mid-edit.
    if (this.dirty.on) {
      this._t = (this._t || 0) + dt;
      this.dirty.glow.scale.setScalar(1 + Math.sin(this._t * 4) * 0.18);
    }
    this.widgets.forEach((w) => w.update?.(dt, camera));
  }
}
