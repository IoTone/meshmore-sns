# UX Best Practices — XR, TUI, and Web

*Lessons learned and patterns established during RobotARme development.*
*Intended as a living reference — update as new patterns emerge.*

> **Scope.** Part 1 here is the **WebXR / three.js** stack. For native Android XR
> (Jetpack XR, SceneCore, ARCore for Jetpack XR) see
> `AndroidXR_Glasses_Dev_StarterGuide.md` and
> `AndroidXR_Glasses_UX_Best_Practices.md` — those carry the device-proven
> findings from MeshmoreXR on optical see-through glasses. Two items below are
> stack-independent and worth reading whichever renderer you are on: the
> display-technology distinction under *Passthrough*, and the angular sizing
> rule under *Text Rendering*.

---

## Part 1: XR / WebXR

### Panel Placement

**Place UI panels in front of the user, not at world origin.**

When entering immersive AR/VR, the user's real-world position becomes the camera origin. Panels placed at a fixed world position (0, 1.3, 0) will end up inside the user's head or behind them.

```javascript
// BAD: panels at fixed world position
panel.position.set(0, 1.3, 0);

// GOOD: anchor panels relative to user on session start
const xrCam = renderer.xr.getCamera();
const pos = new THREE.Vector3();
const fwd = new THREE.Vector3(0, 0, -1).applyQuaternion(xrCam.quaternion);
fwd.y = 0; fwd.normalize();
uiAnchor.position.set(
  pos.x + fwd.x * 1.5,   // 1.5m in front
  Math.max(1.2, pos.y - 0.15),  // comfortable eye level
  pos.z + fwd.z * 1.5,
);
uiAnchor.lookAt(pos.x, uiAnchor.position.y, pos.z);  // face the user
```

**Comfortable distance:** 1.2–1.8m from the user. Closer than 0.8m causes eye strain. Further than 2.5m makes text hard to read.

**Size in degrees, not metres, and check the layout fits before building it.** What the eye resolves is angular size, so derive every dimension from the distance the element will sit at:

```
size_metres  = 2 · distance · tan(angle / 2)
usable_width = 2 · distance · tan(FOV / 2)
```

Floors that held up on optical glasses: **1.3° for text** (you must resolve strokes to tell `8` from `B`), **3.0° for icons**. Summing your labels against the usable width catches overlapping layouts in a calculator rather than on your face — it found three separate collisions in one project, each of which had been misread as a styling problem.

**Allow repositioning:** Register panels as draggable so users can move them to their preferred position. Use a shared parent group (`uiAnchor`) so all panels move together.

**Brief delay on AR start:** The XR camera takes a few hundred milliseconds to report accurate world position. Delay panel anchoring by ~500ms.

### Text Rendering in XR

**MSDF atlases are ASCII-only unless you generate CJK atlases.**

three-mesh-ui uses pre-built MSDF (Multi-channel Signed Distance Field) font atlases. These contain a fixed character set. Any character not in the atlas crashes the renderer:

```
The character '組' is not included in the font characters set.
TypeError: Cannot read properties of undefined (reading 'x')
```

**Mitigation patterns:**
- Use `tMsdf()` wrapper that returns English fallback for non-ASCII locales
- Use troika-three-text for runtime SDF rendering of any Unicode character
- Keep three-mesh-ui for layout/panels, troika for localized content text
- When mixing: three-mesh-ui handles panel borders, backgrounds, button states; troika handles the actual text content

**troika-three-text:** Loads .ttf/.otf fonts at runtime, generates SDF glyphs on-demand in a web worker. Supports full CJK. Verified at 60fps with 25 text objects including Japanese. Requires `blob:` in CSP `script-src` and `worker-src` for its web worker.

### Toasts and Notifications

**Place toasts in world space, not camera space.**

Camera-attached toasts (HUD-style) move with the user's head — they can never be "looked at" and become unreadable in XR.

```javascript
// BAD: follow camera every frame
_toastHud.position.copy(camera.position).add(dir);  // in animate loop

// GOOD: position once when toast appears, leave in world space
if (!_toastHudPinned) {
  _toastHud.position.copy(camera.position).add(dir);
  _toastHudPinned = true;
}
```

When all toasts expire, unpin the HUD so the next batch appears in front of wherever the user is looking at that moment.

**Render toasts in front of panels:** Set `depthTest: false` on toast materials and use `renderOrder: 1000` to ensure toasts are always visible.

### Input in XR

**Show the virtual keyboard by default on input-focused views.** Users wearing a headset can't easily find a small toggle button. Auto-show the keyboard when navigating to a view that requires text input.

