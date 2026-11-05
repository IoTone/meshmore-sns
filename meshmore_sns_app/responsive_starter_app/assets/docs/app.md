# Meshmore SNS

An **offline-first companion app** for MeshCore LoRa mesh radios, paired
over Bluetooth Low Energy. No accounts, no servers, no internet
dependency — everything you see is read straight off the mesh through
your connected device.

> This page ships inside the app. The **Protocol** and **Firmware** docs
> next to it are snapshots of the upstream MeshCore documentation, cached
> for offline reading and refreshed from GitHub when you're online.

## What it does

Meshmore SNS turns a MeshCore companion radio into a social, glanceable
network you can actually see and feel:

- **Dashboard** — nodes in range, radio + location readouts, a battery
  estimate, and recent mesh activity at a glance. The device name is a
  readout: tapping it opens Device configuration, where renaming and
  re-advertising live.
- **Chat** — channel chat and direct messages, each with a delivery
  state: sent, delivered, unknown, or failed. A channel can be the
  shared public one, named by hashtag, or given a key you choose, and
  shared by QR.
- **Nodes** — every node you've heard, with message counts, tags, and
  favourites. Tap any node for identity, proximity, signal, hop path,
  and telemetry.
- **Hyperlocal grid** — ten ways to see the mesh around you: radial
  radar with range rings and a heading HUD, globe, equal grid, street
  map on the vector basemap, mesh survey, elevated terrain view,
  force-directed mesh tree, SNS cell heat map, weather, and channel
  activity.
- **Battery** — a real state-of-charge estimate from the radio's
  voltage, with a time-to-empty projection.
- **Tools** (Settings → Tools) — radio stats (noise floor, airtime),
  ping, per-hop trace, nearby-repeater discovery, a long run and a
  range test, each with an exportable result. One runs at a time, and
  the ones that send text never use the public channel.
- **Offline maps** (Settings → Offline maps) — map tiles you view are
  cached on the phone; regions can be downloaded from servers that
  allow it (USGS in the US, or your own tile server); GeoJSON event
  maps (a festival's street plan) draw over the map. One storage
  budget, and anything can be set to delete itself after a while.
  OpenStreetMap's own servers don't allow offline downloads, so OSM is
  cached only as you look at it.

## How it works

- **`MeshcoreController`** is the heart of the app: it owns the BLE
  link and speaks the MeshCore **companion radio protocol** (see the
  Protocol doc). It tracks nodes, chats, channels, telemetry, battery,
  and location, and exposes them to the UI.
- The protocol codec is a **pure-Dart package** with no Flutter
  dependencies, so the whole stack is unit-tested against a fake
  transport.
- Six views: slide sideways to change view, or use the strip under the
  app bar. A map that pans takes the drag while you are moving it, and
  the strip is always one tap away. Seven skins, and full English and
  Japanese.

## Offline-first by design

Region radio presets, device power profiles, the world map outline,
and these docs are **baked into the app** so it works with no
connectivity. The only network traffic is opportunistic: OSM map tiles
and refreshing these documentation snapshots when you happen to be
online. Your mesh data never leaves your device.

## Telemetry & sensors

The app requests and decodes telemetry from your own radio and from
contacts: GPS altitude and **environment readings** (temperature,
humidity, pressure) when the device's firmware provides them.

> **Note:** environment readings only appear if the radio's firmware
> build includes an environment sensor in its telemetry path. Many
> stock companion builds report only battery and GPS. The Firmware doc
> and the device's telemetry mode tell you what your hardware emits.

## Privacy

Meshmore SNS has no backend and collects nothing. Identities, channel
keys, message history, and tags live only in your phone's local
storage. Sharing happens over the radio, on your terms.

---

_Meshmore SNS — IoTone, Inc. Licensed MIT. Built with Flutter._
