# Radio alerts: where the beep lives, and how to silence it

_Investigation 2026-10-21. Upstream snapshots used: tag `companion-v1.17.1`
(commit `d929643`, the exact build on the owner's Heltec) and tag
`companion-v1.18.0` (current companion release). Local firmware working tree:
`~/Documents/meshcore-fw-alerts` (clone of `companion-v1.17.1`, patch applied,
nothing pushed)._

## The beep is firmware, on the radio

- Melody player: `src/helpers/ui/buzzer.cpp`. The whole translation unit is
  wrapped in `#ifdef PIN_BUZZER` (line 2) … `#endif` (line 62), so a board
  whose variant does not define that macro has no buzzer code compiled at all.
- `genericBuzzer::play()` returns immediately when `_is_quiet` is set
  (`buzzer.cpp:24`), so quiet silences every melody, including the boot and
  shutdown songs (`buzzer.h:33-34`).
- Tones: contact message, channel message and UI ack, in
  `examples/companion_radio/ui-new/UITask.cpp:767-785` (same in `ui-tiny`,
  `ui-orig`). Startup sound on boot, shutdown sound on power-off.
- **It sounds whether or not a phone is connected.** CORRECTED 2026-10-23.
  `UITask::notify()` (`ui-new/UITask.cpp:622-649`) has no `hasConnection()`
  check. The earlier claim that a paired radio is already silent was wrong:
  `:814`/`:834` gate the **display wake** in `msgRead`/`newMsg`, not the
  buzzer. A buzzer board chimes with MeshMore attached.
- Repeaters and room servers have no notification path at all
  (`examples/simple_repeater/UITask.cpp` has no `notify`/buzzer call), so only
  companion-radio builds beep.

## Which builds can beep

- 43 companion-radio envs of the 586 in `companion-v1.17.1` both define
  `PIN_BUZZER` and link `helpers/ui/buzzer.cpp` (measured 2026-10-23; method
  and the corrected earlier figure are under "How many builds can beep"
  below). Board families: Heltec V4 R8
  TFT, Heltec RC32, Seeed Wio Tracker L1 family, ThinkNode M1/M2/M5/M8/M9,
  RAK WisMesh Tag, Muzi Base / R1 Neo, Meshtiny, Meshtracker X1, T1000-E,
  T-Echo Card, Nano G2 Ultra, GAT562 30S Kit.
- `PIN_BUZZER` alone is not enough: `arduino_base`'s src filter does not glob
  `helpers/ui/`, so each beeping env adds `+<helpers/ui/buzzer.cpp>`
  explicitly. `M5Stack_Unit_C6L_companion_radio_*` defines the pin, never links
  the player, has no display/UI, and is silent despite the flag.
- **Heltec V3 and plain Heltec V4 (including V4.3 OLED) do not.** Their
  variant sets no `PIN_BUZZER`, so `toggleBuzzer()` compiles to nothing and the
  radio cannot make a sound. Only the `heltec_v4_r8_tft` config does
  (`-D PIN_BUZZER=4`, `variants/heltec_v4_r8/platformio.ini:77`).
- The owner's base radio reports `mfr: Heltec V4.3 OLED`, firmware
  `v1.17.1-d929643` (read from the app's Device configuration screen,
  2026-10-21). It is buzzerless.

## The off switch that already exists

- `NodePrefs::buzzer_quiet` (`examples/companion_radio/NodePrefs.h:30`,
  persisted as `comp.buzz_q`, line 111). Default 0 = audible.
- Applied at boot: `buzzer.quiet(_node_prefs->buzzer_quiet)` before the startup
  song (`ui-new/UITask.cpp:743-746`).
- Reached **only from the device**: triple-click runs `toggleBuzzer()`
  (`ui-new/UITask.cpp:911`, `:955`; `ui-tiny:808`, `:852`; `ui-orig:567`),
  which flips the pref, calls `buzzer.quiet()` and `savePrefs()`. On
  `HAS_DRV2605` boards the triple cycles Buzz+Vibe → Buzz → Vibe → Silent.
- Which button that is:
  - Joystick boards (`UI_HAS_JOYSTICK`, e.g. Wio Tracker L1 Pro): the
    **Menu / back button**, `PIN_BACK_BTN = PIN_BUTTON1 = GPIO13`
    (`variants/wio-tracker-l1/variant.h:27`, `target.cpp:27`), consumed at
    `ui-new/UITask.cpp:757`.
  - Other boards: `PIN_USER_BTN` (GPIO0 on Heltec V3/V4 R8, the PRG/BOOT
    button), consumed at `ui-new/UITask.cpp:770`.
  - Timing: `MomentaryButton` multi-click window is 280 ms between releases
    (`src/helpers/ui/MomentaryButton.cpp:3`). Three presses, not a hold.
- There is **no remote way to set it** in 1.17.1:
  - CLI: `MyMesh::handleCommand` handles radio prefs, `board`, `reboot`,
    `poweroff`, `set name`, `set pin`, `wifi.*`, `ver`, `tz.offset`. No buzzer.
    `docs/cli_commands.md` documents no buzzer command either.
  - Companion protocol: `docs/companion_protocol.md` has zero occurrences of
    buzz/quiet/silent, and `grep -c buzz MyMesh.cpp` is 0.

## Layers, cheapest first

| Layer | Change | Reaches | Cost |
|---|---|---|---|
| 1. Build config | `PIN_BUZZER` per variant | one board family, removes the code | per-board builds |
| 2. Prefs default + one-shot migration | `buzzer_quiet = 1`, marker key, force once on boot | every existing unit, user can re-enable | 2 files, this patch |
| 3. Device UI (exists) | triple-click | one unit at a time | none |
| 4. CLI command | add `set alerts on\|off` to `handleCommand` | serial console, and over BLE on ≥1.18.0 | ~15 lines |
| 5. App control | CMD 66 `CMD_RUN_CLI_COMMAND` + layer 4 + app toggle | the companion app | firmware ≈19 lines + app screen |
| 6. Cloud/backend | nothing exists | — | do not |

Layer 5 became cheap at 1.18.0: `CMD_RUN_CLI_COMMAND = 66` runs the same
`handleCommand()` the serial console uses and replies with
`RESP_CODE_CLI_REPLY = 29` (`MyMesh.cpp:68`, `:104`, `:1118`). 1.17.1 does not
have it. So an app-side alerts switch needs no new opcode and no protocol
version bump, only a CLI command in firmware plus an app function.

## Layer 2, implemented (option B)

Files in `~/Documents/meshcore-fw-alerts` (clone at `d929643`):

- `examples/companion_radio/NodePrefs.h` — `buzzer_quiet = 1`,
  new `alerts_default_applied` flag persisted as `comp.alerts_def`, and
  `applySilentDefault()` which forces quiet once and reports whether the caller
  should save.
- `examples/companion_radio/MyMesh.cpp` — after `loadPrefs()`:
  `if (_prefs.applySilentDefault()) savePrefs();`. This runs before the UI
  starts, and `sensors.node_lat/lon` were just seeded from prefs, so the save
  cannot zero the position.
- `examples/companion_radio/MyMesh.h` — `FIRMWARE_VERSION` becomes
  `v1.17.1-silent`, so a radio running this build is identifiable from the app.
- `test/test_companion_node_prefs/` — three native tests: default is quiet,
  a stored `buzz_q:0` is migrated exactly once, and a user who turns alerts
  back on keeps that choice across reboot.

Why a migration is needed at all: prefs are JSON (`/prefs.json`) and an
existing unit has `buzz_q:0` written in it. Changing the C++ default alone only
affects radios that never saved prefs (fresh or erased). The marker key is how
"one-time" is expressed without touching identity, contacts or channels, and
without the destructive `erase`.

`vibe_quiet` is deliberately left alone: haptic boards still vibrate.

### Built and tested (2026-10-21)

- `pio test -e native` — 43/43 pass, including the three new ones.
- `pio run -e heltec_v4_companion_radio_ble` — SUCCESS (ESP32-S3).
- `pio run -e WioTrackerL1_companion_radio_ble` — SUCCESS (nRF52840), plus
  `-t create_uf2` → `.pio/build/WioTrackerL1_companion_radio_ble/firmware.uf2`
  (866 KB, base 0x27000).
- Not flashed to any radio yet.

### Flashing, and what it preserves

- ESP32 (Heltec, T-Deck-class): USB + `pio run -e <env> -t upload`. Never
  `erase_flash`: the filesystem partition holds identity, contacts, channels
  and prefs.
- nRF52 (Wio, T1000-E, RAK, ThinkNode): double-press reset within 0.5 s, copy
  `firmware.uf2` to the UF2 drive. Do not tick "Erase device" in the web
  flasher, for the same reason.

## Open

- **Partly answered (2026-10-23):** the owner's V4.3 OLED does not beep, so
  the noise is a different unit. Still open: which one, and what firmware it
  runs. The app's own cues (`lib/cue/cue_bridge.dart`, `lib/tts/`) are a
  separate phone-side system and are already user-configurable, so they are
  not the cause of a radio in another room beeping.
- Whether to also add the CLI command (layer 4) so the setting is scriptable
  from a serial console, and later from the app on 1.18.0.
- Whether `vibe_quiet` should also default to silent for a pager-style fleet.

## Flashed to the owner's Wio Tracker L1 Pro (2026-10-21)

- The unit arrived running **Meshtastic**, not MeshCore (USB CDC debug:
  `[RadioIf] Started Tx ...`, `SX126x AGC reset`).
- Bootloader: `UF2 Bootloader 0.9.2`, `Model: Seeed TRACKER L1`,
  `SoftDevice: S140 7.3.0` — the softdevice MeshCore's `nrf52840_s140_v7`
  link script expects.
- Entered DFU with a 1200-baud touch on its CDC port (no button press
  needed). The UF2 volume mounts as `/media/ldeen/TRACKER L1` (FAT16,
  32.1 MB) once, and the Adafruit bootloader has MSC, so the volume
  disappearing while the device stays enumerated means the app started.
- Backed up the previous image first:
  `cp "/media/ldeen/TRACKER L1/CURRENT.UF2" /tmp/mmdev/wio_before_meshtastic.uf2`
  (1,908,736 bytes, md5 `f455563769971cd2ff07c4613f23a0d1`). Copy it back to a
  UF2 volume to return to Meshtastic. Meshtastic's own settings may not
  survive MeshCore's use of the flash.
- Flashed `firmware.uf2` (866,304 bytes, md5 `f35549dd35feb1f4c768002ea8471220`).
  Afterwards the device enumerates as `2886:1667 Seeed Wio Tracker L1` with CDC
  only, product string from the board package, and it exposes `/dev/ttyACM1`.
- The build's `ADVERT_NAME='"@@MAC"'` and default radio `869.618 MHz` mean it
  must be re-regioned (USA/Canada) before it can hear a 910.525 node. The app
  connection does **not** mute the chime (corrected 2026-10-23: `notify()` has
  no connection gate), so disconnecting is not required for the test. This
  patched build boots silent anyway, so hearing anything at all requires the
  first triple-click.

## The possibilities, board by board

Each physical unit falls into exactly one of these, and only two of them can
ever beep:

| # | Unit | Boot melody | Message chime | Remote control (1.17.1) |
|---|---|---|---|---|
| 1 | No `PIN_BUZZER` (Heltec V3, plain V4 incl. V4.3 OLED) | no | no | nothing to control |
| 2 | Pin defined, player not linked (M5 C6L, headless) | no | no | nothing to control |
| 3 | Buzzer, stock prefs (app attached or not) | **yes** | **yes** | triple-click only |
| 4 | Buzzer, this patched build | no | no, until re-enabled | triple-click only |
| 5 | Repeater / room server | no | no | n/a |
| 6 | Third-party fork with its own Sound menu (e.g. the L1 Pro build that ships `v1.17.104`) | fork-specific | fork-specific | fork-specific menu |

So a Heltec V3/V4 fleet never beeps (row 1). Rows 3 and 4 are the only ones
where "the radio is beeping" is true and fixable. Attaching a phone does not
silence row 3: `notify()` has no connection gate (corrected 2026-10-23).

## What the owner confirmed on hardware (2026-10-21)

- Seeed Wio Tracker L1 Pro: triple-clicking the second (Menu) button toggles
  the buzzer from any screen, which matches the code path (the handler runs in
  the UI loop, not per screen). Heltec V4.3 has no speaker, so the same press
  does nothing there.
- Both statements are consistent with §"The off switch that already exists";
  neither needs a code change.

## David's reply (2026-10-22/23) and what is still open

He answered in chat:

- "my heltek V4.3 oled no beep" — matches this document and the hardware
  evidence. That unit is row 1.
- "heltec has a beep" — some other Heltec in his fleet, unnamed. Candidates are
  a V4 TFT (Meshtastic `PIN_BUZZER=6`) or a V4 R8 TFT (MeshCore
  `PIN_BUZZER=4`). No Heltec V4.3 OLED build in this tree defines the pin.
- "the tags from seeed have a chime" — consistent with the Wio Tracker L1
  family (`PIN_BUZZER=12`, source linked). Row 3.
- "the m5unit stuff" — a category, not a verified claim about one unit. The
  only M5Stack variant here sets an inert pin on a headless build (row 2).
  What firmware those units run is still unknown.
- He also asked whether radios with speakers have a button: the Wio Tracker L1
  family does, triple-click on Menu, persisted.

Still open: exact model of the beeping Heltec, whether the Seeed tags run our
firmware or stock, and whether he wants per-board silent builds.

## Superseded: asked of David, awaiting his reply (2026-10-21)

- Which exact board model(s) the field radios are. The answer decides whether
  the complaint is row 1/3 (nothing to fix on the radio) or rows 4/5 (flash
  the patched build).
- Whether those radios are used with the companion app attached, since a paired
  radio never chimes.
- No further action until he answers. The firmware patch and the built images
  stay local.

## "The Heltec also has a beep" — checked, 2026-10-22

David answered that the Heltec beeps. The owner has never heard it. Both are
true, and they are about different things.

What the owner's radio actually is: `mfr: Heltec V4.3 OLED`, firmware
`v1.17.1-d929643`, which is `heltec_v4_companion_radio_ble` (the TFT build
would report "Heltec V4.3 TFT").

Evidence that this build cannot make a sound:

- `variants/heltec_v4/platformio.ini` defines no `PIN_BUZZER` in any env, and
  no env links `helpers/ui/buzzer.cpp` or `NonBlockingRTTTL`.
- `ui-new/UITask.h:16` only includes `buzzer.h`, and `:29` only declares the
  `genericBuzzer` member, under `#ifdef PIN_BUZZER`. `UITask.cpp:955`
  `toggleBuzzer()` therefore compiles to an empty function, and the
  "muted" icon (`:145`) is never drawn.
- The melodies live in the binaries only when that code is compiled. Heltec's
  own official MeshCore builds for this board
  (`resource.heltec.cn/download/WiFi_LoRa_32_V4/firmware/meshcore/`,
  `heltec_v4_companion_radio_ble.bin` and `heltec_v4_tft_companion_radio_ble.bin`,
  both `v1.13.0`) contain **none** of the `genericBuzzer` strings
  (`Startup:d=4…`, `MsgRcv3:d=4…`, `kerplop:d=16…`). This is the weakest of
  the arguments: it proves those two published builds are silent, not that
  the hardware is. It is consistent with the rest, nothing more.
- The V4.3.1 datasheet (16 pages, rev 1.1.0, Sep 2025) contains no buzzer,
  beep, piezo or speaker text at all (`pdftotext -layout | grep -inE
  'buzzer|piezo|speaker|beep|audio|tone'` → 0 hits), and neither does the
  V4.2.0 datasheet. Its "1.4 Components" diagram (page 7) labels every
  component on both board faces: buttons, USB-C, white and orange LEDs,
  both IPEX antenna connectors, the OLED, the pin headers, the ESP32-S3R2,
  the solar, battery and GNSS interfaces, and the power-management IC. A
  buzzer is not among them. The back-board photograph on the same page,
  rendered at 500 dpi, shows no buzzer can or piezo disc anywhere on the
  PCB. The pin tables (J2, J3, "Additional Pins") break out no buzzer pin.
- The only Heltec V4-family env in MeshCore that beeps is
  `heltec_v4_r8_tft`: `-D PIN_BUZZER=4` plus `+<helpers/ui/buzzer.cpp>`
  (`variants/heltec_v4_r8/platformio.ini:77,80`). Its model string is
  "Heltec V4 R8 TFT" (`HeltecV4R8Board.cpp:82`), not "V4.3 OLED".
- Heltec's buzzer documentation sits under the **WiFi LoRa 32 Expansion Kit**
  ("Buzzer and Sensor Configuration Guide"), i.e. an add-on board, not the V4
  main board.
- Meshtastic splits the same way. In `develop`
  (`variants/esp32s3/heltec_v4/platformio.ini`), `heltec-v4` (OLED) defines
  neither `PIN_BUZZER` nor `USE_PIN_BUZZER`, while `heltec-v4-tft` sets
  `PIN_BUZZER=6` and `USE_PIN_BUZZER=PIN_BUZZER` (`:60-61`).
- MeshCore `main` as fetched 2026-10-22 is identical to 1.17.1 here: of the
  19 `heltec_v4*` envs on `main`, **none** defines `PIN_BUZZER`. The only
  Heltec V4-family env with a buzzer anywhere in the tree is
  `heltec_v4_r8` (`PIN_BUZZER=4`). Two independent projects, same split.
- The V4 OLED board cannot be made to beep by a preference. `toggleBuzzer()`
  (`UITask.cpp:955-968`) is entirely inside `#ifdef PIN_BUZZER`, so on this
  board a triple-click does nothing and shows no alert. There is no fake
  affordance to hide, and nothing for the app to switch off.

So on this unit the beep is not muted, it is absent. Anyone who hears one is on
a board whose firmware compiled it: a Heltec V3 or T114 with a build that
defines the pin, a V4 R8 TFT, an expansion-kit buzzer, or a Meshtastic TFT
build. Their model string in the app's Device screen names which.

### Hardware absent vs code absent, kept separate

Two different claims were being run together, and they are not the same:

- **The board has no transducer.** Proven above from Heltec's own components
  diagram and pin tables, corroborated by two firmware projects that do wire
  buzzers everywhere they exist.
- **The build has no buzzer code.** Also true here, but it is a consequence,
  not the cause. A build can drop the code and a board can still be silent.
- **A GPIO can always be driven.** True and irrelevant: an ESP32-S3 pin with
  nothing attached to it makes no sound.

Two arguments used on 2026-10-21 do not support either claim and are recorded
here so they are not reused:

- The microphone recording beside the radio proves only that the radio was
  quiet for those 12 seconds. The board has no transducer at all, so a silent
  recording is the expected result on any board and distinguishes nothing.
  (The reason first given, a `!hasConnection()` gate, was also wrong:
  `notify()` has no such gate.)
- The official-binary string check proves one published build is silent. It
  says nothing about the board.

### If a buzzer were wanted on a V4.3 OLED

- `genericBuzzer::play()` calls `rtttl::begin(PIN_BUZZER, melody)`
  (`buzzer.cpp:24`), and NonBlockingRTTTL drives the pin with `tone()`, i.e.
  LEDC PWM. That wants a **passive** buzzer or piezo. An active buzzer with
  its own oscillator will click, not play the melody.
- Wiring: signal to one free header GPIO, ground to J3 pin 1, 3.3 V to J3
  pins 2 or 3. The V4.3 pin tables expose 15, 16, 19, 20, 26, 33, 40 and 41
  free of the MeshCore variant's own assignments. The pins the TFT and R8
  builds use (6 and 4) are **not** broken out on the OLED board, so copying
  their number does nothing.
- Firmware: `-D PIN_BUZZER=<pin>` plus `+<helpers/ui/buzzer.cpp>`, compiled
  per pin, so a DIY buzzer means a local build, not a setting. On the owner's
  fork the default would also have to flip, since
  `NodePrefs::buzzer_quiet = 1` now boots silent by design.
- Cost and risk: a part, a solder joint inside a closed case, and a firmware
  fork per pin. It does not make the fleet quieter, which is the actual goal.

## How many builds can beep, measured, 2026-10-23

`pio project config --json-output` resolves every env's inherited flags and
source filter, so this is the real count, not a grep:

- **586 envs** in the tree.
- **48** resolve both a `-D PIN_BUZZER=<pin>` and
  `+<helpers/ui/buzzer.cpp>`.
- **43 of those are companion builds**, which is the set that can actually
  chime (repeater and room-server UIs never reference the buzzer).

The earlier "36 of the ~200 companion envs" figure in this document was a
partial grep. It is corrected here.

## The M5Stack Unit C6L: pin yes, player no, and no link error

CORRECTION, 2026-10-23. An earlier revision of this document said the
`M5Stack_Unit_C6L_companion_radio_ble` / `_usb` envs fail to link. That is
**wrong**, and so was the probe behind it.

- `variants/m5stack_unit_c6l/platformio.ini:18` does set `-D PIN_BUZZER=11`
  and the companion envs pull in `NonBlockingRTTTL` (`:91`, `:109`) without
  adding `+<helpers/ui/buzzer.cpp>`.
- But that variant never links `examples/companion_radio/ui-new/` and never
  defines `DISPLAY_CLASS`: it has no on-device UI at all. Nothing in the
  build references `genericBuzzer`, so the missing source costs nothing and
  the firmware links and runs silent. It is a no-display companion build,
  not a broken one.
- The probe that misled me was adding `-D PIN_BUZZER=99` to a **UI** env
  (`heltec_v4_companion_radio_ble`, which links `ui-new`), where it failed
  with `undefined reference to genericBuzzer::*`. That proves only what
  happens to a UI env with a pin and no source. Resolving every env shows
  **zero** envs in that combination: `[envs with pin + ui-new + no source]`
  is empty, so there is no latent link bug anywhere in the tree.
- Consequence: the C6L is silent by construction, and its flag is inert.
  It says nothing either way about what firmware any particular C6L runs.

## Draft issue for David, written 2026-10-23, NOT posted

Held locally on the owner's instruction. Post only on their word.

**Title:** Radio buzzer behaviour across the fleet

**Body:**

We want to stop the radios beeping at home. Before changing anything I need
to know what is actually beeping.

What we know for certain:

- Chimes are firmware. MeshCore plays a boot melody, a chime on direct and
  channel messages, and a click on some keypresses.
- A build either compiles the buzzer code in or it does not. Without it, the
  board cannot make a sound regardless of what any app does.
- On a build that has it, a triple-click toggles it and the setting survives
  a reboot.
- The app cannot change it today. The protocol has no command for it, and
  neither does the CLI.

What we do not know:

- Which of your devices beep, exactly.
- What firmware and version each one is running.
- Whether they beep with a phone connected, or only standalone.
- Whether what you hear is the chime melodies or something else.

Our side: we have a local firmware change that makes buzzer boards silent by
default and lets a triple-click turn it back on. It is running on a Wio
Tracker L1 Pro. Nothing is published. We can build it for any board once we
know which boards matter.
