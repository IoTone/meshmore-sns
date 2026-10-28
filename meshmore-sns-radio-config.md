# MeshCore radio configuration: what the settings actually are

Written 2026-10-24. Read from the firmware at `companion-v1.17.1`
(`d929643`, `/home/ldeen/Documents/meshcore-fw-alerts`), from the live
MeshCore preset API, and from computed LoRa time-on-air. This is the radio
half of the LDMUX-over-mesh plan. The protocol half is
`meshmore-sns-architecture.md` §5 and the facts are
`meshmore-sns-meshcore-interop.md`.

## 1. MeshCore has no radio presets in the firmware

There is no preset enum, no parameter table, and no label-to-tuple map
anywhere in the firmware. `CommonRadioPrefs.h` declares only scalar
accessors (`getFreq`/`setFreq`, `getBandwidth`/`setBandwidth`,
`getSpreadFactor`/`setSpreadFactor`, `getCodingRate`/`setCodingRate`).
The firmware stores four numbers and is told nothing else.

A "preset" is a label that lives in the MeshCore app API, fetched from
`https://api.meshcore.nz/api/v1/config`, so the project can change the
suggested list without shipping firmware. That has a consequence that
matters here: **the app's baked list can drift from the live list**, and
in MeshMore's case it had (§6).

## 2. What must match for two nodes to hear each other

| Parameter | Must match? | Why |
|---|---|---|
| Frequency | **yes** | different carrier, nothing to demodulate |
| Bandwidth | **yes** | the chirp spans a different width |
| Spreading factor | **yes** | the chirp rate differs |
| Coding rate | **no** | it is carried in the packet header, so a CR4-8 node and a CR4-5 node interoperate |
| Path hash mode | **yes** | 1/2/3-byte hashes; a node on an older mode silently drops the others |

There is **no degraded mode**. A mismatch does not degrade, it goes silent:
the radio still transmits, the app shows no error, and the node is simply
unheard. That is the single most common support issue in the MeshCore
community.

Coding rate being the exception is why a whole region can run CR4-8 while
its neighbours run CR4-5. It costs airtime (the payload portion takes 8/5 as
long) and buys decode margin.

## 3. Time on air, computed

LoRa formula, coding rate 4/5, CRC on, explicit header, and MeshCore's own
preamble rule (`preambleLengthForSF`, `src/helpers/radiolib/RadioLibWrappers.h:56`:
32 symbols at SF ≤ 8, 16 above). The payload is a 176-byte MeshCore packet,
which is `RAW_CUSTOM` carrying our 172-byte record plus header and a
three-hop path.

| Preset | MHz | BW kHz | SF | CR | Time on air | Records/hour at 1 % |
|---|---|---|---|---|---|---|
| USA / Canada | 910.525 | 62.5 | 7 | 5 | **613 ms** | 58.7 |
| USA — Southern California | 927.875 | 62.5 | 7 | 5 | 613 ms | 58.7 |
| Australia (Narrow) | 916.575 | 62.5 | 7 | 7 | 822 ms | 43.8 |
| Australia (Mid) | 915.075 | 125 | 9 | 5 | 935 ms | 38.5 |
| EU/UK (Narrow) | 869.618 | 62.5 | 8 | 8 | 1656 ms | 21.7 |
| EU/UK (Deprecated) | 869.525 | 250 | 11 | 5 | 1542 ms | 23.3 |
| Costa Rica | 910.525 | 125 | 11 | 5 | 3740 ms | 9.6 |

For reference, the same packet at SF7/BW500 is 77 ms (470 records/hour) and
at SF12/BW125 is 6824 ms (5.3 records/hour).

Two things this table corrects from earlier drafts of the plan:

- The deployable presets are **62.5 kHz narrowband**, not 125 or 500 kHz.
  The narrow choice is deliberate: it dodges periodic man-made noise in the
  ISM band and lowers the noise floor by about 6 dB against 250 kHz.
- At the preset a North American deployment actually uses, a 1 % duty cycle
  affords about **ten command operations an hour**, not zero. An earlier
  section of the architecture document claimed the link could not complete
  one operation per hour. That was computed on the wrong bandwidths and is
  withdrawn.

