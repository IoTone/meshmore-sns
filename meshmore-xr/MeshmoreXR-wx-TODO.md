# MeshmoreXR — WEATHER IN THE SKY: how SNS does it, and what XR should do

**Status: SPEC READ, NOT BUILT. 22 August 2026.** The operator's instruction was
"the algorithm is to monitor the public channel for weather statements, and
weather statements that can be tied to a location — we can put weather icons
into the sky around the areas where this information is reported", and to go and
read how Meshmore SNS did it first. This is that read, against the source rather
than from memory, so the XR version inherits the parts that were already
thought through instead of re-deriving them badly.

Everything below is what SNS **actually ships**, with file references. Where the
design document and the code disagree, the code wins and it is noted.

---

## 1. It is two independent signals, and only one of them costs anything

`weather_view.dart` shows measured sensor telemetry AND weather mined from chat.
The mined half is the one that matters here: its own note says it is *the only
weather signal when the firmware reports no environment sensor, so it always
shows*. It costs no airtime, needs no permission, and works with the radio off —
the same argument that made Meshbook worth building first.

The measured half is already half-built in XR (`TelemetryAsk`, the WX bay) and
is blocked on other people's radios shipping with every telemetry class set to
DENY. **The chat-mined half has no such blocker.**

---

## 2. The lexicon — `lib/sns/weather_lexicon.dart`

Nine conditions, each with a glyph, which is exactly what a sky icon needs:

| condition | glyph | English terms (verbatim) |
|---|---|---|
| clear | ☀ | sun, sunny, sunshine, clear, blue sky, bluebird |
| clouds | ☁ | cloud, clouds, cloudy, overcast, grey sky, gray sky |
| fog | 🌫 | fog, foggy, mist, misty, haze, hazy |
| rain | 🌧 | rain, raining, rainy, drizzle, downpour, shower, showers, wet |
| snow | ❄ | snow, snowing, snowy, sleet, hail, flurries, blizzard |
| wind | 🌬 | wind, windy, gusty, breezy, gale, blustery |
| storm | ⛈ | storm, stormy, thunder, thunderstorm, lightning, typhoon, hurricane, cyclone |
| heat | 🔥 | hot, scorching, sweltering, muggy, humid, heatwave, baking |
| cold | 🧊 | cold, freezing, frigid, chilly, frosty, frost, icy |

Japanese is a parallel list, not a translation of the English one: 晴れ・快晴・
日差し・青空 for clear, 曇り・くもり・雲 for clouds, 霧・もや・かすみ for fog,
雨・小雨・大雨・にわか雨・土砂降り for rain, and so on. **This app already ships
in both languages, so the JA list comes along or the feature is English-only in
a Japanese build.**

Plus 18 locale-independent **emoji** (☀🌞🌤 ☁⛅🌥 🌫 🌧🌦☔ ❄🌨☃ 💨🌬 ⛈🌩🌪), which
matter more here than anywhere: on a mesh people type 🌧 far more often than
they type a sentence about rain.

**Matching rules that exist to stop false positives:**

- English matches on a **word boundary** regex, so "sun" does not fire on
  "Sunday". Japanese matches by substring, because it has no word boundaries.
- **Negation.** English negators (`no, not, without, n't, never, hardly`) are
  looked for in the **16 characters before** the match; Japanese negators
  (`ない, ません, じゃない, ではない`) in the **8 characters after**. A hit drops
  that condition outright.
- Temperature needs a **unit marker** — `°C ℃ °F ℉ degrees celsius/fahrenheit °
  度` — so "see you at 28" is never a temperature. Ranges (`18-22°C`) yield both
  endpoints. Fahrenheit converts. Spelled-out numbers do not parse.

---

## 3. The scan — `lib/sns/weather_inference.dart`

`scan(text, languageCode, at, sourceMsgId) → WxObservation?`, and `scanAny`
which runs both languages and merges (channels are mixed-language).

**Confidence is a MAX, never a sum:**

| evidence | confidence |
|---|---|
| emoji | 0.90 |
| rain / snow / fog / storm term | 0.80 |
| clear / clouds / wind term | 0.70 |
| heat / cold term | 0.55 |
| a parsed temperature | floors it at 0.85 |
| temperature **and** a condition | +0.10, clamped to 1.0 |

Heat and cold score lowest deliberately: "hot" and "cold" are qualitative and
get said about coffee, arguments and people. Concrete nouns are trusted more.

