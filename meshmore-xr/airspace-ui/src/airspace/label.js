// AiRspace UI — text.
//
// Sized in VISUAL ANGLE, not pixels (L7), and the floor is LOCALE-DEPENDENT:
// Latin >= 1.2 deg, kana >= 1.5, kanji >= 1.8. See i18n.js for why.
//
// Text itself is a flat plane — that is unavoidable and correct; a bevelled
// glyph is a novelty, not a legibility win. What must not be flat is the thing
// the text sits ON. Use makeShardLabel() for anything that needs to read as an
// object rather than a decal.

import * as THREE from 'three';
import { angularSize } from './Billboard.js';
import { FONT_STACK, minDegFor } from './i18n.js';
import { shard } from './materials.js';

const PX = 44;
const font = (px = PX) => `600 ${px}px ${FONT_STACK}`;

export function makeLabel(text, colorHex, { deg = 1.4, dist = 1.4, backing = null, pad = 18 } = {}) {
  // The requested size is a floor request, not a grant: a kanji string is
  // promoted to 1.8 deg even if the caller asked for 1.2.
  const effDeg = minDegFor(text, deg);

  const cv = document.createElement('canvas');
  const ctx = cv.getContext('2d');
  ctx.font = font();
  const m = ctx.measureText(text);
  const w = Math.ceil(m.width) + pad * 2;
  const h = PX + pad * 2;
  cv.width = Math.max(4, w); cv.height = h;

  const c2 = cv.getContext('2d');
  if (backing !== null) {
    c2.fillStyle = `#${backing.toString(16).padStart(6, '0')}`;
    c2.globalAlpha = 0.92;
    c2.fillRect(0, 0, w, h);
    c2.globalAlpha = 1;
  }
  c2.font = font();
  c2.textBaseline = 'middle';
  c2.textAlign = 'center';
  c2.fillStyle = `#${colorHex.toString(16).padStart(6, '0')}`;
  c2.fillText(text, w / 2, h / 2 + 2);

  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.minFilter = THREE.LinearFilter;
  tex.anisotropy = 4;

  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
  const sp = new THREE.Sprite(mat);
  const hWorld = angularSize(effDeg, dist);
  sp.scale.set(hWorld * (w / h), hWorld, 1);
  // Callers that emphasise a label MUST scale relative to this, never
  // setScalar() — that discards the aspect ratio and the angular sizing, and a
  // long string balloons to a metre wide. Use scaleLabel().
  sp.userData.isLabel = true;
  sp.userData.baseScale = { x: sp.scale.x, y: sp.scale.y };
  sp.userData.aspect = w / h;
  sp.userData.text = text;
  return sp;
}

export function scaleLabel(sprite, k) {
  const b = sprite.userData.baseScale;
  if (!b) return;
  sprite.scale.set(b.x * k, b.y * k, 1);
}

// A label mounted on a SHARD — a bevelled box with real thickness and a lit
// edge. This is the volumetric replacement for "text floating on a flat panel":
// the text plane insets into the shard's front face, so the whole assembly
// reads as an object you could pick up.
export function makeShardLabel(text, colorHex, shardColor, { deg = 1.4, dist = 1.4, padX = 1.35, padY = 2.1 } = {}) {
  const g = new THREE.Group();
  const sp = makeLabel(text, colorHex, { deg, dist, backing: null });
  const w = sp.scale.x * padX;
  const h = sp.scale.y * padY;
  const back = shard(w, h, shardColor, { depth: Math.max(0.006, h * 0.42), opacity: 0.92 });
  g.add(back);
  sp.position.z = Math.max(0.006, h * 0.42) / 2 + 0.0015; // inset into the face
  g.add(sp);
  g.userData.label = sp;
  g.userData.shard = back;
  return g;
}
