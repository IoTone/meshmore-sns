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

There is no companion command to set `dutycycle` on `companion-v1.17.1`:
`CMD_SET_CUSTOM_VAR` (41) reaches sensor settings only, and
`CMD_RUN_CLI_COMMAND` (66) is a later firmware (`FIRMWARE_VER_CODE` is 13
here, and the CLI passthrough needs 14). So it is a **serial provisioning
step**, once per radio.

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

## 7. What to configure on the two radios

1. **Do not invent a preset.** If either radio is meant to join a local
   MeshCore mesh, match that mesh. In North America the de facto standard is
   910.525 MHz / 62.5 kHz / SF7 / CR5, and mismatches fail silently.
2. For a private two-radio link with no community obligation, the same tuple
   is still the right default: it is what the firmware ships as the US
   suggestion, it is the most sensitive narrowband option that still keeps
   the payload moving, and 613 ms per record is workable.
3. **Coding rate is the only safe local deviation.** A private pair can run
   CR4-8 for margin without partitioning from CR4-5 neighbours.
4. **Path hash mode must match** whatever mesh is joined; for a private pair,
   1 byte is fine and costs less per packet.
5. **Set the radio's own duty cycle once**, over serial:
   `set dutycycle 1` for an EU-equivalent hard bound, or a looser value if
   chat/telemetry should keep its headroom.
6. **Transmit power**: 22 dBm is the community norm; the firmware caps at
   `MAX_LORA_TX_POWER`. More power mostly buys interference at close range,
   not range.

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
