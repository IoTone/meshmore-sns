# Device Notes

Field notes for the radios we actually run Meshmore SNS against — the
quirks, the undocumented gestures, and the things the firmware will not
let the app do.

> This page ships inside the app and is written by us, not pulled from
> upstream. Everything below was checked against the MeshCore firmware
> source; where behaviour is version-dependent it says so.

## Before you blame the app

Two rules explain most "why is it doing that" moments:

- **Anything on the radio's own hardware — buzzer, LED, screen — is
  firmware, not app.** Meshmore SNS talks to the radio over the MeshCore
  *companion protocol*, and that protocol simply has no opcodes for
  those. If a knob isn't in the protocol, no app can offer it — ours or
  anyone else's.
- **Meshtastic is not MeshCore.** The same hardware runs either
  firmware, and they share nothing but the LoRa chip. Features you
  remember from a Meshtastic app (configurable message beeps, for one)
  do not exist in MeshCore, and vice versa.

### "But the MeshCore app has a Notifications screen"

It does, and so do we — but that screen governs **your phone**, not the
radio. Per-channel notification modes, alert sounds, muting a contact:
all of it is the handset deciding what to show you. None of it reaches
across the BLE link to the radio's buzzer, because there is no command
in the protocol to carry it.

This is the single most common source of confusion, and it's worth being
precise about: a request for exactly this — an app-side do-not-disturb
that silences a T1000-E's buzzer on a schedule — was raised upstream and
closed as *completed* by the change that added the **triple-press button
toggle**. The button gesture is the maintainers' answer to "let the app
mute it." There is no app-side path waiting to be found.

---

## Seeed SenseCAP T1000-E

Our reference device. Screenless card tracker, one button, nRF52840.

Firmware target: `t1000e_companion_radio_ble` · UI module: `ui-orig` ·
BLE pairing PIN: **`123456`** (fixed at build time).

### Silencing the buzzer — triple-press the button

**Press the button three times in quick succession.** That toggles the
buzzer off, and the setting is written to flash, so it survives reboots
and battery pulls.

This is the *only* way to do it. It is not documented upstream, which is
why it's easy to miss.

A few things that make it feel like it didn't work:

- **Muting is silent; unmuting beeps.** Turning the buzzer *on* plays a
  short confirmation tone. Turning it *off* plays nothing, and the
  T1000-E has no screen to show the "Buzzer: OFF" message the firmware
  generates. The absence of the next beep is your only confirmation.
- **Don't press too slowly.** The presses have to register as one triple
  gesture. A slow third press lands as a separate single press, which
  fires a self-advert instead.
- **Two presses does something else**, and four presses toggles the GPS
  module. If you overshoot to four, you've just changed your GPS state.

Once muted, the firmware also pulls the buzzer's hardware enable line
low, so the amplifier is genuinely powered down rather than just being
told to stay quiet.

### Why it beeps at 2am but not while you're using the app

The radio only sounds an incoming-message beep **when no app is
connected over BLE**. While Meshmore SNS holds the link, message beeps
are suppressed by the firmware itself.

So the beeping you hear is almost always the radio running alone —
phone out of range, Bluetooth off, or the app killed in the background.
If your device beeps *while* you're connected, that's worth reporting;
it shouldn't happen.

### Known upstream problem: it isn't perfectly silent

Even after a successful triple-press mute, some units still emit a short
beep roughly every ten minutes once off the charger — suspected to be a
low-battery warning on a path that ignores the mute setting. This is an
open upstream bug, not something we can fix from the app.

**Workaround:** keep the unit charged. A charged T1000-E that has been
muted is quiet.

### What we cannot offer in the GUI, and why

There is no in-app toggle for the buzzer, and there cannot be one on
stock firmware. The companion protocol handler that serves our app
contains no buzzer commands at all — the buzzer preference is reachable
only from the button handler. The protocol's general-purpose
"custom variable" channel, which we already use for the GPS controls,
is wired exclusively to the sensor subsystem and cannot reach it either.

We also can't *read* the state to show you a status dot: the buzzer
preference isn't included in the device info the radio reports on
connect.

If a future firmware exposes it, the app can pick it up without a
redesign — but until then, the button is the interface.

### If you want a real software mute: TapTap firmware

There is a third-party MeshCore fork for the T1000-E, **TapTap FW**,
that adds chat-driven buzzer control — you message the device with
`/buz off` to silence it, `/buz rtttl` for ringtones, `/buz cw` to have
it beep out incoming messages in Morse. If a software-controllable
buzzer matters more to you than staying on stock firmware, that's the
option that exists today.

Two warnings before anyone flashes one:

- **The gestures are not the same.** On TapTap, *triple-press toggles
  GPS* — on stock MeshCore, triple-press toggles the buzzer and
  quadruple-press toggles GPS. Muscle memory from one will change the
  wrong setting on the other.
- **It is not the firmware we test against.** Our interop testing pins a
  specific upstream MeshCore companion build. A device on TapTap is
  outside that, and anything odd it does is ours to diagnose alone.

### Other T1000-E notes

- **Four presses toggles GPS** on and off, same persist-to-flash
  behaviour.
- **GPS polling interval isn't settable** on the firmware build we pin
  for interop testing — the device accepts the on/off flag but rejects
  the interval. The app detects this and hides the interval picker
  rather than showing a control that silently fails.
- **Reported temperature is not ambient.** The sensor sits near the
  electronics and reads warm.

---

## Seeed Wio Tracker L1 Pro

Has a screen (SH1106 OLED), which changes the buzzer experience for the
better.

Firmware target: `WioTrackerL1_companion_radio_ble` · UI module:
`ui-new`.

- **Same triple-press gesture** toggles the buzzer, and it persists the
  same way.
- **You get real feedback here.** The screen shows `Buzzer: OFF`, and a
  muted icon stays in the status bar so you can confirm the state at a
  glance later.
- **Watch the first press.** If the display has gone to sleep, the
  gesture also wakes it. Make sure all three presses land as one burst.
- **The pairing PIN is not `123456`.** Radios with a screen show a
  random PIN on their display during pairing — enter that one. The
  fixed `123456` that works on the T1000-E will fail here.

Same connection rule as the T1000-E: message beeps are suppressed while
the app is connected over BLE.

---

## Heltec V3

Firmware target: `Heltec_v3_companion_radio_ble` · UI module: `ui-new` ·
SSD1306 display.

- **No buzzer.** The Heltec V3 companion builds don't define a buzzer
  pin at all, so there is nothing to silence and no triple-press
  behaviour to learn. If you want to be alerted to messages on this
  device, that's the phone's job — configure it in the app's own
  notification settings.
- **The pairing PIN is random** and shown on the device's display, as
  with any screened radio.

---

## Adding to this page

This is our running list, and it only earns its keep if we keep feeding
it. When a device does something surprising, add it here with:

1. **What you observed**, concretely enough for someone else to
   reproduce.
2. **Which firmware build** the device was running.
3. **Whether it's fixable from the app**, or a firmware/hardware limit
   we have to document and live with.

The distinction in point 3 is the valuable part. Most of the time we
lose to a quirk, we lose it twice — once discovering the behaviour, and
again months later re-deriving whether it was ever ours to fix.
