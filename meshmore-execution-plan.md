# MeshMore — execution plan (how the work is driven)

Written 2026-11-05 as the supervisor's operating document. `meshmore-feature-register.md` is the feature list and
`meshmore-master-plan.md` §9.6 is the build order; this page is the *operating* plan: which child does what, in what
order, with which files, and what counts as done. Where this page and the register disagree, the register's authority
order wins and this page is corrected.

State: **toolchain verified, branch strategy decided, no application code changed yet. Next action is W0 below.**

---

## 1. Verified environment facts (measured this session, 2026-11-05)

| Fact | Evidence |
| --- | --- |
| Repo root `/home/ldeen/Documents/meshmore-sns`, branch `feat/ldmux-gateway`, HEAD `1e66a8d` | `git log`, `git status` |
| The planning set (register, master plan, app spec, four feature specs, breadth review) is **untracked**; 4 files modified | `git status --short` |
| App: 172 `lib/**/*.dart`, 137 `test/**/*.dart`; package `meshmore_sns_app/packages/meshcore` has 18 test files | `find` counts |
| `lib/` dirs: `meshcore` (+`gateway`), `screens` (+`maps`,`tools`,`dashboards`), `theme`, `maps`, `chat`, `peer`, `sns`, `tools`, `docs`, `bot`, `cue`, `tts`, `perms`, `shell`, `cryptokit`, `licenses`, `util`, `ui`, `gen`, `l10n` | `find lib -maxdepth 2 -type d` |
| Phone connected: `motorola_edge_2024`, serial `ZD222W34LJ`, `adb` at `/usr/bin/adb` | `adb devices -l` |
| No `flutter` on PATH. Flutter 3.47.4 exists only in the nix store; the wrapped binary's SDK is immutable and fails with `flutter failed to create a directory at …/bin/cache/artifacts` | direct run |
| Artifacts for android/web/linux are prebuilt in separate store paths (`*-flutter-artifacts-{,android-,web-,linux-}x86_64-linux`), with `bin/cache/{artifacts,pkg,stamps}` inside | `find` on the store paths |
| All four defects the master plan §9.1 names are present as described: `appTargetVer = 1` default (`frame_codec.dart:392-396`), `chdata.reserved1` discarded (`:1029-1030`), no consumed-byte assertion in `decode`, one-notification-one-frame contract (`transport.dart:14-17`) | read |
| `MeshcoreTransport` documents "one BLE notification = one frame" as the transport's responsibility | `packages/meshcore/lib/src/transport/transport.dart:14-17` |
| Subagents: fork context by default, `maxTasks 12`, `concurrency 6`, all seven builtin agents `tools: "inherit"` | `~/.pi/agent/extensions/subagent/config.json`, `settings.json` |

**Toolchain — closed, verified 2026-11-05.** Flutter is installed as a nix store SDK and must be invoked from the
`-sdk-links` wrapper, not the plain wrapper (the plain one tries to write into the read-only store).

```bash
export PATH="/nix/store/x8cc2489gk0lhbgm5q3y7pxfb7v9r706-flutter-wrapped-3.47.4-sdk-links/bin:$PATH"
export JAVA_HOME=/home/ldeen/.local/jdk/jdk-21.0.12+8
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_USER_HOME=/home/ldeen/.config/.android   # build only
```

- `flutter --version` → 3.47.4 / Dart 3.13.3 (re-verified this session). `dart` is beside it.
- `flutter test` baseline: **1044 tests, ~90 s**. One file: ~6 s. Use `flutter test test/<dir>` while iterating.
- Build: `flutter build apk --debug` then `adb -s ZD222W34LJ install -r build/app/outputs/flutter-apk/app-debug.apk`;
  `JAVA_HOME` is mandatory for gradle (Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20 are the working pins).
- Package `com.iotone.meshmore_sns_app`; permissions granted non-interactively with `adb shell pm grant …
  BLUETOOTH_SCAN BLUETOOTH_CONNECT ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS`.
