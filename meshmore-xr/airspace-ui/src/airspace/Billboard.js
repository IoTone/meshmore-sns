// AiRspace UI — L1, the billboard law.
//
// Position from the anchor, ORIENTATION FROM THE HEAD. Always.
//
// Never compose a widget's pose with the hand's rotation: when the user looks
// at the back of their hand the widget goes edge-on and foreshortens into an
// unreadable sliver. Field-confirmed twice ("icon huge", then "1/5 of a red
// semicircle" — both were foreshortening).
//
// On SceneCore this is `head.compose(offset)` evaluated in Space.REAL_WORLD —
// never Space.ACTIVITY, which carries a movable panel's ~1.75x parent scale and
// corrupts any world-derived pose.

import * as THREE from 'three';

const _v = new THREE.Vector3();

export function billboard(obj, camera) {
  obj.quaternion.copy(camera.quaternion);
}

// Position on the hand, but oriented to the head, offset ~6 cm ALONG THE
// HAND->HEAD VECTOR (not along a local axis — a fixed local offset swings the
// widget off the hand as the wrist turns, and is corrupted by parent scale).
export function handAnchored(obj, handPos, headPos, camera, offset = 0.06) {
  _v.copy(headPos).sub(handPos).normalize().multiplyScalar(offset);
  obj.position.copy(handPos).add(_v);
  billboard(obj, camera);
}

// L7 — the angular floor. Returns the world size needed to subtend `deg` of
// visual angle at `dist`. Text >= 1.2 deg, any target >= 0.6 deg, anything
// reached-for >= 2 deg. These are floors, not targets.
export function angularSize(deg, dist) {
  return 2 * dist * Math.tan((deg * Math.PI) / 360);
}
