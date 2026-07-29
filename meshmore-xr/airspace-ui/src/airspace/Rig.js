// AiRspace UI — the five zones, as the library's only layout primitive.
//
// There is no Box, no Column, no Row. THERE IS NO 2D LAYOUT IN AIRSPACE.
//
// L5 (reach vs. read) is enforced by the type system rather than by review:
// Reach does not accept content, Read does not accept controls. Mixing them is
// the single most common way spatial UI becomes tiring.

import * as THREE from 'three';

export class Rig {
  constructor(scene) {
    this.scene = scene;

    // Body-locked, YAW ONLY. The always-on mesh; the resting state of the app.
    this.horizon = new THREE.Group();
    // Reach space, 0.35–0.7 m: controls only.
    this.reach = new THREE.Group();
    // Read space, 1.2–2.5 m: content only.
    this.read = new THREE.Group();
    // Head-locked at the outer viewport rim: transient status only, never
    // load-bearing, auto-dismissed <= 3 s after a terminal state.
    this.edge = new THREE.Group();
    // World-locked to the floor plane. Never follows the user.
    this.ground = new THREE.Group();

    scene.add(this.horizon, this.reach, this.read, this.edge, this.ground);
  }

  addControl(obj) {
    if (obj.userData?.isContent) throw new Error('AiRspace L5: content cannot live in Reach space');
    this.reach.add(obj);
    return obj;
  }

  addContent(obj) {
    if (obj instanceof THREE.Group && obj.hitRadius !== undefined) {
      throw new Error('AiRspace L5: a control cannot live in Read space — select the object and its controls come to your hand');
    }
    obj.userData.isContent = true;
    this.read.add(obj);
    return obj;
  }

  // HORIZON is body-locked and yaw-only: it follows where you are FACING, not
  // where you are LOOKING. Pitch must not drag the mesh up and down with your
  // gaze, or the bearings stop meaning anything.
  syncHorizon(headYaw) {
    this.horizon.rotation.y = 0; // world-stable in this prototype; the user's
    // yaw is the camera's. On device this tracks torso, not head.
    void headYaw;
  }

  clearReach() { while (this.reach.children.length) this.reach.remove(this.reach.children[0]); }
  clearRead() { while (this.read.children.length) this.read.remove(this.read.children[0]); }
}
