// AiRspace UI — shared spatial constants.
//
// Widgets size their labels in VISUAL ANGLE, which means they need to know how
// far away they will actually be. When a widget hardcodes one design distance
// and its host places it at another, every label silently lands under the 1.2
// deg readability floor — the failure is invisible in code review and obvious
// only on a headset. So the distance lives in exactly one place.

export const REACH = 0.62;  // controls: 0.35–0.7 m (L5)
export const READ = 1.4;    // content:  1.2–2.5 m (L5)

// L7 floors, in degrees of visual angle.
export const MIN_TEXT_DEG = 1.2;
export const MIN_TARGET_DEG = 0.6;
export const MIN_REACHED_DEG = 2.0;

// Label sizes are set above the floor with headroom, because several widgets
// scale their labels down for depth cueing (Tumbler dims and shrinks the
// non-facing values) and the SMALLEST rendered state is what has to clear 1.2.
export const LABEL_DEG = 1.5;
export const LABEL_SUB_DEG = 1.4;
export const LABEL_FACE_DEG = 1.9;