- App-side log: `adb logcat -d --pid=$(adb shell pidof com.iotone.meshmore_sns_app)` filtered on
  `flutter :|\[meshcore|\[telem|\[place|BluetoothGatt`. UI: `adb exec-out screencap -p`, `uiautomator dump`.
- Side-by-side audit builds used a separate `git worktree` + a `sed` on `applicationId`; never the user's checkout.
- Record this block in `meshmore_sns_app/TOOLING.md` as W0's deliverable.

---

## 2. Source-of-truth map (primary sources first)

Authority for *decisions*: `meshmore-scope-of-record.md` → `meshmore-master-plan.md` (its §9 supersedes §8, which
supersedes §2/§4) → `meshmore-app-spec.md` → the four feature specs → `meshmore-feature-audit.md` →
`meshmore-sns-spec.md` (history only).

Primary protocol evidence on disk (never cite the research corpus as truth when firmware source exists):

- Mainline firmware + canonical docs: `/home/ldeen/Documents/meshcore-fw-alerts` (`meshcore-dev/MeshCore`, `685a869`),
  `docs/companion_protocol.md`, `docs/payloads.md`, `docs/packet_format.md`, `docs/number_allocations.md`,
  `examples/companion_radio/MyMesh.cpp` (command `#define` block, lines 6-72; `CMD_SEND_CHANNEL_DATA` 62 at :61),
  `examples/simple_repeater/MyMesh.cpp` (flood scope :1184-1189, :2826-2836; defaults :3922, :3949),
  `src/helpers/BaseChatMesh.{h,cpp}` (MAX_TEXT_LEN 160, blob 162), `src/MeshCore.h:20-22` (frame ceilings).
- Keymind fork (frame limits, compat, `dm.one_key`, mOTA, OTA queue drain, 200 measurement files):
  `/home/ldeen/Documents/mesh-research/meshcore-keymind` (`mikecarper/MeshCore`, `77d0f2c`),
  `src/helpers/CompanionFrameLimits.h`, `CompanionHardwareCommandCompat.h`, `CompanionMotaControl.h`,
  `examples/companion_radio/MyMesh.cpp:607-611,1373`, `NodePrefs.h:121`, `docs/test-results/`.
- meshcomod (`949627fe`) for the v27 version counterexample; `wadamesh` (`53d17d0`) and `wadamesh-tak` (`8944370`)
  for MediaMesh/Lua internals; `meshcore.js`, `meshcore-decoder`, `meshcore_client` under `mesh-research/clones/` as
  host-side cross-checks.
- Curated notes with citations: `/home/ldeen/Documents/mesh-research/notes/topics/` — priority reads
  `companion-behaviour.md`, `companion-wire-layouts.md`, `companion-frames.md`, `companion-command-table.md`,
  `group-data-and-scope.md`, `group-data-type-registry.md`, `media-pipeline-mechanics.md`, `places-and-images-prior-art.md`,
  `place-report-encoding.md`, `radio2-measured.md`, `mcsim-measured-reliability.md`, `meshmore-app-audit.md`.
- The knowledge store returns **web compilations**, not firmware truth (checked 2026-11-05: it cannot support
  `0x3E` budgets, repeater region-deny, or telemetry slots). Use it for orientation only.
- Hardware bench: `/home/ldeen/Documents/lora/` (two Heltec V4 boards, `INVENTORY.md`, `flake.nix`, flashing tools).

---

## 2a. Branch strategy, and the LDMUX gateway removal (decided 2026-11-05)