## 4. The radio enforces a measured duty cycle already

This is the finding that changes the governor design.

`Dispatcher` keeps a transmit-airtime budget with a **one-hour window** and
enforces it on every send (`src/Dispatcher.cpp:20-60`, `:85-120`):

```
duty_cycle   = 1 / (1 + airtime_factor)
tx_budget_ms = 3_600_000 * duty_cycle
after a send: tx_budget_ms -= measured_tx_duration_ms
if the budget is below reserve: delay the next send by needed / duty_cycle
```

- `airtime_factor` defaults to **0**, so `duty_cycle = 1.0`: no restriction
  out of the box.
- `set dutycycle <1..100>` in the CLI sets `airtime_factor = (100/dc) - 1`
  (`src/helpers/CommonCLI.cpp:450-459`), so `dutycycle 1` gives a 1 %
  budget.
- The meter uses the **measured** transmit duration (`Viair` time from
  `isSendComplete`), not an estimate.
- Over budget, it **delays** the next send rather than dropping it.

Implications:

- The radio can enforce EU-equivalent 1 % by itself, measured, with no app
  involvement. Provision it once and forget it.
- It applies to **everything that radio transmits**, including MeshMore's
  own chat, telemetry and adverts. The user's instruction was that the
  conservative budget is for LDMUX traffic only, so this cannot be the only
  mechanism: setting the radio to 1 % would throttle chat too.
- The correct split is therefore two layers: the **radio's own** budget as a
  hard outer bound covering all traffic, and the **gateway's** LDMUX-scoped
  budget inside it (§5).

**CORRECTION (2026-10-28).** An earlier version of this section said there
is no companion command to set the duty cycle. That was wrong. `CMD_SET_TUNING_PARAMS`
writes `_prefs.airtime_factor = af / 1000.0f` and `CMD_GET_TUNING_PARAMS` reads it
back (`examples/companion_radio/MyMesh.cpp`, handlers adjacent to each other,
`grep -n CMD_SET_TUNING_PARAMS`). The frame is `[set_tuning][rx_delay_base*1000
u32 LE][airtime_factor*1000 u32 LE]` and the same command also sets
`rx_delay_base`, so a client must GET first and write both back. `dutycycle 1`
(1 %) is `airtime_factor = 99`, i.e. `af = 99000` on the wire. The MeshMore
codec already encodes both (`MeshcoreFrameCodec.setTuningParams` /
`getTuningParams`); the app has **no control** for it by design
(`meshmore-sns-ux-coverage.md`). The wrong claim came from only looking at
`CMD_SET_CUSTOM_VAR` (41), which does reach sensor settings only.
Not yet verified on hardware.

## 5. Where the gateway's estimate is fine, and where it is not

The audit called the gateway's airtime meter unsound because `est_timeout`
is "only an estimate". That was half right.

- For **duty-cycle accounting** the meter only needs *our own* transmit time,
  which is the packet's time on air. That is computable exactly from the
  modem parameters and is what the firmware itself measures. Repeater
  retransmissions and collisions are other stations' airtime and do not
  count against our budget at all. So the gateway's meter is adequate.
- For **predicting a round trip** the estimate is genuinely unreliable,
  because it cannot see congestion. Timeouts must be treated as
  "no answer yet", never as "lost".

The honest wording is therefore: the meter is exact for our own airtime; the
timeout is a guess.

## 6. What MeshMore had wrong, and what it still lacks

Verified against the live API on 2026-10-24.

**Corrected in `lib/meshcore/region_presets.dart`:**

| Preset | Was | API says |
|---|---|---|
| Australia (Narrow) | CR4-5 | **CR4-7** |
| EU/UK (Narrow) | CR4-5 | **CR4-8** |
| Switzerland | CR4-5 | **CR4-8** |
| Portugal 868 | CR4-5 | **CR4-6** |
| Australia (SA/WA/QLD) | CR4-5, one entry | QLD **CR4-5**, SA/WA **CR4-8** |

