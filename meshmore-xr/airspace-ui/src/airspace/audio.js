// AiRspace UI — procedural audio.
//
// Zero binary assets: oscillators + noise + envelopes only. No files, no
// localization, no licensing — and it unit-tests as pure math (assert
// non-silent, correct duration, expected dominant frequency).
//
// On Android this maps to a SoundPool routed as USAGE_MEDIA. Assistant and
// sonification usages get ducked or misrouted on headsets (field-confirmed).

const SEMI = (n) => Math.pow(2, n / 12);

export class Audio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.enabled = true;
    this.voices = 0;
    this.packetGate = { count: 0, window: 0, floor: 1 };
  }

  // Browsers block AudioContext before a user gesture — init lazily.
  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.32;
    this.master.connect(this.ctx.destination);
  }

  // pan: -1 (left) … +1 (right). Spatialized notifications use the sender's
  // true bearing; a node with no position estimate plays dead-centre and MUST
  // NOT be given a fake bearing (see audio spec §4.3).
  tone(theme, { freq, dur = 0.09, type, gain = 0.5, pan = 0, sweep = 0, delay = 0 }) {
    if (!this.enabled) return;
    this.init();
    if (!this.ctx || this.voices > 6) return; // voice ceiling

    const t = this.ctx.currentTime + delay;
    const osc = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    const p = this.ctx.createStereoPanner();

    osc.type = type || theme.wave;
    osc.frequency.setValueAtTime(freq, t);
    if (sweep) osc.frequency.exponentialRampToValueAtTime(Math.max(40, freq * sweep), t + dur);

    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0002, gain), t + Math.min(0.012, dur * 0.2));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);

    p.pan.value = Math.max(-1, Math.min(1, pan));
    osc.connect(g); g.connect(p); p.connect(this.master);

    this.voices++;
    osc.onended = () => { this.voices--; };
    osc.start(t);
    osc.stop(t + dur + 0.02);
  }

  noise(theme, { dur = 0.12, gain = 0.25, pan = 0, band = 1800 }) {
    if (!this.enabled) return;
    this.init();
    if (!this.ctx || this.voices > 6) return;

    const t = this.ctx.currentTime;
    const n = Math.floor(this.ctx.sampleRate * dur);
    const buf = this.ctx.createBuffer(1, n, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);

    const src = this.ctx.createBufferSource(); src.buffer = buf;
    const f = this.ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = band; f.Q.value = 1.4;
    const g = this.ctx.createGain(); g.gain.value = gain;
    const p = this.ctx.createStereoPanner(); p.pan.value = pan;

    src.connect(f); f.connect(g); g.connect(p); p.connect(this.master);
    this.voices++;
    src.onended = () => { this.voices--; };
    src.start(t);
  }

  // Quantize to the theme's scale — VECTORLINE's whole thesis, harmless elsewhere.
  scaled(theme, degree) {
    const s = theme.scale;
    const oct = Math.floor(degree / s.length);
    return theme.root * SEMI(s[((degree % s.length) + s.length) % s.length] + oct * 12);
  }

  // Density control (audio spec §2.1): the mesh should FEEL busy without
  // becoming fatiguing. Rate ceiling + ambient decay.
  allowPacket(now) {
    const g = this.packetGate;
    if (now - g.window > 1) { g.window = now; g.count = 0; }
    if (g.count >= 4) return 0;
    g.count++;
    g.floor = Math.max(0.12, g.floor - 0.004);
    return g.floor;
  }
  relaxPackets() { this.packetGate.floor = Math.min(1, this.packetGate.floor + 0.01); }

  // ---- the event taxonomy (audio spec §2) --------------------------------
  fire(theme, event, opts = {}) {
    if (theme.silent && theme.silent.includes(event)) return; // silence is a choice
    const pan = opts.pan || 0;
    switch (event) {
      case 'PROXIMATE': return this.tone(theme, { freq: this.scaled(theme, 0), dur: 0.04, gain: 0.10, pan });
      case 'HOVER':     return this.tone(theme, { freq: this.scaled(theme, 1), dur: 0.045, gain: 0.16, pan });
      case 'COMMIT':
        this.tone(theme, { freq: this.scaled(theme, 2), dur: 0.07, gain: 0.30, pan });
        return this.tone(theme, { freq: this.scaled(theme, 4), dur: 0.09, gain: 0.24, pan, delay: 0.045 });
      case 'DENY':
        this.tone(theme, { freq: theme.root * 0.5, dur: 0.14, gain: 0.28, type: 'square', pan, sweep: 0.7 });
        return this.noise(theme, { dur: 0.09, gain: 0.12, band: 700, pan });
      case 'DETENT':    return this.tone(theme, { freq: this.scaled(theme, opts.step || 0), dur: 0.028, gain: 0.20, pan });
      case 'SEAT':      return this.tone(theme, { freq: this.scaled(theme, opts.on ? 3 : 0), dur: 0.10, gain: 0.30, pan, sweep: opts.on ? 1.18 : 0.82 });
      case 'NODE_FOUND':
        // The signature sound. HALO FIELD's sonar ping; an arpeggio in VECTORLINE.
        if (theme.key === 'vector') {
          for (let i = 0; i < 4; i++) this.tone(theme, { freq: this.scaled(theme, i), dur: 0.1, gain: 0.2, pan, delay: i * 0.06 });
          return;
        }
        return this.tone(theme, { freq: theme.root, dur: 0.25, gain: 0.26, pan, sweep: 0.86 });
      case 'PACKET': {
        const g = this.allowPacket(opts.now || 0);
        if (!g) return;
        return this.tone(theme, { freq: this.scaled(theme, opts.step || 0) * 2, dur: 0.03, gain: 0.05 * g, pan });
      }
      case 'MSG_CHANNEL':
        this.tone(theme, { freq: this.scaled(theme, 0), dur: 0.12, gain: 0.26, pan });
        return this.tone(theme, { freq: this.scaled(theme, 2), dur: 0.16, gain: 0.22, pan, delay: 0.10 });
      case 'MSG_DIRECT':
        // Deliberately the same interval, INVERTED and doubled — instantly
        // distinguishable from a channel message, obviously related to it.
        this.tone(theme, { freq: this.scaled(theme, 4), dur: 0.13, gain: 0.30, pan });
        this.tone(theme, { freq: this.scaled(theme, 2), dur: 0.13, gain: 0.28, pan, delay: 0.11 });
        return this.tone(theme, { freq: this.scaled(theme, 4), dur: 0.20, gain: 0.24, pan, delay: 0.22 });
      case 'LINK_UP':
        return [0, 2, 4].forEach((d, i) => this.tone(theme, { freq: this.scaled(theme, d), dur: 0.14, gain: 0.26, delay: i * 0.08 }));
      case 'LINK_DOWN':
        return [4, 2, 0].forEach((d, i) => this.tone(theme, { freq: this.scaled(theme, d), dur: 0.16, gain: 0.24, delay: i * 0.09 }));
      case 'TIER_CHANGE':
        return [0, 3, 5, 7].forEach((d, i) => this.tone(theme, { freq: this.scaled(theme, d), dur: 0.18, gain: 0.20, delay: i * 0.07 }));
      case 'CRITICAL':
        // Never themed away. Never silent. Ducks everything else.
        for (let i = 0; i < 4; i++) {
          this.tone(theme, { freq: 880, dur: 0.12, gain: 0.5, type: 'square', delay: i * 0.18 });
          this.tone(theme, { freq: 587, dur: 0.12, gain: 0.4, type: 'square', delay: i * 0.18 + 0.09 });
        }
        return;
      default: return;
    }
  }
}
