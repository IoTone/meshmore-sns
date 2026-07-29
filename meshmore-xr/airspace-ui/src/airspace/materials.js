// AiRspace UI — volumetric materials.
//
// THE BUG THIS FIXES: a sphere drawn with MeshBasicMaterial renders as a FLAT
// COLOURED CIRCLE. There is no shading term, so every "3D" primitive in v1 was
// visually indistinguishable from a 2D disc. Foreshorten-proof, yes — but flat.
//
// Lights are the obvious answer and the wrong one here: most of our symbology is
// EMISSIVE (an additive see-through display adds light, it does not reflect it),
// and a lambert-only emissive sphere still flattens at the silhouette. What
// reads as volume on a glowing object is the FRESNEL RIM — the edge brightening
// you see on anything round and self-luminous.
//
// So: a fixed-direction lambert term for body shading + a view-dependent fresnel
// rim for silhouette. Works identically on panel and additive substrates, needs
// no scene lights, and costs one cheap shader.

import * as THREE from 'three';

const VERT = /* glsl */ `
  varying vec3 vN;
  varying vec3 vV;
  void main() {
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    vN = normalize(normalMatrix * normal);
    vV = normalize(-mv.xyz);
    gl_Position = projectionMatrix * mv;
  }
`;

const FRAG = /* glsl */ `
  uniform vec3  uColor;
  uniform vec3  uRim;
  uniform float uRimPower;
  uniform float uCore;
  uniform float uOpacity;
  varying vec3 vN;
  varying vec3 vV;
  void main() {
    vec3 n = normalize(vN);
    vec3 v = normalize(vV);
    // Body: a fixed key direction so the volume shades consistently no matter
    // where the user's head is — symbology must not flicker as you turn.
    float lam = clamp(dot(n, normalize(vec3(0.35, 0.75, 0.55))), 0.0, 1.0);
    // Silhouette: fresnel rim. This is what makes an emissive sphere read round.
    float f = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), uRimPower);
    vec3 c = uColor * (uCore + (1.0 - uCore) * lam) + uRim * f;
    gl_FragColor = vec4(c, uOpacity);
  }
`;

export function volumetric(color, {
  rim = 0xffffff, rimPower = 2.4, core = 0.42, opacity = 1,
  additive = false, rimStrength = 0.55,
} = {}) {
  const r = new THREE.Color(rim).multiplyScalar(rimStrength);
  const m = new THREE.ShaderMaterial({
    uniforms: {
      uColor: { value: new THREE.Color(color) },
      uRim: { value: r },
      uRimPower: { value: rimPower },
      uCore: { value: core },
      uOpacity: { value: opacity },
    },
    vertexShader: VERT,
    fragmentShader: FRAG,
    transparent: true,
  });
  if (additive) { m.blending = THREE.AdditiveBlending; m.depthWrite = false; }
  return m;
}

export function setColor(mat, color) { mat.uniforms?.uColor.value.set(color); }
export function setOpacity(mat, o) { if (mat.uniforms) mat.uniforms.uOpacity.value = o; }

// ---------------------------------------------------------------------------
// The volumetric primitive set. Every one of these has real depth: there is no
// flat quad, no stroked circle, and no 1-px line anywhere in the symbology.

// HALO — a real TORUS, not a RingGeometry annulus. You can see its roundness,
// and it never degenerates into a stroked circle at a grazing angle.
export function halo(radius, tube, color, opts = {}) {
  return new THREE.Mesh(new THREE.TorusGeometry(radius, tube, 10, 96), volumetric(color, opts));
}

// PULSE — an expanding torus whose TUBE THINS as the ring grows, so it reads as
// a shockwave losing energy rather than a donut inflating.
export function pulseRing(radius, tube, color, opts = {}) {
  return new THREE.Mesh(new THREE.TorusGeometry(radius, tube, 8, 48), volumetric(color, { additive: true, core: 0.8, ...opts }));
}

// SPUR — three concentric tubes (core / glow / halo), additive. Never a line:
// WebGL line width is ignored on most platforms, and anything under ~1 cm
// radius is invisible in bright passthrough.
export function spur(from, to, color, { core = 0.006, glow = 0.018, halo: h = 0.045 } = {}) {
  const g = new THREE.Group();
  const dir = to.clone().sub(from);
  const len = dir.length();
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.clone().normalize());
  [[core, 0.95, 0.55], [glow, 0.30, 0.85], [h, 0.10, 1.0]].forEach(([r, op, coreMix]) => {
    const m = new THREE.Mesh(
      new THREE.CylinderGeometry(r, r, len, 12),
      volumetric(color, { additive: true, opacity: op, core: coreMix, rimStrength: 0.25 })
    );
    m.quaternion.copy(q);
    m.position.copy(from).lerp(to, 0.5);
    g.add(m);
  });
  return g;
}

// CARET — a CONE pointing along a bearing. A flat triangle disappears edge-on;
// a cone is legible from every angle and reads as "pointing" in real 3D.
export function caret(size, color, opts = {}) {
  const m = new THREE.Mesh(new THREE.ConeGeometry(size * 0.5, size * 1.5, 14), volumetric(color, opts));
  m.geometry.rotateX(Math.PI / 2); // point down -Z
  return m;
}

// BAR — extruded box segments. Discrete, so it is readable at a glance without
// a scale, and it has thickness so it reads at an angle.
export function segBar(count, filled, color, dim, { w = 0.008, h = 0.026, d = 0.008, gap = 0.004 } = {}) {
  const g = new THREE.Group();
  for (let i = 0; i < count; i++) {
    const on = i < filled;
    const m = new THREE.Mesh(
      new THREE.BoxGeometry(w, h * (on ? 1 : 0.62), d),
      volumetric(on ? color : dim, { core: on ? 0.55 : 0.30, rimStrength: on ? 0.6 : 0.2 })
    );
    m.position.x = (i - (count - 1) / 2) * (w + gap);
    g.add(m);
  }
  return g;
}

// SHARD — the volumetric replacement for a flat panel. A bevelled box with real
// thickness and a lit edge; text insets into its face.
export function shard(w, h, color, { depth = 0.012, opacity = 0.9 } = {}) {
  const m = new THREE.Mesh(
    new THREE.BoxGeometry(w, h, depth),
    volumetric(color, { core: 0.5, opacity, rimStrength: 0.35, rimPower: 3.0 })
  );
  return m;
}