**XR controller raycasting:** Extend the InteractionManager to support XR controllers alongside mouse. Use `renderer.xr.getController(0/1)` for ray origin, `selectstart`/`selectend` for click. Visible ray line (cyan, `depthTest: false`) provides essential feedback. Shorten the ray to the hit point for precision feedback.

**Hand tracking support:** WebXR's `selectstart`/`selectend` events fire on pinch gestures automatically via the same controller objects. No separate implementation needed.

**Focus feedback must be dramatic, not subtle.** A 15% opacity bump that looks fine on desktop is invisible through Spectacles passthrough at 90fps. The minimum viable hover state for XR:
- Background opacity bump 70% → 100%
- White outline appears (border width ≥ 0.006)
- Slight scale up (1.0 → 1.05) — gives tactile sense of "popped forward"
- Audio cue (soft keystroke) on hover-in, not just on click

**Always render a reticle in world space at the ray hit point.** The ray line itself can be unreliable on hand-tracking devices (Spectacles, Quest hand mode) where the controller transform is derived from joint poses. A small bright sphere (~12mm radius) placed at the world hit point — sized/colored differently when over a clickable target — gives unambiguous focus indication regardless of ray rendering. Add it to the scene (not as a child of the controller) and update its position each frame from `controller.matrixWorld + direction * hit.distance`. Use `depthTest: false` and `renderOrder: 999` so it renders through panels.

**Visual ray + reticle together** is the right pattern: the ray shows direction, the reticle shows the precise hit point, and the button hover state confirms the interaction will register.

**Beams must use real geometry, not `LineBasicMaterial`.** WebGL's `linewidth` is silently ignored on most platforms (always 1px). For a sci-fi laser look that holds up through Spectacles passthrough, build the beam as 3 concentric `CylinderGeometry` cylinders — a thin bright core (~6mm radius), a mid glow (~18mm), a soft halo (~45mm) — all with `THREE.AdditiveBlending` so the layers sum into a luminous bloom. Cylinder length is controlled per-frame with `scale.z` to match the raycast hit distance. Anything under ~1cm radius is invisible in bright AR passthrough.

**Color-code the hands.** Orange for one hand, cyan for the other. Users instinctively recognize "the orange ray is from my left hand" without thinking. Hand differentiation matters more than aesthetic consistency.

**Hide controller geometry until WebXR connects an input source.** Listen for `'connected'` and `'disconnected'` events on each `getController(i)`. Three.js doesn't auto-hide controller children — if you build a beam as a child of an unbound controller slot, it renders at the world origin (≈ eye level for the user) the moment XR begins, which looks like a phantom beam stuck in your face. Track `sourceConnected` per slot, set `beamGroup.visible = false` initially, and toggle it from the connect/disconnect event handlers. Also clear hover state on disconnect (otherwise the last-hovered button stays in its hover state forever).

**Make XR config tunable from the server.** Beam radii, opacities, colors, reticle size — these are taste-driven. Don't bake values into the JS. Render a `window.XR_CONFIG = {...}` `<script>` block from the page template, populated from `.env`. Devs can iterate on the visual design without rebuilding JS — edit `.env`, restart server, reload page. Pattern: `const X = +(window.XR_CONFIG?.foo ?? defaultFoo);` at module load with sensible defaults.

**Spectacles-specific: hand tracking ray pose validity.** When using hand tracking on Snap Spectacles, the input source pose can briefly be at world-origin with identity orientation in the first few frames before the hand is fully resolved. The reticle visibility check should also test `controller.matrixWorld.elements[12-14]` (translation column) — if all near zero AND no hit was found, the controller pose is suspect. In practice the `connected`/`disconnected` event handling above catches this for us, but worth knowing.

**Device authorization flow for password entry:** Typing complex passwords with XR controllers is painful. Implement RFC 8628 device authorization: XR shows a short code, user enters it on their phone with a real keyboard. Much better UX than virtual keyboard password entry.

### Passthrough / Mixed Reality

**Enable passthrough with a transparent clear color:**
```javascript
renderer.setClearColor(0x000000, 0);  // alpha=0 → passthrough
```

Request `'immersive-ar'` with `'local-floor'` reference space. The matrix floor grid provides spatial anchoring in the real world.

**⚠️ Know whether the headset is video passthrough or additive optical — it changes what you can draw.** Video passthrough composites your scene over a camera feed: black is black and contrast works as it does on a screen. Additive optical see-through (Xreal Aura class) *adds* light to the room and can never make anything darker, so:

- `0x000000` is not black, it is **invisible** — it is the room showing through.
- A dark backing plate behind small UI, the standard contrast fix on video passthrough, does nothing at all. Worse, if it writes depth it becomes an occluding hole.
- Filled shapes read as lumps of emitted light; **thin line art reads as a diagram** — the exact opposite of the video-passthrough preference.
- The only reliable legibility lever left is **angular size**.

Test on the actual optics before committing a visual language. See §0 of `AndroidXR_Glasses_UX_Best_Practices.md` for the full comparison table.

**Offer the AR button before login.** Users may want to put on their headset and enter AR before authenticating. The "Start AR" button should be visible on the login page, not just the post-login app.

### Grabbable Panels

**Let users reposition panels by dragging.** In XR, users have different physical spaces and preferences. Register panels with `draggable: true` in the InteractionManager. Use a shared `dragTarget` (parent group) so all panels move together.

Desktop: click-drag on the panel. XR: controller grab (trigger hold + move).

### Audio in XR

**Initialize Web Audio on first user gesture:**
```javascript
// BAD: at module load (blocked by browser)
initAudio();

// GOOD: on first click/keypress
document.addEventListener('click', () => initAudio(), { once: true });
```

**Provide audio feedback on every interaction:** Keystroke sounds on text input, navigation blips on button clicks, success/error chimes on API results. Silence is disorienting in XR — audio confirms that interactions registered.

**Offer multiple sound sets:** Users have different preferences and environments. Mechanical keyboard, terminal, typewriter, synth, silent. Let users cycle through options in-XR with immediate audio preview.

### Performance

**Target 90fps in XR.** Frame drops cause motion sickness. Profile with the browser's Performance panel.

- troika-three-text: verified 60fps with 25 objects. SDF generation is async (web worker), doesn't block render.
- three-mesh-ui: `ThreeMeshUI.update()` can be expensive with many panels. Minimize visible panels.
- Matrix floor shader: use `depthWrite: false` and low opacity to avoid overdraw costs.
- Digital rain columns: use instanced rendering or limit to ~20 columns.

---

## Part 2: TUI / Terminal

### Color and Rendering

**Use 24-bit true-color for modern terminals.** Most terminals (Ghostty, WezTerm, iTerm2, foot) support `\e[38;2;R;G;Bm`. Match colors to the XR theme for brand consistency.

**Detect terminal capability:** Check `TERM`, `TERM_PROGRAM`, and custom env vars (`ROBOTARME_ANSI`) before using ANSI escapes. Fall back to plain text for dumb terminals and pipes.

**Half-block characters for pseudo-graphics:** `▀▄█` (upper/lower/full block) give 2x vertical resolution. Use for ASCII art logos and banners.

### Animation

**Use background threads for animation during API calls.** The ship-in-pipe dataflow animation runs in an `sb-thread` while the HTTP request executes. Guarantees minimum visible duration (`*min-animation-secs*`) even when the API returns instantly on localhost.

**Avoid cursor save/restore during user input.** `\e[s`/`\e[u` interacts badly with `read-line` and background threads. For prompt-time effects, use synchronous inline output (digital rain after Enter) rather than concurrent cursor manipulation.

**`\e[1B` (cursor down) doesn't work at the terminal's last line.** Multi-line animation that requires moving the cursor down will break at the bottom of the terminal. Use single-line animation (overwrite current line) for reliability.

### Input

**Character-at-a-time input for rich prompts:** Use `stty cbreak -echo` to read individual keypresses. This enables real-time effects (digital rain decay under the cursor as you type). Always restore with `stty -cbreak echo` in `unwind-protect`.

**Empty input semantics:** Empty username = cancel/go back (silent). Empty password = show error message (not silent — user needs feedback). Empty in password-change = show validation error.

### Audio

**Terminal BEL is universal but limited.** `(write-char (code-char 7))` triggers the OS alert sound. Double-BEL for success, single for error. The actual sound depends on the terminal's configuration.

**For richer TUI audio:** Use platform-specific commands (`afplay` on macOS, `paplay` on Linux) with fire-and-forget subprocesses. Detect platform at startup.

### Localization

**Standard env vars for locale:** Check `--locale` flag → `ROBOTARME_LOCALE` env → standard `LANG` env → default en_US. Support both `ja_JP` and `ja_JP.UTF-8` formats.

**CJK renders natively in modern terminals.** No special handling needed — `format t` with Japanese strings works if the terminal font includes CJK glyphs (standard on macOS/Linux).