**Decided by evidence, 2026-11-05: remove the inter-app gateway from MeshMore.** LDMUX is a separate product with its
own repo (`/home/ldeen/Documents/ldmux`) and, on its current branch `feat/standalone-radio`, **owns the radio link
itself**: `packages/mobile/composeApp/src/androidMain/kotlin/dev/ldmux/mobile/mesh/AndroidRadioLink.kt` imports
`io.iotone.meshcore.android.{AndroidBleTransport, MeshcoreSession, RawSendCallback, SessionListener}` from its own
vendored `packages/mobile/vendor/libmeshcore` (README: copied from `meshmore-sns` at `7386999`). There is no
`GATEWAY_HANDOFF`, no loopback client and no pairing-token use left in ldmux; `mesh/Radio.kt:347` describes the
gateway protocol's sequence number and `SEND_RESULT` in the past tense. The one remaining consumer of the pattern is
gone, so MeshMore keeps no server, no grants and no second app's protocol.

The branch `feat/ldmux-gateway` still carries that work at its tip and is named after it; both are corrected in W0.
The decision record goes in `meshmore-scope-of-record.md` as a dated ruling, because the architecture document's §8
("architecture accepted: the two-app gateway design stands", 2026-10-24) is now superseded.

Measured entanglement in the app (so the removal is bounded, not a rewrite):

| Surface | Count | Paths |
| --- | --- | --- |
| Gateway implementation | 3 files | `lib/meshcore/gateway/{gateway_service,gateway_handoff,mesh_sender_adapter,secure_pairing_persistence}.dart` |
| Touch points | 5 files | `lib/main.dart`, `lib/meshcore/meshcore_controller.dart`, `lib/meshcore/airtime_prefs.dart`, `lib/meshcore/mesh_network_store.dart`, `lib/shell/home_shell.dart` |
| UI | 1 screen | `lib/screens/connected_apps_screen.dart` + its entry in `lib/screens/app_settings_screen.dart` |
| Tests | 5 files | `test/meshcore/gateway/*` (3), `test/screens/connected_apps_screen_test.dart`, `test/shell/home_shell_test.dart` |
| Packages | 2 dirs | `meshmore_sns_app/packages/meshcore_gateway/` (L2 codec), `meshmore_sns_app/packages/meshcore_host/` (desktop daemon) |
| Dependency | 1 | `pubspec.yaml:64-67` `meshcore_gateway` |

Rule for the removal: **keep the MeshCore capability, delete the gateway.** `MeshSenderAdapter` gives the app the
raw-data/OK-ERR send path that register W1 asks for ("MeshCarryCodec lifted into the app's send path"); it becomes
`lib/meshcore/mesh_sender.dart` and loses only `bindPeer`. Everything else leaves: the loopback server, sessions,
grants, pairing token and secure-storage record, Binder handoff and its Kotlin service/manifest permission, the
gateway status and Connected-apps screen, the QR grant, the LDMUX-tuned airtime governor (the app's own airtime
meter stays, `airtime_prefs.dart`), the `meshcore_gateway` package, the `meshcore_host` desktop daemon, the gateway
tests and the gateway rows in the specs. Nothing is lost: ldmux vendors the codecs it needs and keeps its own history
of the branch.

Documents to correct in the same commit: `meshmore-feature-register.md` §6a and the gateway rows, `meshmore-app-spec.md`
APP-M1–M6 (to AGAINST with the decision date), `meshmore-scope-of-record.md` (new dated decision), the architecture
§5.5 / §2.4 sections, `README.md`, `meshmore_sns_app/STATUS.md`, `meshmore-sns-gateway-handoff.md` (mark superseded and
point at the ldmux repo), and the master plan's gateway rows.

## 2b. Remote state (2026-11-05)

`origin/dev` is 2 commits ahead of this branch's base and both are R4 follow-ups that the app must keep:

- `10a8c14` swipe between grid maps + a Swipe ⇄ Pan toggle (`grid_screen.dart` `_panMode`, key `grid-pan-toggle`,
  two new ARB strings, shell capture lock).
- `c81b051` left/right swipes change screens again; maps chosen by dropdown (`grid_screen.dart`, `home_shell.dart`,
  ARB, `pubspec.yaml` version).

