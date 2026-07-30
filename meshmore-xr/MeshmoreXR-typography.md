# MeshmoreXR — Typography Plan

**Status:** proposal, blocking further text work.
**Supersedes:** the font paragraph in `MeshmoreXR-i18n-ja.md` §4 and the implicit
"stroke glyphs are the text system" assumption in `spatial/Glyphs.kt`.
**Companion docs:** `AiRspace-UI.md` (L7 angular law), `MeshmoreXR-i18n-ja.md`
(kinsoku, locale switching), `MeshmoreXR-design-brief.md` §7 (themes).

---

## 0 · What forced this

We shipped a 4×6 stroke font. It is genuinely the right answer for a callsign
welded to a mote — the glyph is extruded geometry, it has volume, it shades like
the rest of the symbology, and there is no surface anywhere. It is also,
permanently, incapable of drawing 漢字. A stroke font is a set of hand-authored
line segments; 常用漢字 alone is 2,136 characters averaging ten strokes each,
and hand-authoring them is not a project, it is a career.

So there are two truths to hold at once:

- We must render CJK, and that requires a real font with real glyph outlines.
- We must not become a mobile app: text on a lit rectangle, left-aligned, in a
  scrolling list, at a fixed place in the viewport.

The mistake would be to treat those as the same constraint. They are not. **A
panel is a filled surface with edges. A glyph is ink.** On an additive
see-through display, black is transparent — a textured quad with a transparent
ground emits only its ink and has no visible rectangle at all. Real font
rendering does not force us onto panels; only *backgrounds, boxes, and scrolling*
do. That distinction is the whole plan.

---

## 1 · Measured facts

Everything below is derived from these, not from taste.

### Device — XREAL Aura, per eye

| Quantity | Value | Source |
|---|---|---|
| Render target | 1920 × 1200 | display 20 is 3840×1200 stereo (`dumpsys display`) |
| FOV | ≈ 61° H × 34° V (70° diagonal) | design brief §6 |
| **Angular resolution** | **31.5 px/° horizontal**, 35.3 px/° vertical | 1920/61, 1200/34 |

Use **31 px/°** as the working figure — the horizontal axis is the tighter one
and text runs horizontally.

### Faces we already own

Measured directly from the TTFs in `meshmore_sns_app/.../assets/fonts/`:

| | Saira | JetBrains Mono |
|---|---|---|
| unitsPerEm | 1000 | 1000 |
| **Cap height** | **0.688 em** | **0.730 em** |
| x-height | 0.510 em | 0.550 em |
| Variable axes | **`wght` 100–900, `wdth` 50–125** | `wght` 100–800 |
| Useful features | `zero` `tnum` `lnum` `case` `ss01` `ss02` | `zero` `case` `calt` |
| Codepoints | 661 | 976 |
| Latin Ext-A | 128/128 | 126/128 |
| Greek / Cyrillic | 4 / 0 | 77 / 98 |
| **Kana / CJK** | **0 / 0** | **0 / 0** |

Two consequences, both load-bearing:

1. **Neither face can render a single Japanese character.** A CJK face is not a
   nice-to-have, it is a missing dependency.
2. Saira has a **width axis**. That matters more in XR than on a phone, and in
   the opposite direction — see §4.

---

## 2 · Three tiers, and the rule that picks between them

| Tier | What it is | Handles | Where it may appear |
|---|---|---|---|
| **S — STROKE** | Extruded segment geometry (`spatial/Glyphs.kt`, `Prims.spur`) | Latin caps, digits, a few marks | Anything welded to a 3D thing: callsigns, microhud ticks, bar labels, numerals |
| **R — RUN** | Real font rasterised per text run into a transparent-ground texture on a quad | **All Unicode**, incl. CJK, accents, emoji | Anything carrying *language*: messages, place names, settings labels, node detail |
| **P — PANEL** | Compose `Text` on a `SpatialPanel` | whatever Compose does | **Two places only** (below) |

**The routing rule, in order:**

1. Is it a **developer surface** (`--ez debug true`) or the **system IME escape
   hatch**? → **P**. Nothing else may use P, ever.