**The 0.5 threshold lives in the callers, not the engine** — which means an
XR caller picks its own, and should probably pick a higher one, because a wrong
icon hanging in the sky is more assertive than a wrong chip in a list.

An observation carries: conditions (a set — one message can say several),
`temperatureC` (the **mean** of every temperature in the message), confidence,
`at`, `sourceMsgId`, an ≤80-character `sourceSpan` of the text, and optionally
lat/lon/placeName.

---

## 4. Placing it — the part XR needs most

Two sources, in priority order, memoised per message id:

1. **A place name in the text**, resolved by `PlaceInferenceEngine` against a
   **GeoNames cities≥15000 gazetteer** bundled as `assets/data/cities15000.bin`.
   Cues are graded: a coordinate 0.95, a Maidenhead grid square 0.9, "hello
   from X" 0.65, "heading to X" 0.55, "near X" 0.5, a bare name 0.45; bonuses
   for an exact match, being in region, population ≥100k, and being unique.
   Minimum confidence **0.80**, and anything beyond **300 km** is dropped —
   the feature is hyperlocal on purpose.
2. **The sender's node GPS**, by parsing the `"name: "` prefix and matching a
   known node by name — and **refusing when more than one node matches**,
   because names on a mesh are neither unique nor authenticated.
3. Otherwise **unlocated**: it still counts toward the ambient summary but gets
   no place, because *wrong placement is worse than no placement*.

Clustering (`aggregateMicroclimates`) buckets located observations into a
**0.05° grid cell (~5.5 km)**, takes the dominant condition per cell by a
strictly-greater scan, the most common place name as the label, min/mean/max
temperature, and the **centroid** of the group as its position. Sorted by
mention count.

A cluster is then enriched with a **measured** temperature from any node with
environment telemetry within **5 km** (`_measuredTempNear`), and the UI prefers
the measured number and marks it `✓measured`.

---

## 5. What XR should do differently

**The sky is the point.** SNS renders these as a wrap of chips because a phone
has no sky. This app has a horizon with true bearings, range rings and altitude,
and a cluster already carries a centroid — so the natural drawing is the
condition's glyph at the cluster's **bearing and distance**, sitting above the
horizon rather than in a list. That is the whole reason to port it.

Consequences to decide before building:

- **Elevation encodes nothing yet.** Distance is already the ring; height above
  the horizon is free, and could carry temperature, recency, or confidence. It
  should carry exactly one of them, and the choice should be stated.
- **Confidence should be visible, not just thresholded.** A 0.55 "it's hot in
  here" and a 0.95 coordinate-tagged downpour must not draw identically. Alpha
  or size, never colour alone (§S4).
- **Ageing.** SNS reprocesses a fixed 24 hours on open; the design doc wanted a
  decaying store and it never landed. In the sky, stale weather is worse than
  on a phone — it looks like now. An icon should fade with age, and the window
  probably wants to be shorter than 24 h.
- **No gazetteer is bundled here.** `cities15000.bin` is a real asset with real
  size; §1.2's "zero assets" rule was about audio, but the same question
  applies. The cheaper first cut is source (2): the SENDER's node position,
  which this app already has for 300+ peers and which needs no gazetteer at all.
  Place names in text can come later.
- **Both languages from the start.** The lexicon is bilingual in SNS and this
  app ships in two locales; an English-only miner would be a surface that goes
  quiet in a Japanese build.

**Suggested first cut:** the sender's own position, the emoji lexicon plus the
strongest English and Japanese terms, a confidence floor above SNS's 0.5, a
window of a few hours, one glyph per 0.05° cell drawn on the horizon at its
true bearing, fading with age. No gazetteer, no place-name parsing, no
temperature — those are the second cut, and each is separable.

---

## 6. Where the parts are

| what | where |
|---|---|
| lexicon, glyphs, temperature regex | `meshmore_sns_app/…/lib/sns/weather_lexicon.dart` |
| scan, confidence, aggregation, clustering | `…/lib/sns/weather_inference.dart` |
| place cues and scoring | `…/lib/sns/place_inference.dart` |
| gazetteer | `…/lib/sns/city_gazetteer.dart`, `assets/data/cities15000.bin` |
| locating + microclimate assembly | `…/lib/meshcore/meshcore_controller.dart` (`microclimatesFor`, `_measuredTempNear`) |
| the phone surface | `…/lib/screens/weather_view.dart` |
| the original design | `meshmore-sns-microclimate-wx.md` |