**It is a re-port, not a merge.** This branch rewrote `grid_screen.dart` (+494/−…) and `home_shell.dart`
(+522/−…) after the merge base `e7691c8`, while dev's change is ~108 lines in the same regions. Resolve the 6 conflict
hunks by keeping the local structure and porting dev's behaviour onto it: pan mode off on entering the tab, the
toggle only on pannable views, swipe belongs to the shell, capture lock driven by `_panMode && pansHorizontally`.
`app_en.arb`/`app_ja.arb` gain dev's two tooltip strings; regenerate `lib/gen/*` with `flutter gen-l10n`.

## 2c. Where the app's own structure sits (file ownership for briefs)

Measured 2026-11-05 (`lib` = 172 files, ~54k lines excluding generated l10n):

| Area | Files / lines | Notes |
| --- | --- | --- |
| `lib/meshcore/` | 36 / 9.4k | controller is 4,023 lines — the single biggest coupling point; split work here by concern, never two children at once |
| `lib/screens/` | 56 / 24.9k | grid 1,743 · device config 1,464 · node sheet 1,288 · chat 894 · channels 889 |
| `lib/maps/` | 14 / 3.9k | `maps_controller.dart` 1,239 lines, disk-first tile stack |
| `lib/sns/` + `cue/` + `bot/` + `tools/` | 29 / 5.4k | SNS cells, cue/earcons, bot responder, six tools |
| `lib/theme/` `lib/ui/` | 12 / 2.3k | tokens + shared widgets; the type/colour ratchet lands here |
| `lib/gen/` | 3 / 14.7k | generated; never hand-edit, regenerate with `flutter gen-l10n` |

## 3. Waves, ownership and gates

Rules that hold for every wave: one writer per directory (concurrent writers use `worktree: true`); every item ends
with targeted tests plus `flutter analyze` clean; a wave ends with the full suite and a reviewer child; every
behavioural claim carries `file:line` evidence.

Waves run in this order because it is the register's dependency order. Items inside a wave are independent unless a
"serial" note says otherwise.

### W0 — Base, toolchain and the gateway removal (serial, gate)
1. Rename the branch `feat/ldmux-gateway` → `feat/app-completion` (history kept, name corrected).
2. Merge `origin/dev` and re-port its two swipe commits onto the local grid/shell rewrite (§2b).
3. Remove the LDMUX gateway surface and correct the documents (§2a). `flutter test` + `flutter analyze` green after;
   the app still connects, sends a channel message and a DM on the phone.
4. `meshmore_sns_app/TOOLING.md` with the verified environment block, test timings, build/install/log commands.
5. Baseline numbers recorded: **1044 tests, 75 s wall, all passed (measured 2026-11-05)**; `flutter analyze` warnings;
   APK install.

Done when: a child can run `flutter test test/...` (6 s for one file) against a branch that has no gateway code and
all of dev's behaviour, and the phone runs that build.

### W1 — Correctness defects (register §1, master plan §9.1)
- **D1** `0x3E`… no: **D1 is the version default.** `appTargetVer` default becomes 3 at both call sites; tests prove
  the V3 message frames decode (per-message SNR appears).
- **D2** channel datagram `via`/radio-profile byte read and surfaced; no longer `reserved1`.
- **D3** `decode` asserts the frame was fully consumed; `CHANNEL_INFO` accepts 16- and 32-byte PSKs.
- **D4** BLE framing: MTU read at connect, refuse below 179 with the actual value shown; notification reassembly or a
  documented one-frame guarantee enforced at the transport boundary.
- **D5** `isPush` classification (27 `CHANNEL_DATA_RECV` and 29 `CLI_REPLY` are never replies).
- **D6** `interop_replay_test.dart` becomes a real replay against captured vectors.
Ownership: `packages/meshcore/**` for D1-D3, D5-D6; `lib/meshcore/**` + `lib/screens/diagnostics` for D2/D4 surfacing.
Gate: package suite green and fast; a device build still connects.