2. Does the string contain anything outside `[A-Z0-9 .\-_/:?#*+!(),']`? → **R**.
3. Is it bound to a specific 3D object and short (≤ ~16 cells)? → **S**.
4. Otherwise → **R**.

Note what rule 2 does: it makes CJK, accents, and emoji *automatically* take the
real-font path. `Callsign.render()` stops being a fallback that degrades text and
becomes what it should have been — the router. Its tofu boxes remain, but only
for tier S, where they are correct: a stroke-font surface honestly reporting that
it cannot draw a character. Tier R never produces tofu.

**Tier S is not deprecated.** It is the thing that makes the horizon look like
Wipeout rather than like a HUD overlay, and it is the only text with genuine
volume. Latin callsigns keep it.

---

## 3 · The faces

| Role | Face | Why |
|---|---|---|
| **Display** (wordmark, surface titles) | **Saira**, `wght` 600, `wdth` 105 | Direct continuity with Meshmore SNS mobile. The brand already reads this way. |
| **Body / CJK** | **M PLUS 1 Code** | Measured below. Monospaced and technical rather than humanist, and sits beside Saira without argument. |
| **Telemetry** (numerals, units, RSSI, coordinates) | **JetBrains Mono**, `wght` 500, `zero` on | Continuity with mobile's slashed-zero motif. Monospace is already tabular. Best x-height of the three (0.550). |

**Mixing rule:** never mix Saira and M PLUS inside a single run. A run is
single-face. When a *mixed-script* string occurs (`ridge-2 の中継局`), the whole
run goes to M PLUS — its Latin is competent and script-consistent, and swapping
faces mid-run at 1.5° of visual angle reads as a rendering fault.

