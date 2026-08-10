# MeshmoreXR — Privacy Policy

**Last updated: 9 August 2026** · MeshmoreXR (`com.iotj.meshmore.xr`), IoTone, Inc.

## We collect nothing

MeshmoreXR does not declare Android's `INTERNET` permission and links no
networking library, so the operating system will not let it open a network
connection. There is no analytics, no advertising, no crash reporting, no
account, no login, and no identifier created for you.

There is no server. Nothing to collect data with, and nowhere to send it.

## What stays on your headset

Your messages, your per-channel voice setting, your theme, and your app settings
are kept in this app's private storage on the device. Only this app can read
them, and uninstalling removes them.

## Permissions

- **Bluetooth** — to talk to your MeshCore radio. `BLUETOOTH_SCAN` is declared
  `neverForLocation`.
- **Location** — to place mesh nodes at their true bearing around you. The app
  prefers your radio's own position; the headset's GPS is a fallback that is
  **off by default**. Broadcasting your position to the mesh is a separate
  setting. Your location never leaves the device except over your own radio, and
  only if you turn that on.
- **Microphone** — only while you are dictating a reply, from the moment you
  press SPEAK. Never in the background.
- **Hand tracking** — to let you point at and pinch controls. Processed on
  device by the Android XR runtime; never recorded.

## Two things that do leave, and are not ours

**Dictation.** Speech recognition is done by Android's own speech service, a
separate part of the operating system. We ask it to work offline
(`EXTRA_PREFER_OFFLINE`), but the system may decline — typically when no offline
language model is installed — and then it sends the audio to your device's
speech provider under **their** privacy policy. We only ever receive the
recognised text. To avoid this, install an offline speech model for your
language, or use the canned replies.

**The radio, and the air.** Messages you send go out over LoRa on a shared
public band. A direct message may be relayed by other people's equipment; a
channel message is addressed to everyone listening, and anything on the
well-known public channel key is readable by anyone in range (the app marks
those channels PUBLIC). Your MeshCore radio also stores messages in its own
firmware, which is not this app and not under our control — consult your radio's
own documentation for what it keeps.

This is how a LoRa mesh works. MeshmoreXR adds no encryption beyond MeshCore's.

## Suggested replies

Drafted replies are produced entirely on the device from a fixed set of phrases,
with no model and no network call. Nothing you receive is sent anywhere to
produce one, and nothing is transmitted without you confirming it. Off switch is
in the APP bay.

## Children

Not directed at children and not intended for anyone under 13.

## Changes and contact

If this changes, the date above changes. IoTone, Inc. — <privacy@iotone.io>
