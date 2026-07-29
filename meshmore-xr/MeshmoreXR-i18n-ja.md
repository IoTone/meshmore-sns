# MeshmoreXR — Japanese & English

**Japan is a launch market for the target hardware.** Japanese is a first-class
requirement from day one, not a localization pass bolted on before release.

Implemented in `airspace-ui/src/airspace/i18n.js`; verified by `npm test`.

---

## 1. The load-bearing finding: CJK needs a larger angular floor

The 1.2° text floor in `AiRspace-UI.md` L7 is derived from **Latin** letterforms,
which carry roughly 2–4 strokes per glyph. It does not transfer.

A kanji such as 態 carries **14 strokes in the same em box**. At 1.2° of visual
angle every one of those strokes must survive both the display's pixel grid and
the eye's acuity limit, and they do not: the glyph becomes a grey smudge —
legible as "there is text here" and nothing more. The floor scales with **stroke
density**, not with glyph count.

| Script | Floor | At 1.4 m |
|---|---|---|
| Latin | **1.2°** | ≈ 29 mm |
| Kana (かな / カナ) | **1.5°** | ≈ 37 mm |
| Kanji (漢字) | **1.8°** | ≈ 44 mm |

**The densest glyph in the string sets the floor.** Mixed kana+kanji is the norm
in Japanese and one unreadable kanji ruins the line, so `ティア1` (pure katakana)
sits at 1.5 while `無線機` is promoted to 1.8. This is enforced in code — a caller
asking for 1.2 on a kanji string *gets* 1.8, because the request is a floor
request, not a grant:

```js
const effDeg = minDegFor(text, deg);   // promotes, never demotes
```

**Practical consequence:** a Japanese UI is physically bigger than the same UI in
English. Layouts must be designed at the JA size and allowed to look airy in EN,
never the reverse. Designing at EN size and "checking JA later" guarantees a
rebuild.

## 2. Monospace CJK is double-width

A label box sized for `SETTINGS` will not hold `設定` at the same advance count —
the character count went *down* and the width went *up*. Every layout measures;
none assumes. This is why `makeLabel()` measures the actual string on a canvas
rather than estimating from `text.length`.

## 3. Tofu is the failure mode that ships

Canvas text falls back **silently**. A missing face renders boxes, throws
nothing, logs nothing, and passes every test that only checks "did it render."
Worse, the fallback happens on the first frame and the texture never repaints, so
it survives a later font load.

Two defences, both required:

1. **Resolve the face before the first build** — `await loadFonts()` ahead of any
   label construction, explicitly loading a CJK sample string (`document.fonts.load`
   with only a size does not guarantee the japanese subset).
2. **Assert it in CI** — the smoke test checks `document.fonts.check(..., '設定')`
   *and* measures a kanji advance, because a fallback font resolves the check but
   produces a visibly different metric.

## 4. Font

**M PLUS 1 Code** (OFL). One family covers monospace *and* full Japanese, which
is exactly why the SNS brief picked it: it serves the console/telemetry layer,
JA localization, and the Wipeout "kanji-as-graphic" motif without a second
license to clear.

| Subset | woff2 |
|---|---|
| latin | 9 kB |
| japanese | **616 kB** |

On Android, bundle both as APK assets for a guaranteed offline baseline — the UI
must never show raw keys or tofu because the network is gone. 616 kB is a real
but acceptable cost for an offline-first app; the alternative is a device font
that may not exist.

## 5. What does *not* translate

Deliberately Latin in every locale:

- **Callsigns and node names** — they are identifiers on the wire.
- **Units and numbers** — `340m`, `-71dBm`, `042°`, `SF7`, `915.0`.
- **Protocol tokens** — `CH0`, `PTT`, `TX`.

Mixing scripts inside one telemetry line is correct here, not sloppy: the reader
needs the number, and transliterating `dBm` into katakana helps nobody.

## 6. Line breaking (kinsoku shori, 禁則処理)

Japanese does not use spaces, so a naive break lands anywhere. The minimum
viable subset, implemented in `wrapJa()`:

- **Never start a line with** `、。，．）」』】〉》”’ヽヾー` or a small kana
  (`ぁぃぅぇぉっゃゅょゎヵヶ`) or `！？`
- **Never end a line with** `（「『【〈《“‘`

Full kinsoku is a deep well; this subset removes the breaks that read as broken
rather than merely suboptimal.

## 7. Locale switching

Switching locale rebuilds every text texture. That is cheap here (canvas
textures) and correct: the SNS app learned that switching after panels are built
requires rebuilding them anyway, and a reload was the reliable path.

Fallback chain: **locale → en → the raw key**. Never blank — on a device you are
wearing, the key itself (`station.radio`) is a useful debugging indicator.

## 8. Vertical writing (縦書き)

Not used for body text, and not needed. Worth noting as a **graphic** option for
NERV SPATIAL, where vertical Japanese running down a panel edge is period-correct
for the reference and would be a genuine differentiator. It must never carry
information that is not also available horizontally.

## 9. Honest gaps

- **The JA strings in `i18n.js` are my translations and need a native review**
  before they go near a build. They are plausible and consistent, which is not
  the same as idiomatic. `送信待ち` for "queue" and `停波` for "dark" in particular
  are choices I would want argued with.
- **TTS/STT for Japanese** is specified in the audio brief but not prototyped.
  Vosk has a JA model; Android's on-device recognizer supports ja-JP. Neither is
  verified here.
- **Sorting and search** in Japanese (kana ordering, romaji input matching) is
  unaddressed. It matters much less in this app than most, because bearing —
  not alphabetical order — is the primary index.
- **The floors in §1 are reasoned from stroke density, not measured on the
  device.** They are conservative and defensible, but the honest test is a
  legibility check on real hardware in real sunlight, which nobody has run yet.