### W2 — Skin tokens prerequisite (master plan §9.5)
`MmType` gains size/spacing/radius scales; a colour ratchet test forbids new literals; the >250 `fontSize:` literals
migrate screen by screen in later waves (only the ratchet + scale land here, plus the migration of shared widgets).
Gate: eight-preset exhaustiveness still compiles; `test/theme/**` green.

### W3 — Protocol foundations (register §1)
- **P1** `0x3E CMD_SEND_CHANNEL_DATA` encoder + inbound `ChannelDataFrame` dispatch to a consumer, golden vectors both
  halves (package + controller; serial with P2 because both touch the controller).
- **P2** command correlation: every `OK`/`ERR` attributed to its command; no credit from an unregistered reply.
- **P3** conformance suite: golden vectors for every emitted frame, the four ceilings, `path_len` unpacking, airtime.
- **P4** capability probing by command probe (never version compare) + APP-A8 `#`-normalization defect.
- **P5** `0x91` one-key rejection decode; `0x42` expert-gated CLI with a typed whitelist; `0x4A`/`0x4B` status only;
  `MeshCarryCodec` lifted into the app send path.
Gate: a channel datagram round-trips through the fake transport end to end.

### W4 — Messenger correctness (register §2)
Notifications (classes, SOS channel, tap-through) · encrypted store + migration + Auto Backup exclusion + encrypted
export (APP-E1-E3, N5) · composer budget (160 incl. prefix) + drafts (D1-D3, E7) · search, unread counts, retention
visibility (E6, E2) · block store and the ten-surface matrix + report bundle (F1-F3) · history threads/export/
truncation + the four delivery rules (C1-C4).
Serial: the store migration lands before anything that writes new rows; correlation (P2) lands before the four rules.

### W5 — Radio safety (register §3)
Staged commit + single-use revert for the four stranding params · capability refusal wording + radio health readout +
region presets + the "Pinned" advert fix (remove or make true) · identity replacement carry-over · multi-radio
ownership and stranded-state copy · radio2 cost disclosure and flood-scope display.

### W6 — Places (register §4, `meshmore-places-spec.md`)
`Place` object + store + TTL ladder · long-press create · place layer with clustering and countdown badges ·
`[PLACE]` encode/parse with frozen examples · confirm/refute · directions handoff ladder · place echoes · ledger export.
Serial after W3-P1 (text sends) and W4 (store).

### W7 — Media (register §5)
Reassembly with request-missing-chunks, salted resends, marked packets, completion receipt, 350 ms pacing,
`ERR_CODE_TABLE_FULL` as backpressure · AVIF encode/decode (`avif_native` + `flutter_libavif`, 320×240 floor) ·
media-off-by-default enforcement at the send path · place photos.

### W8 — Field operations (register §5)
Position history + trail + GPX · geofences with hysteresis · inter-node relationship · SOS (12 sends, 10 beacons,
3600 s hard stop, key-bound ACK) · check-in `[CHK:<id6>]` · coverage ping with the geohash-6 cell model · operational
export bundle.

### W9 — Store readiness and cross-cutting breadth (register §7, app spec N-group)
Target API 36 · 16 KB/RELRO checklist · in-app pair flow + declaration-video path (CDM evaluated) · demo mode ·
terms/privacy/data-safety copy · error catalogue (N2) · three-clock time model (N3) · degraded modes (N4) ·
performance budgets (N6) · interop matrix (N7) · accessibility (K1-K3) · diagnostics redaction (L1-L2).

### W10 — On-device verification (~40 unverified behaviours)
Run the matrix on the motorola + two Heltec boards: pairing flow, MTU, notification, background message, reconnect,
radio2, advert location, telemetry, channel send/receive, media pacing, SOS, places on air. Reflash boards from
`/home/ldeen/Documents/lora/` as needed. Only items that need the user (a PIN, a second radio) are requested, and only
after everything else is done.

### W11 — Documentation sync (continuous, finalised at each wave end)
Update `meshmore_sns_app/STATUS.md`, `README.md` status block, the register's state column, and any decision the code
overturned. No feature ships with a stale row.