**Keep the ASCII art logo in English regardless of locale.** It's a brand mark rendered with the pixel font, not translatable text.

### FASL Cache

**SBCL caches compiled Lisp files.** Changes to `.lisp` files won't take effect if the `.fasl` cache is stale. The `bin/robotarme` script should:
```bash
rm -f "$HOME/.cache/common-lisp"/*/path/to/cli.fasl
```
Also add `asdf:clear-system` before `ql:quickload` to force recompilation.

**Never commit .fasl files.** Add `*.fasl` to `.fossil-settings/ignore-glob` and `.gitignore`.

### Macros for Flat Code

**CL macros reduce nesting dramatically.** Deep `let`/`loop`/`cond` nesting causes paren balancing errors. Macros like `with-screen`, `with-animation`, `with-api-result`, and `defmenu` collapse 30-40 lines into 5-10.

**Prefer `Write` over `Edit` for deeply nested CL code.** String replacement (`Edit`) on Lisp code is error-prone — each substitution can shift the paren count. Full file rewrite (`Write`) guarantees balance.

**Run a paren balance check after every edit:**
```python
d = sum(1 if c == '(' else -1 if c == ')' else 0 for c in source)
assert d == 0
```

---

## Part 3: Web Pages

### Readability in Mixed Reality

**Increase font sizes for MR viewing.** When viewing a web page through a headset's passthrough camera, text is smaller and harder to read than on a desktop monitor.

- Code input: 32px minimum (for device codes like `XXXX-XXXX`)
- Form labels: 14px minimum
- Body input fields: 20px minimum
- Buttons: 18px font, 16px padding
- Add visual icons (SVG) for context — a headset icon on the device auth page helps users understand the flow

### i18n with `data-i18n` Attributes

**Use data attributes for HTML localization:**
```html
<label data-i18n="device_page.code_label">Device Code</label>
```

```javascript
document.querySelectorAll('[data-i18n]').forEach(el => {
  el.textContent = translations[el.dataset.i18n] || el.textContent;
});
```

This keeps the HTML readable (English is the default visible text) while supporting runtime translation. The `data-i18n` attribute serves as both the translation key and documentation.

### Keystroke Audio on Forms

**Add keystroke sounds to web forms.** A lightweight script (~30 lines) using Web Audio API adds satisfying click sounds on every keypress. Initialize the AudioContext on the first keydown event (browser requirement).

```javascript
document.addEventListener('keydown', function(e) {
  init();  // lazy AudioContext init
  if (e.target.tagName === 'INPUT') click();
});
```

### CSRF Considerations

**Not all pages need CSRF.** Endpoints that validate credentials directly (like `/api/device/confirm`) don't benefit from CSRF protection. CSRF protects against unauthorized actions by an already-authenticated user — if the endpoint requires a password, the password IS the authentication.

**Browsers may not save `Set-Cookie` from 401 responses.** If your CSRF flow requires fetching a session cookie from an endpoint that returns 401 (like `GET /api/session` for unauthenticated users), the browser may silently discard the cookie. Design CSRF flows to avoid this.

---

## Part 4: Cross-Platform

### User Preferences

**Store preferences server-side, sync across devices.** Font, audio, and locale preferences saved via API persist in the database. Changing a preference on TUI is reflected on XR on the next page load (and vice versa).

**Resolution order:** User model (authenticated) → localStorage (browser, pre-auth) → environment variables (TUI) → default.

### Locale Switching

**Reload the page on locale change.** Three-mesh-ui builds text geometry at creation time with a specific font. Switching locale after panels are built requires rebuilding them. A page reload is the simplest and most reliable approach.

### JSON Message Catalogs

**One JSON file per locale, shared between backend and frontend.** The same `en_US.json` / `ja_JP.json` files are loaded by CL (`jonathan:parse`) and JS (`fetch`). ~160 keys covers all UI text.

**Fallback chain:** Locale-specific message → English message → raw key string. Never show a blank string — the key itself (`"login.authenticate"`) is a useful debugging indicator.

### Authentication Flow

**Two-step login for 2FA:**
```
POST /api/login → password OK → { requires_totp: true, totp_session: "token" }
POST /api/login/verify-totp → TOTP code OK → full session
```

The `totp_session` token is a 64-char hex random (same strength as device auth codes). It proves password verification occurred without granting a session cookie. Expires in 5 minutes.

**Device authorization (RFC 8628) for XR:** User code (8 chars, no ambiguous characters) displayed on headset. Phone/PC confirms at `/device`. Polling every 5.5 seconds (respects rate limit). Much better than typing passwords in VR.

