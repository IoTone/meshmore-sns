# MeshMore — execution plan (how the work is driven)

Written 2026-11-05 as the supervisor's operating document. `meshmore-feature-register.md` is the feature list and
`meshmore-master-plan.md` §9.6 is the build order; this page is the *operating* plan: which child does what, in what
order, with which files, and what counts as done. Where this page and the register disagree, the register's authority
order wins and this page is corrected.

State: **toolchain unblocked pending one scout result; no code changes made yet in this pass.**

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

**Toolchain gate (must close before any code child starts).** Preferred fix: copy the unwrapped SDK to a writable path
and symlink the three artifact sets into its `bin/cache/`, then verify `flutter --version`, `flutter devices`,
`flutter pub get`, `flutter test` and an APK build. Record the exact recipe in `meshmore_sns_app/TOOLING.md`.

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

## 3. Waves, ownership and gates

Rules that hold for every wave: one writer per directory (concurrent writers use `worktree: true`); every item ends
with targeted tests plus `flutter analyze` clean; a wave ends with the full suite and a reviewer child; every
behavioural claim carries `file:line` evidence.

Waves run in this order because it is the register's dependency order. Items inside a wave are independent unless a
"serial" note says otherwise.

### W0 — Toolchain and baseline (serial, gate)
1. Writable SDK recipe + `meshmore_sns_app/TOOLING.md`; record `flutter test` baseline (count, wall time),
   `flutter analyze` output, `flutter build apk --debug`, `adb install` of the current build.
2. Commit the untracked planning set on a new branch `feat/app-completion` (docs first, no code).

Done when: a child can run `flutter test test/...` in under a minute and the phone runs the current build.

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
| W0 toolchain + baseline | in progress | scout | open |
| W0 docs commit on `feat/app-completion` | not started | supervisor | — |
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