---

## 4. Standing brief block (paste into every child task)

```
Scope and authority
- Read first: meshmore-feature-register.md (your row), then the scope-of-record decision it names, then the spec.
- Primary evidence is firmware source under /home/ldeen/Documents/meshcore-fw-alerts, meshcore-keymind, meshcomod,
  wadamesh*; the research notes are a pointer, not proof. Cite file:line for every behavioural claim.
- Edit only the paths named in your task. Do not refactor, rename or reformat outside them. No new dependency
  without naming its licence and why the decided option does not work.

Quality bar
- Keep tests fast: targeted `flutter test <path>` while working; the full suite only at the end. A test file over
  5 s or a suite over ~90 s is a defect to report, not to accept.
- Every new behaviour gets a test that fails without the change. Golden/byte vectors for anything on the wire.
- User-facing strings go through ARB (app_en.arb + app_ja.arb in lockstep). No hardcoded English in widgets.
- Follow the existing patterns in the directory you touch (controller/store/widget layering, token usage, l10n).
- Commit per coherent item, message style `area: lowercase sentence, the reason`. Never commit a red tree.

Report back
- Bullets: what changed (path:line), tests run with wall time, what is verified vs unverified, and any decision you
  had to take that the documents do not cover. Name anything you deliberately did not do.
```

---

## 5. Verification protocol

- Per item: targeted tests + `flutter analyze` clean + doc row updated.
- Per wave: full `flutter test`, `flutter analyze`, reviewer child pass over the diff, then a device build/install.
- Device gates: connect, MTU value, channel send/receive with a second node, notification while backgrounded,
  reconnect after radio power-cycle, radio2 receive attribution, telemetry query, SOS cancellation.
- Every wave writes its evidence into the register row and `STATUS.md`, with the command and its output, not a claim.

## 6. Open questions to close by investigation (register §9)

Unkeyed-place "keyed only" filter · block-vs-queue interaction at send time · whether `dm.one_key` is discoverable
before a send · the three measurement protocols (§9.14 M1-M3) · CDM vs permanent FGS · RELRO padding on the current
plugin set. Each is a child task with a written answer, not a guess.

## 7. Tracker

| Wave | State | Owner | Evidence |
| --- | --- | --- | --- |
| W0 toolchain | **done** | scout | SDK path verified; 1044 tests / 90 s; gradle pins known |
| W0 docs commit | **done** | supervisor | `e86a712` on `feat/ldmux-gateway` |
| W0 branch rename + dev re-port | not started | — | conflicts: grid_screen, home_shell, arb ×2, gen ×2, tests ×2, STATUS, UX spec |
| W0 gateway removal + doc correction | not started | — | 14 app files, 2 packages, 6 docs |
| W1 defects | not started | — | — |
| W2 skin tokens | not started | — | — |
| W3 protocol | not started | — | — |
| W4 messenger | not started | — | — |
| W5 radio | not started | — | — |
| W6 places | not started | — | — |
| W7 media | not started | — | — |
| W8 field ops | not started | — | — |
| W9 store + breadth | not started | — | — |
| W10 on-device matrix | not started | — | — |
| W11 docs sync | continuous | — | — |

## 8. Questions that stay with the owner (ask only when blocked)

1. Branch: work continues on `feat/ldmux-gateway` renamed to `feat/app-completion`, or a fresh branch from `origin/dev`
   with the local line merged in? (Current plan: rename in place, so no history is lost.)
2. Is anything in the removal list above meant to survive for another client (a second app, a desktop tool) that is
   not LDMUX? If yes, name it and the capability it needs; otherwise the removal is total.
3. Push policy: is `feat/app-completion` allowed to be pushed to `origin`, or does it stay local until reviewed?
4. On-device work that needs hands: nothing yet. Later, W10 will ask for a radio reflash or a PIN only after every
   software-only route is exhausted.