### Rate Limiting

**Separate rate limiters for different threat models:**
- Auth endpoints (login, register): 5/min per IP
- Device poll: 1 per 5 seconds per IP (RFC 8628 `slow_down`)
- TOTP verify: 5/min per IP

**Reset on success:** Clear the rate limit counter after a successful login to avoid penalizing legitimate users who mistype once.

**Clear rate limits in tests:** The E2E test suite resets `*rate-limit-table*` between test sections to avoid 429 errors from accumulated requests.

### Versioning

**Bump the patch version on every bug fix.** The version is displayed on the TUI welcome screen and the XR login/app pages (via `/api/version`). Users can verify they're running updated code. Server version from `robotarme.asd`, CLI version from `*cli-version*`.

**Keep server and CLI versions aligned.** They're separate ASDF systems but should increment together.

---

## Appendix: Common Pitfalls

| Pitfall | Impact | Prevention |
|---------|--------|-----------|
| Japanese text in MSDF panel | Crash: `Cannot read properties of undefined` | Use `tMsdf()` for all three-mesh-ui text |
| `\e[nA` resets column on some terminals | Cursor moves to column 1 instead of staying in place | Use `\e[s`/`\e[u` (save/restore) instead of relative movement |
| SBCL `--eval` with multiple forms | Error: "Multiple expressions" | Wrap in `(progn ...)` |
| `bin/robotarme` not passing args | SBCL doesn't see `--locale` etc. | Add `-- "$@"` after the `--eval` chain |
| FASL cache stale | Old code runs despite source changes | Delete cache in bin script: `rm -f ~/.cache/common-lisp/*/...cli.fasl` |
| `fetch()` without body on POST | Lack http-body middleware crashes parsing empty JSON | Always send `body: '{}'` on POST requests |
| AudioContext before user gesture | Silently fails — no audio | Initialize on first click/keypress with `{ once: true }` |
| Toast `TOAST_DIST` too far | Toasts render behind panels | Use 0.8m (closer than panel distance of 1.2-1.5m) |
| `defun` inside a `defun` (missing paren) | Nested function defined at runtime, not load time — appears undefined | Run paren balance check after every edit |
| `nil` serialized as `[]` by jonathan | JavaScript truthy check passes for `[]` | Use `:false` keyword for explicit JSON `false` |

## Spatial Status & Guidance Standards (R30 native — adopted 2026-07-08)

Owner rule: **no long-running job may report progress only inside a panel.**
If the user must stare at one spot to know what's happening, the design is
wrong. Standards for every job > ~2 seconds on Android XR:

1. **Progress HUD: HEAD-LOCKED at the outer edge of the viewport** (owner
   decision 2026-07-09, reversing the earlier lazy-follow — for a short-lived
   indicator the user is actively watching, rigid head-lock at the edge is
   what's wanted; the lazy-follow toast was "a tiny window off in the distance
   at a strange angle"). Implementation: a PanelEntity repositioned every
   ~40 ms via `head.compose(edgeOffset)` (full head rotation, right edge,
   ~0.8 m ahead). *Distinction:* persistent CONTENT (models, panels) stays
   world-anchored so the user can walk around it; only the transient progress
   ornament is head-locked.
2. **Percentage or step semantics, always.** `SCANNING 60%`, `UPLOADING 45%`,
   `SERVER PROCESSING 25s`, `STEP 2/4` — never a bare spinner. If the backend
   gives no %, show elapsed time and the current step name.
3. **In-environment task guidance.** When quality depends on user motion,
   SAY WHERE TO LOOK: during a room scan the HUD shows live coverage
   (`FLOOR ✓ · WALLS 1`) and prompts (`slowly look around — floor + walls`).
   The environment is the UI; direct the user's gaze to improve the result.
4. **Terminal cue + auto-dismiss.** Completion flashes a final state
   (`MODEL READY`) then removes the HUD within ~3 s; failures persist the
   error in the panel log (the durable record) — the HUD is transient signal,
   the panel is history.
5. **Capability-gated with graceful fallback.** No spatial capability (2D /
   Home Space) → the panel log remains the only surface; the HUD must never
   be load-bearing for correctness.
6. **Exception-contained.** HUD failure (DP API drift) degrades to
   panel-only — a status ornament may never crash a job (field rule).

Applies to: SCAN ROOM (first implementation, app 0.5.2), future OTA pushes,
release uploads, and any Phase D+ long operation.
