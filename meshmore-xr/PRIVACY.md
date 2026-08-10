# MeshmoreXR — Privacy Policy

**Last updated: 9 August 2026**
**Applies to:** MeshmoreXR (`com.iotj.meshmore.xr`), published by IoTone, Inc.

MeshmoreXR is a companion app for a MeshCore LoRa mesh radio, for Android XR
glasses. This policy describes exactly what the app does with data. It is short
because the app does very little.

---

## The short version

**MeshmoreXR has no internet access.** The app does not declare Android's
`INTERNET` permission, so the operating system will not let it open a network
connection even if it tried. It contains no analytics, no advertising, no
crash-reporting service, and no third-party SDK that collects anything.

Nothing you do in this app is sent to IoTone, and there is no server for it to
be sent to.

Everything the app knows stays on the headset or goes out over your own radio.

---

## What the app stores, and where

All of it is in Android's private app storage on your device, readable only by
this app, and removed when you uninstall it.

| What | Why | Where |
|---|---|---|
| Messages you have received and sent | So your conversations survive closing the app | On the device |
| Which conversations read themselves aloud | Your per-channel voice setting | On the device |
| Your chosen theme | So the app looks the way you left it | On the device |
| App settings (location use, diagnostics, channel sending, suggested replies) | So they survive a restart | On the device |

There is no account, no sign-in, and no identifier created for you by this app.

---

## Permissions, and what each is actually for

**Bluetooth (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`)** — to find and talk to your
MeshCore radio. `BLUETOOTH_SCAN` is declared `neverForLocation`: the app does not
use Bluetooth scanning to work out where you are.

**Location (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`)** — to place other
mesh nodes at their true compass bearing around you, which requires knowing
where you are.

- The app prefers the position reported by **your own radio**.
- The headset's own GPS is used **only as a fallback**, **only if you switch it
  on**, and it is **off by default**. It is in the APP bay as USE HEADSET
  LOCATION.
- Sharing your position **with the mesh** is a separate setting (SHARE MY
  LOCATION). Broadcasting a position puts it on the air unencrypted to anyone in
  radio range. That is a property of the LoRa mesh, not of this app, and it is
  why the two settings are kept apart: using a fix to draw bearings on your own
  display never implies transmitting it.
- Your location is never sent to IoTone or to any server, because the app cannot
  reach one.

**Microphone (`RECORD_AUDIO`)** — only to dictate a reply, and only from the
moment you press SPEAK. The app never listens in the background, and the
permission is requested the first time you reach for dictation rather than at
startup.

> **One honest caveat about dictation.** Speech recognition is performed by
> Android's own speech recognition service, which is a separate part of the
> operating system, not code in this app. MeshmoreXR asks it to work **offline**
> (`EXTRA_PREFER_OFFLINE`), but that is a preference the system may decline —
> for example if no offline language model is installed on your device. When the
> system chooses to recognise speech in the cloud, that transfer is between your
> device and your device's speech provider (typically Google), under **their**
> privacy policy, not ours. We never see the audio or the transcript leave the
> device, and we receive only the recognised text.
>
> If this matters to you, install an offline speech model for your language in
> Android's settings, or use the canned replies instead of dictation.

**Hand tracking (`HAND_TRACKING`)** — to let you point at and pinch the app's
controls. Hand and head tracking data is processed on the device by the Android
XR runtime, used to position things in front of you, and never recorded or
transmitted by this app.

---

## What goes out over the radio

When you send a message, it is transmitted by your MeshCore radio over LoRa. You
should assume that:

- A **direct message** is addressed to one node but travels over a shared
  public radio band and may be relayed by other people's equipment.
- A **channel message** is addressed to everyone listening on that channel. The
  app will not send one at all unless you explicitly enable SEND ON CHANNELS in
  the APP bay, and confirm it twice.
- Messages on the well-known **public** channel key can be read by anyone in
  range. The app marks such channels PUBLIC wherever it lists them.

This is how a LoRa mesh works. MeshmoreXR does not add encryption beyond what
the MeshCore protocol itself provides.

## Suggested replies

The app can offer a drafted reply based on the message you are reading. This runs
entirely on the device with no model and no network call — it reads the message
for intent and picks from a fixed set of drafts. Nothing you receive is sent
anywhere to produce it. A suggested reply is always marked as generated and is
never transmitted without you confirming it. It can be turned off in the APP bay
(SUGGEST A REPLY).

## Children

MeshmoreXR is not directed at children and is not intended for use by anyone
under 13.

## Changes

If this policy changes, the date at the top changes with it. Because the app
collects nothing, any change here will be about what the app *does*, not about
what we do with data about you.

## Contact

IoTone, Inc. — <privacy@iotone.io>
