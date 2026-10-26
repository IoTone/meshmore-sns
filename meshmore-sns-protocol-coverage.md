# Companion protocol coverage: what MeshMore uses, and what MeshCore already offers

Written 2026-10-24. Answers one question: **do we need a custom networking
layer to run a private mesh of N radios, or does MeshCore already have one?**
It already has one. The gap is that MeshMore did not expose it.

## 1. Method

- Command set extracted from the firmware the radios actually run:
  `examples/companion_radio/MyMesh.cpp` at `companion-v1.17.1` (`d929643`),
  58 `CMD_*` defines.
- Compared against the opcodes `packages/meshcore` implements,
  `lib/src/codec/constants.dart`.
- Cross-checked against the package's pin, `companion-v1.15.0`
  (`dee3e26`), by fetching that tag's `MyMesh.cpp`.

## 2. The pin is safe, and the official doc is not a spec

Two findings that change how much confidence the pin deserves.

**The protocol document is not a protocol specification.** Fetching
`docs/companion_protocol.md` at both tags shows it names **seven**
commands: `CMD_APP_START`, `CMD_DEVICE_QUERY`, `CMD_GET_CHANNEL`,
`CMD_GET_CONTACTS`, `CMD_SET_CHANNEL`, `CMD_SET_DEVICE_TIME`,
`CMD_SYNC_NEXT_MESSAGE`. The package implements 37. So the pin documents the
frame envelope and a handful of flows; everything else was, and has to be,
transcribed from firmware source.

**The pin is nevertheless sound for what we need.** Diffing the command
defines between `companion-v1.15.0` and `companion-v1.17.1` yields exactly:

- added: `CMD_DEVICE_QUERY` (22), `CMD_SEND_RAW_PACKET` (65)
- removed: `CMD_DEVICE_QEURY` (22, a typo, replaced by the above)
- renumbered: **none**

So every command the pin implies still exists at the same number on the
running firmware. No pin bump is required to use the network-shaping
commands, and there is no renumbering hazard.

## 3. Coverage

**37 of 58** opcodes implemented after this pass (was 32).

Added in this pass, all MeshCore's own network mechanics:

| Opcode | Command | What it does |
|---|---|---|
| 54 | `CMD_SET_FLOOD_SCOPE_KEY` | override the flood transport key, or send floods unscoped |
| 60 | `CMD_GET_ALLOWED_REPEAT_FREQ` | the frequencies this **companion build** may repeat on |
| 61 | `CMD_SET_PATH_HASH_MODE` | 1/2/3-byte path hashes, network-wide |
| 63 | `CMD_SET_DEFAULT_FLOOD_SCOPE` | name + key that scopes floods |
| 64 | `CMD_GET_DEFAULT_FLOOD_SCOPE` | read it back |

**21 still missing**, grouped by what they would buy:

- *Contact lifecycle*: `SHARE_CONTACT` 16, `EXPORT_CONTACT` 17,
  `IMPORT_CONTACT` 18, `GET_CONTACT_BY_KEY` 30, `GET_ADVERT_PATH` 42.
  Needed for QR-code contact exchange and for repairing a stale path.
- *Signing / identity*: `SIGN_START` 33, `SIGN_DATA` 34, `SIGN_FINISH` 35,
  `EXPORT_PRIVATE_KEY` 23, `IMPORT_PRIVATE_KEY` 24. Needed for key backup
  and for signed messages.
- *Repeater/client login*: `SEND_LOGIN` 26, `LOGOUT` 29,
  `HAS_CONNECTION` 28. Needed to administer a repeater from the app.
- *Device admin*: `REBOOT` 19, `FACTORY_RESET` 51, `SET_DEVICE_PIN` 37,
  `GET_TUNING_PARAMS` 43, `SET_AUTOADD_CONFIG` 58, `GET_AUTOADD_CONFIG` 59.
- *Path discovery / anonymous request*: `SEND_PATH_DISCOVERY_REQ` 52,
  `SEND_ANON_REQ` 57.

## 4. A private mesh of N radios, in MeshCore's own terms

No custom protocol is involved. A network is defined by five settings that
every node shares, and MeshCore's own firmware enforces the rest.

1. **Radio parameters** — frequency, bandwidth, spreading factor, coding
   rate (`CMD_SET_RADIO_PARAMS` 11). This is the only mechanism that
   actually isolates airtime from the public mesh.
2. **Path hash mode** (61) — every node must agree. It also sets the
   raw-data payload budget: `174 − hops × hashSize` bytes.
3. **Flood scope** (63) — an optional named scope that confines *flooded*
   traffic to repeaters that know the scope. Direct traffic is never scoped.
   Note the key is `SHA256("#name")`, so a scope name is a shared convention,
   not a secret.
4. **Repeaters** — nodes running the `simple_repeater` firmware. That build
   has **no frequency restriction**, unlike a companion's repeat mode
   (limited to 433.000 / 869.495 / 918.000 by
   `companion_radio/MyMesh.cpp:1005-1021`).
5. **Channels** (31/32) — optional PSK groups for group chat within the
   network.

Roles, therefore, are not roles we invent:

- a **member node** is a companion radio with those settings,
- a **repeater** is a `simple_repeater` radio with the same settings,
- the **network definition** is the five values, which is what has to be
  distributed for a new node to join.

## 5. What this means for MeshMore

The product feature is *exposing these settings and distributing them*, not
implementing networking. Concretely:

- MeshMore already sets radio parameters (`device_config_screen.dart:261`,
  `:350`) and now has encoders for path hash mode and flood scope.
- It does not yet have a way to save a set of values as a named network and
  apply it to another radio. That is the missing piece, and it is a data
  model plus UI, not a protocol.
- Nothing about LDMUX changes: it still carries records as direct raw custom
  over whatever the radio is configured to.

## 6. Sources

- `examples/companion_radio/MyMesh.cpp` @ `companion-v1.17.1` (`d929643`):
  command defines `:30-65`, path hash mode `:1466-1473`, flood scope key
  `:1936-1945`, default flood scope `:1947-1973`, allowed repeat freq
  `:1994-2002`, radio params `:1386-1421`, repeat freq ranges `:1005-1021`.
- `examples/simple_repeater/MyMesh.cpp:434-459` — `allowPacketForward`, no
  frequency gate, no payload-type gate, no per-key ACL.
- `docs/companion_protocol.md` at `dee3e26` and `d929643`.
- `packages/meshcore/lib/src/codec/constants.dart`,
  `frame_codec.dart`, `test/network_shaping_test.dart`.