**Still missing (needs new l10n keys, so it is a separate change):**

- Canada as a distinct preset (same radio tuple as USA, but a 3-byte path
  hash default since the 2026-09-09 split).
- USA — Southern California (927.875 / 62.5 / SF7 / CR5, 3-byte path hash).
- Australia (Mid), Brazil, Costa Rica, both EU 433 entries, Hungary,
  Netherlands and Netherlands (Limburg), New Zealand (Narrow), Portugal 433,
  Slovakia, Vietnam (Narrow).
- `us_arizona` (908.205 / 62.5 / SF10) is **not** in the API feed; it is a
  third-party client value and should be labelled as such.
- New Zealand points at the deprecated 250 kHz tuple, and Vietnam at the
  deprecated 250 kHz tuple, while the API carries narrow replacements as the
  current standard.

**Not supported at all:**

- **Path hash mode.** Presets in the feed specify `path_hash_size` 1, 2 or 3,
  and it must match across a mesh. The firmware exposes
  `CMD_SET_PATH_HASH_MODE` (61, `MyMesh.cpp:1466-1474`,
  `[61][0][mode]`, mode 0..2), and `RESP_CODE_DEVICE_INFO` reports the
  current value as its last byte (v10+). `packages/meshcore` models neither
  the setter nor the field, and `RegionPreset` has no field for it. A
  Canadian or SoCal peer cannot be joined correctly without this.

## 7. Your two radios, in plain terms

Two radios are involved, and they play different roles.

**Radio A — the one plugged into your phone.** Confirmed on the device,
2026-10-24, by reading MeshMore's Device configuration screen:

| | |
|---|---|
| Node name | `HELTEC-BASE` |
| Public key | `615f431f51c96375…` |
| Radio | **910.525 MHz / 62.5 kHz / SF7 / CR5 / 22 dBm** |
| Preset | USA / Canada (matches exactly) |
| Firmware | `v1.17.1-d929643`, build 14-Aug-2026 |
| Hardware | Heltec V4.3 OLED |
| BLE peer | `F8:5B:1B:BE:C5:3D` |
| Battery | 4.37 V, 100 % |

**Nothing on Radio A needs changing.** It is already at the North American
community standard, and it is hearing a live local mesh (channel 0 traffic
from several other nodes was arriving while this was checked). That last
point matters: the preset cannot be changed casually, because changing it
would disconnect this node from the mesh it is currently part of.

**Radio B — the one that would sit on your desktop.** The LDMUX daemon end
needs its own radio, and it must be configured to the **same four numbers**:
910.525 MHz, 62.5 kHz, SF7, CR5. A mismatch is not slow or degraded — the
two radios cannot hear each other at all, and nothing reports an error. If
Radio B is ever pointed at a different preset, the link silently does
nothing.

A useful way to hold this: the four numbers are the *channel the radios
speak on*, not a preference. Frequency and bandwidth and spreading factor
must be identical. Coding rate is the one exception, because it travels in
each packet's header, so CR5 and CR8 interoperate.

## 7.1 Why the old preset values were wrong

Confirmed wrong, and confirmed why.

**The evidence.** Fetched `https://api.meshcore.nz/api/v1/config` directly
(not through a summariser) on 2026-10-24. It serves 26 presets, and the
MeshCore project's own documentation says presets live on that API so they
can change without shipping firmware. Comparing entry by entry against
MeshMore's table found five discrepancies.

**Where MeshMore's numbers came from.** The file's own header says the
values are "mirrored from `github.com/zjs81/meshcore-open` and
`gotnull/socialmesh`". Fetching `meshcore-open`'s
`lib/models/radio_settings.dart` shows why that produced bad numbers: its
baked list assigns **`cr4_5` to almost every preset**, and it contains no
API fetch at all. So:

- `meshcore-open` hardcodes CR 4/5 nearly everywhere.
- The API specifies CR4-7, CR4-8, CR4-8, CR4-6 for four of those entries.
- MeshMore faithfully copied the hardcoded list, inheriting the error.
- `meshcore-open` also lacks `network_settings.path_hash_size`, so MeshMore
  never learned it exists.

