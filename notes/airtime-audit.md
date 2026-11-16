# Airtime audit — what transmits, how often, and what was undue

Scope: every path in the app that can occupy the LoRa channel, and every path that was
*charged* as if it did. Evidence is `file:line` in
`meshmore_sns_app/responsive_starter_app/lib/`, read 2026-11-14.

Airtime is **channel time on a mesh every radio in range shares**. A BLE question to the
radio in the reader's hand is not airtime, whatever it costs in battery.

---

## 1. What the app can transmit

| path | cadence | gated by | cost |
|---|---|---|---|
| Channel text / DM text | user action | airtime budget | one frame, plus radio overhead |
| Channel datagram (media chunks, place reports, voice) | user action, chunked | budget | many frames; a photo is a dozen or more |
| Self advert (`0x07`) | **off by default** (`_periodicAdvert = false`, `meshcore_controller.dart:4006`) | budget | one frame, *flooded* = repeated by every repeater |
| Advert position (`0x0E`) | only when auto-publish is configured | budget | one frame |
| Telemetry request (`0x27`) | **the poller**, see §2 | budget | one request **plus one reply per peer** |
| Status / trace / ping / raw (`0x1B`, `0x24`, `0x19`, `0x41`, `0x32`, `0x37`) | user action (tools) | budget | one frame, trace multiplies by hops |
| Local requests (`0x01` app start, `0x04` contacts, `0x05` time, `0x0A` queue drain, `0x14` battery, `0x1F` channel, `0x28` custom vars, config writes) | on connect and a timer | **not airtime** | BLE only |

The grid's "play" interval (`grid_screen.dart:585`) only re-reads the local node list, so
it transmits nothing. The battery poll (`meshcore_controller.dart:3829`) is local too.

## 2. Found: telemetry polling was on by default, every 10 s, on any tab

`_telemPollEnabled = true` (`:4503`), `_telemPollInterval = 10 s` (`:4505`), and the only
guard was `_visible` — which means *the app is in the foreground*, not *somebody is looking
at readings*. A reader on the chat tab was asking every eligible peer for temperature and
humidity six times a minute, and **every answer is a LoRa transmission by that peer** on the
shared channel. With ten peers that is 3 600 answers an hour that nobody read.

Fixed:
- The interval is 60 s. A minute is still fresher than the sensors behind it change.
- Interest is now a screen saying it is showing readings: `holdTelemetryInterest()` /
  `releaseTelemetryInterest()` (`meshcore_controller.dart`), refcounted, held by
  `WeatherView` (`weather_view.dart`). With no interest there is no timer at all, so the
  app on the chat tab transmits nothing.
- Tests: `test/meshcore/telemetry_interest_test.dart` — no interest means no request
  however long the app is open; interest asks; releasing stops; interests are refcounted.

## 3. Found: the poller skipped peers on a three-byte mesh

`_telemPollTierFor` used `n.outPathHashes.length` as the hop count (`:4599`). A path is
`hops × width` bytes, so a three-byte, two-hop peer read as six hops, fell past both tier
limits and was skipped by the rule that should have polled it. That is *under*-transmission
and a correctness bug: it is also why the weather list could look empty on a network with
3-byte hashes. Fixed to `n.hopCount`, which is decoded from `PathLen`.

## 4. Found: the airtime meter charged frames that never leave the radio

Every frame went through `send()` and was charged (`:1377` onward), with a comment saying
that charging everything "keeps the figure honest". It does the opposite: a contacts sync of
400 contacts, channel probes, a battery poll a minute and every config write were counted as
channel time. The meter is what refuses the reader's next message when the window is full, so
the effect was **undue refusal of real traffic**, not just a wrong number.

Fixed: `MeshcoreController.isOverTheAir(opcode)` classifies the codec's transmitters
(text, datagram, advert, advert position, telemetry/status/trace/control/raw) and only those
are charged. An unknown opcode is treated as local, deliberately: a frame wrongly charged
takes airtime away from messages, while one wrongly uncharged only understates a number.
Tests: `test/meshcore/airtime_accounting_test.dart` (battery read free, channel message
charged, advert charged, the classifier's two lists, empty frame harmless).

## 5. Still open (not fixed here)

1. **No cap on how many peers one poll may ask.** The poller sends one request per tick and
   picks the cheapest tier, so it is rate-limited by the tick, but there is no per-minute
   ceiling if the interval is ever lowered again. Worth a counter beside `airtimeRefusals`.
2. **Advert flooding is the most expensive thing a reader can do with one tap.** A flooded
   advert is re-transmitted by every repeater in range; the app charges it one frame. The
   budget estimator is a proxy for the reader's own radio, not for the mesh's total cost,
   and nothing warns about that.
3. **Position auto-publish cadence** is a stored preference; its interval is not reviewed
   here and it is a LoRa frame each time. Read `LocationSettingsScreen` and the publish
   timer before changing anything.
4. **Media chunks** are individually charged (each is a datagram), so the meter is right,
   but a photo's total is not shown to the reader *before* they send it. `MediaSendSize`
   states bytes, not airtime.
5. **Trace requests multiply by hop count** (the reply gathers per-hop SNR), and the tools
   show no estimate. One tap on a deep route is the largest single airtime spend in the app.