**M PLUS 1 Code, measured** (from the prototype's WOFF, same method as §1):

| | value |
|---|---|
| unitsPerEm | 1000 |
| **Cap height** | **0.730 em** |
| Codepoints | 5,649 |
| **CJK Unified Ideographs** | **5,232** |
| Kana | 181 |
| ASCII | 95/95 |

5,232 ideographs comfortably clears 常用漢字 (2,136) and JIS level 1 (2,965) and
covers most of level 2 (level 1+2 is 6,355). Names and place names outside that
set fall through to the system font chain (§6.2).

**The useful coincidence: M PLUS 1 Code and JetBrains Mono share a cap height of
exactly 0.730 em.** Telemetry set in JB Mono and body set in M PLUS therefore
align on the same cap line at the same em size with no per-face correction. Saira
at 0.688 does not, and needs a +6% em to sit on the same cap line — worth
knowing wherever a display word abuts a numeral.

Caveat: the measured file is the `@fontsource` **japanese subset**, split by
unicode-range for the web. Android must ship the **full TTF**, whose ideograph
count is higher. Verify the shipped artefact, not this number.

---

## 4 · Weight, width, and contrast on an additive display

This is where XR inverts mobile instincts, and it is the part most likely to be
got wrong by reflex.

**Black is transparent.** There is no such thing as a dark scrim behind text.
The mobile move — drop a 60% black plate under the label so it survives a busy
background — renders *nothing at all* on the Aura. The only variables that raise
contrast are **more ink** and **more light**:

| Tool | Works on additive? | Notes |
|---|---|---|
| Dark scrim / plate behind text | **No** | Draws nothing. Do not ship code that assumes it. |
| Dark outline around glyphs | **No** | Same reason. |
| Heavier weight | **Yes** | The primary tool. |
| Larger angular size | Yes | Expensive in FOV. |
| **Bright halo** (same hue, ~25% alpha, ~0.08° blur) | **Yes** | Raises local luminance around the stem. This is our substitute for an outline. |
| Wider `wdth` | Yes | Open counters survive glare; closed counters fill in. |

**Weight floors.** Mobile already had to bump Saira to `w500` because it renders
light on dark. XR is worse — the real world behind the glyph is often a bright
window. Floors:

- Display: `wght` **600** (never below 500)
- Body / CJK: **500**
- Telemetry: **500**
- Microhud: **600** — smallest and most safety-relevant

**Width.** Saira's `wdth` axis defaults to 100 and goes down to 50. **Never go
below 100 in XR.** Condensing is a mobile solution to narrow screens; here the
scarce resource is *angular* width, and narrowing the glyph closes its counters
at exactly the size where the counter is what distinguishes `a` from `o` from
`e`. Prefer `wdth` **105** for display and accept the extra degree.

**Stem minimum:** ≥ **0.06°** (≈ 2 px). Below that a stem aliases into the
background on a per-frame basis and shimmers as the head moves.

---

## 5 · The angular scale

### 5.1 Fixing an ambiguity first

`MeshmoreXR-i18n-ja.md` §1 gives floors of 1.2° / 1.5° / 1.8° but does not say
*what is being measured*. That matters: Latin cap height is ~0.69 em while a
kanji fills ~0.88 em of ink, so "1.8° of kanji" means something very different
depending on whether you read it as cap height, em, or ink.

Ink height is the quantity the *eye* resolves, so that is where the floors are
reasoned. But it cannot be the number the API takes, and one glyph proves why:

| glyph | ink height | ink width |
|---|---|---|
| 一 | **0.077 em** | 0.894 em |
| 日 | 0.851 em | 0.700 em |
| 議 | 0.921 em | 0.921 em |
| 鬱 | 0.923 em | 0.940 em |

`一` is a single horizontal stroke. Sizing a run so that *its* ink reached 1.8°
would blow the em box up by 12×. Its legibility is governed by stroke weight and
width, not height — and any rule keyed on ink height gets this catastrophically
wrong.

**So: the floors are stated as ink height (the rationale) and the API takes EM
DEGREES (the value).** The conversion below is done once, here, from measured
ratios — not per-string at runtime.

### 5.2 The floors, and what they cost

All ink/em figures below are **measured**, not assumed — glyph bounding boxes
read out of M PLUS 1 Code's `glyf` table.

| Script | Ink floor (rationale) | measured ink/em | **⇒ em size (the API value)** | ⇒ px em @31 px/° |
|---|---|---|---|---|
| Latin (Saira) | cap **1.2°** | 0.688 | **1.75°** | 54 px |
| Latin (M PLUS / JB Mono) | cap **1.2°** | 0.730 | **1.65°** | 51 px |
| Kana | **1.5°** | 0.750 (ヲ) – 0.862 (ぱ) | **1.75°** | 54 px |
| Kanji | **1.8°** | 0.851 (日) – 0.929 (無), mean 0.90 | **2.00°** | **62 px** |

Kana ratios are taken across both syllabaries because katakana runs shorter than
hiragana (ア 0.765 vs あ 0.857); sizing to hiragana alone leaves katakana ~11%
under its floor. Kanji uses the dense end of the range, since the dense glyphs
are the ones the floor exists to protect.

The useful surprise: **kana and Latin want the same em size** (1.75°). Only
kanji costs more, and only by 14%. So a mixed ja/en interface does not need two
layout grids — it needs one grid plus a promotion rule for runs containing kanji.

**Promotion, not demotion.** As already implemented in the prototype's
`minDegFor()`: a caller asking for 1.2° on a string containing kanji *gets*
2.05° em. The request is a floor, never a ceiling. This must be enforced in the
API, not left to callers, because the caller is usually a layout that has no idea
what locale it ended up in.

### 5.3 Dense-kanji promotion (tier 2)

At the 1.8° floor a 14-stroke kanji has roughly 3 px stems separated by 2 px
gaps. That is *at* the limit, not comfortably inside it. 態, 曜, 議, 護 will
mush. Two options, in order of cost:

1. **Now:** promote the em to **2.4°** whenever a run contains any character in
   CJK Unified Ideographs above a simple density test.
2. **Later:** measure ink density per glyph *when it is rasterised* (fraction of
   covered pixels in the em box) and cache it in the glyph record. Above ~0.34,
   promote. This is free — we are rasterising the glyph anyway — and it is
   exact rather than heuristic.

### 5.4 The roles

| Role | Ink | Tier | Use |
|---|---|---|---|
| **WORDMARK** | 4.0° | S | Launch mark. Once, briefly. |
| **TITLE** | 2.4° | R | Surface name; the "where am I" line on the back-of-hand menu |
| **BODY** | 1.75° em Latin / 2.00° w/ kanji | R | Message text in the REEL, node detail in FOCUS |
| **CALLSIGN** | 1.4° | S | Node labels on the horizon |
| **TELEMETRY** | 1.3° | S | Numerals, units, bearings |
| **MICRO** | 1.2° | S | Microhud band |

**Posture note.** Two themes change which of these roles exist at all (design
brief §7.0). **RECON AMBER / TRANSIT** lights up MICRO and TITLE and nothing
else — which makes the constraint below load-bearing rather than advisory, since
the microhud is most of that theme's UI. **BIOLUME / TABLETOP** uses every role
but places them at ~0.6 m instead of 2.5 m; because the scale is angular, *no
value in this table changes* — a 1.75° em is simply 18 mm there instead of
76 mm. That invariance is the reason the scale is specified in degrees.

**MICRO is Latin and numerals only, permanently.** Kanji at 1.2° is not small
text, it is a smudge. The microhud carries `042°`, `3.2km`, `SF7`, `12` — never
a place name. If a Japanese string needs to reach the microhud, it does not; it
goes to TITLE on the hand menu instead. This is a hard constraint on layout, not
a preference — and in TRANSIT it is the difference between a usable Japanese
build and an unusable one, because there is no third surface to fall back to.

---

## 6 · How tier R actually renders

### 6.1 The constraint that shapes it

`Texture.create(session, Path)` is the **only** texture entry point in SceneCore
1.0.0-beta01 — it takes a filesystem path. There is no `Bitmap` overload. So
anything we rasterise must be written to disk before it can be sampled.

That rules out the usual glyph-atlas-with-live-updates design, and points at a
different one that happens to suit us better.

### 6.2 Per-run rasterisation

**One text run → one PNG → one quad.** Not a shared atlas.

```
"の中継局が応答なし"  ──Paint/Canvas──▶  ARGB_8888, transparent ground
                     ──▶ cacheDir/type/<sha1(text,face,px,weight)>.png
                     ──▶ Texture.create(path)
                     ──▶ KhronosUnlitMaterial(BLEND) + quad sized to the run
```

Why this is right here and not a compromise:

- Runs are **created once and rarely change**. A callsign, a chat line, a place
  label. This is not a text editor.
- It sidesteps atlas packing, eviction, and the re-upload problem entirely.
- Cache key includes the face and pixel size, so the same string at two sizes is
  two files — correct, and cheap.
- Android's `Paint` gives us **the system font fallback chain for free**, which
  means emoji, obscure kanji, Cyrillic, and Devanagari all just work without us
  shipping a face for each. That also retires the emoji-badge workaround in
  `Callsign.kt` for tier R text (it stays for tier S).

Costs to respect: one file write + one `Texture.create` per distinct run. Both
must happen off the frame loop. A two-level cache — in-memory `Texture` by key,
on-disk PNG by key — makes relaunch nearly free.

### 6.3 Why a textured quad is not a panel

Stated plainly because it will be challenged, and should be:

- The quad's ground is **fully transparent**, so on an additive display it emits
  only the ink. There is no rectangle. Photograph it and you will not find one.
- It is **billboarded and depth-placed**, anchored to a thing in the room, not
  to the viewport.
- Material is `BLEND` with **no depth write**, so runs never occlude the
  geometry behind them and never need sorting.
- It carries **one run**, not a document. There is no scroll.

What *would* make it a panel: a background fill, a border, a fixed screen-space
position, or more than a few lines of stacked text. Those are the things banned,
and they are bannable independently of how the glyphs got there.

### 6.4 Anti-aliasing and sampling

- Rasterise at **2× the target pixel size**, generate mipmaps, sample `LINEAR`.
- **No SDF for CJK.** A signed distance field is a single distance channel; at
  kanji stroke densities the fields of adjacent strokes interfere and the gaps
  close. SDF stays available for the Latin display face, where it buys a wide
  scale range cheaply, but the CJK path is a plain alpha raster.
- Never rasterise below **48 px em**; below that, hinting artefacts dominate and
  the run should have been promoted anyway.

---

## 7 · CJK output rules

Mostly already correct in `MeshmoreXR-i18n-ja.md`; the additions:

- **No letter-spacing on CJK, ever.** Tracking is a Latin device. Applying the
  themes' `headingTracking` to a Japanese string breaks the visual rhythm of the
  em grid and reads as broken kerning.
- **No synthetic italic or synthetic bold on CJK.** Both are slanting/smearing a
  bitmap. Use the face's own weight axis or nothing.
- **No uppercase transform on a run containing CJK** — `upperHeadings` must be
  script-aware, or `ＡＢＣ` mixed with kana gets mangled.
- **Line breaking** uses `BreakIterator.getLineInstance(Locale.JAPANESE)` plus
  the kinsoku rules already specified. Never break on width alone.
- **Line length:** ≤ 30 Latin cells or ≤ 15 CJK cells per line. Beyond that the
  eye has to traverse more than ~25° to return, and the run should be spoken
  (TTS) or split across REEL entries instead.

---

## 8 · CJK input

The genuinely unsolved half. Three paths, in priority order.

### 8.1 Speech — primary

`SpeechRecognizer` with `ja-JP`. The recogniser returns **fully converted
kanji**, which means speech gets us the hard part of Japanese input for free.
This is also the most post-mobile answer available: no keyboard exists in the
room at all.

Already in the brief as a capability (TTS/STT); this promotes it from "feature"
to "the primary Japanese input method".

### 8.2 The gojūon wheel — manual entry

When speech is wrong, unavailable, or inappropriate (a quiet room, a noisy
street, a name the recogniser mangles), we need manual entry, and a QWERTY
soft keyboard floating in space is precisely the mobile artefact we are trying
to leave behind.

The 五十音 grid is **already radial**. Ten consonant rows (あかさたなはまやらわ)
× five vowels (あいうえお) is exactly the flick-input pattern every Japanese
phone user already has in their fingers — and it maps onto a spatial radial menu
without distortion:

- **Ten sectors** around a ring at HAND distance, one per consonant row.
- Dwell or pinch on a sector **expands it into five**, one per vowel.
- A **modifier ring** outside carries 濁点 / 半濁点 / 小書き.
- Latin and digits live on a second ring reached by rotating the wrist.

This is a genuinely better input surface in XR than on a phone, because the
second level can occupy real space instead of overlaying the first.

**v1 output is kana only.** Kana→kanji conversion needs a real IME engine and a
dictionary; the honest scope call is that manual entry produces かな, and anyone
who wants 漢字 speaks it. That is not a cop-out — it matches how the two methods
actually differ in effort.

**v2:** bundle a conversion engine (Mozc's core is BSD-licensed and is the
obvious candidate) behind the same wheel. Flagged as a real dependency decision,
not assumed.

### 8.3 System IME — escape hatch

For a password, a URL, an SSID: a Compose panel with the platform IME, tier P,
explicitly ugly, explicitly rare, explicitly never on the path of anything a
demo shows. It exists so that "you cannot type that here" is never true.

### 8.4 Rejected: air handwriting

Drawing kanji with a tracked fingertip is romantic and does not work. Stroke
order and stroke count are what handwriting recognisers key on, and free-air
strokes have neither reliable pen-down/pen-up nor a stable plane. Recognition
accuracy on 常用漢字 in air is poor enough that the failure mode is worse than
having no manual input at all.

---

## 9 · What replaces the scrolling list

The typographic half of "post-mobile" is not about faces at all — it is about
what happens when there is more text than fits.

| Mobile answer | MeshmoreXR answer |
|---|---|
| Scrolling list | **REEL** — an oval ring buffer on the palm; you rotate through entries, one legible at a time |
| Long message body | **TTS**, spatialised to the sender's bearing. Reading is the fallback, not the default |
| Table of nodes | **The horizon itself.** The list *is* the room |
| Settings screen | Spatial controls; labels are TITLE-size runs attached to the control, never a form |
| Toast / snackbar | **EDGE** motes and audio cues |
| Modal dialog | **FOCUS** — exactly one, gaze-spawned, explicitly dismissed |

The rule underneath: **at most one run of BODY text is legible at a time.** If a
design needs two paragraphs visible simultaneously, the design is wrong, not the
type system.

---

## 10 · Per-theme type bindings

Reusing the mobile `MmType` role model directly (`displayFamily`,
`monoFamily`, `upperHeadings`, `headingTracking`, `slashedZero`) so a skin
travels between the two apps. `wdth`/`wght` are the XR additions.

| Theme | Display | wght / wdth | Upper | Tracking | Mono | Slashed 0 |
|---|---|---|---|---|---|---|
| **HALO FIELD** *(default)* | Saira | 600 / 105 | no | 0.5 | JB Mono | yes |
| **NERV SPATIAL** | Saira | 700 / 100 | **yes** | 2.0 | JB Mono | **yes** |
| **AG-SYSTEMS** | Saira | 600 / 110 | yes | 1.5 | JB Mono | yes |
| **SEELE MONOLITH** | Saira | 500 / 100 | yes | 3.0 | JB Mono | no |
| **DR POP** | Saira | 800 / 115 | no | 0 | JB Mono | no |
| **RECON AMBER** *(Transit)* | JB Mono | **600** / — | yes | 1.0 | JB Mono | yes |
| **VECTORLINE** | *stroke only* | — | yes | 1.0 | stroke | n/a |
| **BIOLUME** *(Tabletop)* | Saira | 500 / 105 | no | 0.5 | JB Mono | no |
| **TERMINAL VOID** | JB Mono | 400 / — | yes | 1.5 | JB Mono | yes |

Two posture-driven adjustments are already folded in above:

- **RECON AMBER** goes to `wght` 600, not 500. In TRANSIT nearly all text is
  MICRO-size in the peripheral band, and §4's "smallest and most
  safety-relevant" weight floor applies to almost the whole theme.
- **BIOLUME** keeps 500 despite tabletop's shorter viewing distance, because
  angular size is unchanged (§5.4) — the glyph subtends the same angle, so it
  needs the same weight. Reducing weight because something is "closer" is the
  reflex to resist.

Three constraints that override the table:

- **CJK ignores `upperHeadings` and `tracking`** (§7).
- **CJK always uses M PLUS 1 Code**, whatever the theme's display face is. A
  theme may restyle Latin; it may not restyle Japanese into illegibility.
- **VECTORLINE** is the deliberate stroke-only theme — the "full Vectrex"
  exception. In Japanese locale it must fall back to tier R for anything with
  kana or kanji, or it cannot render the UI at all. That fallback is a stated
  part of the theme, not a bug.

---

## 11 · Honest gaps

- **The shipped M PLUS TTF is unverified.** §3 measured the web subset; confirm
  the Android artefact's ideograph count before relying on level-2 coverage.
- **Kana→kanji conversion is out of scope for v1.** §8.2.
- **Ink-density promotion is unimplemented.** §5.3 ships as the crude version.
- **Vertical writing (縦書き) remains out of scope**, as in the i18n doc.
- **Furigana is out of scope.** It would need a second baseline at ~0.5× ink,
  which is below every floor here.
- **No Korean or Chinese face is planned.** M PLUS covers Japanese kanji forms;
  Simplified Chinese and Hangul would each need their own face and their own
  floors. The system fallback chain (§6.2) will render them via tier R, unstyled
  — acceptable for a peer's name, not for UI.

---

## 12 · Sequencing

1. **T1 — Router.** Turn `Callsign.render()` into the tier S/R router (§2). No
   new rendering; strings that need R are simply logged as such. Cheap, and it
   tells us the real distribution of what nodes are named.
2. **T2 — Tier R minimum.** `Paint` → PNG → `Texture` → quad, one run, Latin
   only, with the two-level cache. Proves the pipeline without touching i18n.
3. **T3 — CJK output.** Add M PLUS, the promotion rule, kinsoku line breaking.
   Verify against the 1.8° floor with `bin/xrshot`, not by eye on a monitor.
4. **T4 — Angular scale enforcement.** Move all six roles behind an API that
   takes a role and a string and returns a size, with promotion built in.
5. **T5 — Speech input** (`ja-JP`).
6. **T6 — Gojūon wheel**, kana output.
7. **T7 —** *(decision point)* Mozc, or not.

T1–T3 are what the current work actually needs. T4 should not slip past them —
every day it does, another call site hard-codes a size.