And the copy was not even complete: `meshcore-open` has a "New Zealand
(Narrow)" entry that MeshMore did not take.

**What that means in practice.** Every entry MeshMore shipped with CR4-5 was
potentially wrong, because the source it copied had CR4-5 everywhere. The
five verified wrong ones are corrected. The USA / Canada entry happened to be
right, which is why your own deployment was never affected — the error only
shows up in other regions.

**The lesson for the design.** Mirroring a third-party client is a bad
provenance. The API is authoritative, the app is offline-first, so the
correct shape is a **generated** table: fetch the API, emit the Dart list,
commit the result with the fetch date. That keeps it offline-safe without
inheriting somebody else's stale snapshot.

## 8. Reading the current setting

Any of these, in order of convenience:

- **The radio's own screen** (Heltec V4.3 OLED): the companion UI shows the
  radio parameters.
- **MeshMore**: Device configuration → Radio. It reads live values from
  `RESP_CODE_SELF_INFO` and matches them back to a preset, showing "Custom"
  when nothing matches.
- **Serial CLI**: `get radio` prints `freq,bw,sf,cr`. Requires the USB
  companion build or the CLI console, not the BLE build.
- **Companion protocol**: `CMD_APP_START` → `RESP_CODE_SELF_INFO`, frequency
  and bandwidth at bytes 48-57.

**Not readable on the current hardware from this machine**: the installed
firmware is the BLE companion variant, and
`variants/heltec_v4/platformio.ini` defines `ENABLE_USB_INTERFACE` only for
`heltec_v4_companion_radio_usb` and `heltec_v4_tft_companion_radio_usb`
(`:182-190`, `:347-355`). On the BLE build, `/dev/ttyACM0` carries nothing
the companion protocol answers, so a read-only probe there returns silence
(verified 2026-10-24). The value has to come from the device screen, the
app, or a serial-capable build.

## 9. Sources

- Firmware: `src/helpers/CommonCLI.cpp` (`dutycycle`, `set radio`),
  `src/Dispatcher.cpp` (budget enforcement), `src/Dispatcher.h`
  (`duty_cycle_window_ms`), `src/helpers/radiolib/RadioLibWrappers.cpp`
  (`getEstAirtimeFor`, `calcMaxPacketMillis`), `RadioLibWrappers.h:56`
  (preamble rule), `examples/companion_radio/MyMesh.cpp` (radio params,
  self info, path hash mode), `variants/heltec_v4/platformio.ini` (USB
  interface flags).
- Preset list: `https://api.meshcore.nz/api/v1/config`, read 2026-10-24,
  26 entries.
- Interoperability rules and the narrow-band rationale: the MeshCore
  community documentation and operator guides summarised in the research
  pass, with the frequency/bandwidth/SF rule corroborated by the firmware's
  own demodulation path and the coding-rate exception by the packet header.

## 10. Private channels, and the "hog the air" question

Answered in full in `meshmore-sns-architecture.md` §5.7. Summary of the
finding, because it is a natural assumption to make:

- A MeshCore "channel" is a PSK group identified by a one-byte
  `channel_hash` inside `GRP_TXT`/`GRP_DATA` payloads
  (`src/Mesh.cpp:226-245`), **not** a separate radio channel. Every channel
  shares one frequency, bandwidth and spreading factor.
- A private channel therefore gives privacy, **not** airtime. It does not
  avoid a single collision with the public mesh.
- Channel traffic is **flooded** to every repeater, so a private channel is
  the *more* antisocial option: it broadcasts across the mesh while nobody
  can read it. It also costs 19 bytes of framing per packet against raw
  custom's zero.
- LDMUX uses direct raw custom: path-routed, unencrypted by the mesh, but
  wrapped in LDMUX's own ADR-0020 encryption. Invisible and quiet to
  neighbours.
- Genuine isolation needs **different radio parameters**, which takes both
  nodes off the public mesh — a hardware fact, not a protocol choice.
