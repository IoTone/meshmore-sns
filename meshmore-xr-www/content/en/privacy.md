---
title: "Privacy Policy"
description: "Meshmore XR collects nothing. Here is what that means, precisely."
date: 2026-08-14
lastmod: 2026-08-14
url: /privacy/
---
**Effective 14 August 2026** · applies to Meshmore XR (`com.iotj.meshmore.xr`)
by IoTone, Inc. This page is the policy of record for the app; the same text
ships inside the repository as `PRIVACY.md`.

## The short version

Meshmore XR is an off-grid mesh radio companion for AR glasses. **It has no
network access at all** — the app does not declare Android's `INTERNET`
permission, so the operating system will not let it open a connection. There
is no server, no account, no analytics, no advertising, no crash reporting,
and no identifier created for you. We cannot collect your data, because we
built an app with nothing to collect it with and nowhere to send it.

Everything below is detail on that one fact, plus honesty about the two
channels that *do* carry your information — your own LoRa radio, and your
device's speech service — neither of which reports to us.

## What stays on your device

Stored in the app's private storage, readable only by this app, removed by
uninstalling:

- your messages and conversation history (erasable any time: **SETUP → APP →
  ERASE**; the erase asks twice and cannot be undone);
- your favourites and tags for mesh nodes;
- your settings: theme, region preset, per-channel read-aloud, headset-GPS
  fallback, location sharing, channel-send authorisation, telemetry
  permissions, suggested-replies switch;
- a remembered table position for the tabletop view (an anonymous spatial
  anchor ID with no location meaning outside your headset's own room map).

We never see any of it.

## Permissions, and exactly why

| Permission | Why | Limits |
|---|---|---|
| **Bluetooth** | To talk to *your* MeshCore radio over BLE. | `BLUETOOTH_SCAN` is declared `neverForLocation`. |
| **Location** | To place mesh nodes at their true compass bearing around you. | The app prefers your radio's own GPS. The headset's location is a fallback that is **off by default** and one switch to turn off again. Used on-device for bearing arithmetic only. |
| **Microphone** | Dictating a reply. | Listens only from the moment you choose SPEAK until the dictation ends. Never in the background. The in-app rule is printed on the safety card: *mic on only when you speak*. |
| **Hand tracking** | Pointing and pinching controls. | Processed on device by the Android XR runtime; never recorded, never stored. |
| **Scene understanding (coarse)** | Finding a real table so the tabletop map can sit on it. | Plane detection runs on device in the XR runtime. The app receives a surface position, not imagery. No camera frames ever reach the app. |

## What leaves the device — only over your own radio, only on your action

Meshmore XR's entire output path is the Bluetooth link to **your** MeshCore
radio, and from there the open LoRa band. Plainly:

- **Messages you send** travel over a shared public radio band. Direct
  messages may be relayed by other people's equipment. Channel messages are
  addressed to everyone holding that channel's key, and the well-known public
  channel is readable by **anyone in range** — the app labels it PUBLIC and
  warns before you join. Channels created by spoken tag are private the way an
  unlisted phone number is private (the app says so at creation): the key is
  derived from the name, so anyone who guesses the name is in.
- **Your position** is broadcast to the mesh **only** if you enable "share my
  location" — a separate switch from using location, off by default. The
  broadcast is unencrypted, like all mesh position adverts.
- **Telemetry about your radio** (battery, position, environment sensors) is
  disclosed to other nodes only per the *Who may ask about me* setting —
  three classes, each deniable, defaulting to whatever your radio was
  configured with. Requests the app makes to *other* people's nodes are
  single, manual, and user-initiated — never scheduled, never swept.
- **Transmit is conservative by design.** Sending on channels is off until
  explicitly enabled (asked twice), and this build only addresses direct
  messages to the operator's own registered hardware.

This is how a LoRa mesh works. Meshmore XR adds no encryption beyond
MeshCore's, and claims none. Your radio's firmware also stores messages
itself; that storage is governed by the radio, not by this app.

## The one third-party service: speech recognition

Dictation uses Android's own speech recognizer — part of your operating
system, not of this app. We request offline recognition
(`EXTRA_PREFER_OFFLINE`); if your device has no offline model installed, the
system may send the audio to your device's speech provider **under that
provider's privacy policy**. The app receives only the recognised text.
To keep speech fully on-device, install an offline speech model for your
language, or use the canned replies — which are a fixed phrase list chosen on
device, no model, no network, nothing sent without your explicit confirm.

## Radio compliance is yours (and we say so in-app)

Region presets are community-maintained convenience, **not legal advice** —
the app's ABOUT screen carries this in every supported language. In Japan
in particular, lawful use requires the *hardware* to bear 技適 (Giteki)
certification; settings alone are not sufficient, and many imported boards
are not certified.

## Your rights, without a form

Because nothing is collected, there is nothing for us to disclose, correct,
export, or delete on a server — the GDPR/APPI answer to "what do you hold
about me" is **nothing**. Everything the app knows lives on your device under
your control: erase messages in-app, clear the app's storage, or uninstall.

## Children

Not directed at children, and not intended for anyone under 13.

## Changes

If this policy changes, the date above changes, and material changes will be
noted in the app's release notes. Continued use after a change is acceptance.

## Contact

IoTone, Inc. · <privacy@iotone.io> · https://meshmorexr.iotj.cc
