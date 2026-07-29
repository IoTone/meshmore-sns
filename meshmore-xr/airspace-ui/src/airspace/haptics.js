// AiRspace UI — haptics, with the honest fallback.
//
// Optical see-through glasses in this class generally have NO haptic actuator.
// Tier H0 (nothing anywhere) is the likely default, not an edge case, so audio
// and visual must be fully sufficient on their own.
//
// Consequence: at the realistic best case (H1 — paired phone in a pocket,
// ~40–120 ms) haptics are TOO SLOW FOR HOVER. A delayed buzz reads as lag, not
// feedback. So haptics fire only on the events below.

export const HAPTIC_EVENTS = new Set([
  'COMMIT', 'DENY', 'SEAT', 'MSG_DIRECT', 'LINK_UP', 'LINK_DOWN', 'TIER_CHANGE', 'CRITICAL',
]);

// Maps to Android VibrationEffect.Composition primitives.
const PATTERN = {
  COMMIT:      [12],                 // PRIMITIVE_CLICK
  SEAT:        [22],                 // PRIMITIVE_THUD
  DENY:        [10, 60, 10],         // refuse — deliberately unpleasant
  MSG_DIRECT:  [18, 180, 18],        // summon — a "someone wants you" heartbeat
  LINK_UP:     [8, 30, 16],          // QUICK_RISE
  LINK_DOWN:   [16, 30, 8],          // QUICK_FALL
  TIER_CHANGE: [10, 40, 10, 40, 14],
  CRITICAL:    [30, 90, 30, 90, 30, 90, 30], // alarm — never themed, never scaled
};

export class Haptics {
  constructor() {
    this.tier = navigator.vibrate ? 'H1' : 'H0';
    this.scale = 1.0; // user-scalable 0–200%…
    // The actuator is gated behind a user gesture on every platform we target.
    // Firing before one is not just blocked, it logs an error every time — so
    // stay disarmed until the user has actually touched something.
    this.armed = false;
    const arm = () => { this.armed = true; };
    addEventListener('pointerdown', arm, { once: true });
    addEventListener('keydown', arm, { once: true });
  }

  fire(event) {
    if (!HAPTIC_EVENTS.has(event)) return;      // hover is audio + visual only
    if (this.tier === 'H0' || !this.armed) return; // fail safe, silently
    const p = PATTERN[event];
    if (!p) return;
    // …except alarm, which ignores the user scale. A safety signal is not a
    // preference.
    const s = event === 'CRITICAL' ? 1 : this.scale;
    try { navigator.vibrate(p.map((v, i) => (i % 2 === 0 ? Math.round(v * s) : v))); } catch { /* no-op */ }
  }
}
