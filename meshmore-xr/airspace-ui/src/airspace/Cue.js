// AiRspace UI — L3, the triple-cue law.
//
// One call fires visual + audible + haptic together. Widgets never reach for
// the audio or haptic layer directly; they emit an event and the Cue sink
// guarantees the channels stay synchronised.
//
// L3 requires that NO CHANNEL IS LOAD-BEARING ALONE — not that all three fire
// on every event. An event carried by two synchronised channels satisfies it;
// an event carried by one does not.

import { Audio } from './audio.js';
import { Haptics } from './haptics.js';

export class Cue {
  constructor() {
    this.audio = new Audio();
    this.haptics = new Haptics();
    this.log = [];
    this.onVisual = null; // set by the renderer
  }

  // bearing: radians in world space, or null when the source has no position
  // estimate. A bearing-unknown event plays dead-centre and is NEVER given a
  // fake direction (audio spec §4.3).
  fire(theme, event, opts = {}) {
    const pan = opts.bearing == null ? 0 : Math.sin(opts.bearing - (opts.headYaw || 0));
    this.audio.fire(theme, event, { ...opts, pan });
    this.haptics.fire(event);
    if (this.onVisual) this.onVisual(event, opts);
    this.log.push(event);
    if (this.log.length > 24) this.log.shift();
  }
}
