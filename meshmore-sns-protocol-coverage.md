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
| 61 | `CMD_SET_PATH_HASH_MODE` | 1/2/3-byte path hashes this node stamps on packets it sends |
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
- Raw custom records (`CMD_SEND_RAW_DATA`, `CMD_SEND_RAW_PACKET`) stay
  available in the app's own send path: they travel as direct raw over
  whatever the radio is configured to, so a private payload needs no radio
  support beyond those two commands.

## 7. Interop matrix (APP-N7)

What is proven, against what, and what a user outside the proven set loses.
A cell is `PROVEN` only with a test name or a capture behind it; everything
else says what would prove it. The mechanism is the capability probe
(`packages/meshcore/lib/src/codec/capability.dart`): a capability is
`unknown` until a reply or a probe says otherwise, and `unknown` is refused
rather than attempted.

| Capability | Mainline companion | Two-profile companion | Degrades to | Evidence |
|---|---|---|---|---|
| Frame envelope, V1 message frames | PROVEN | PROVEN | — | `frame_codec_test.dart`, `conformance_test.dart` (golden vectors `m1`–`m6`) |
| V3 message frames (per-message SNR) | PROVEN decode, from firmware layout (`MyMesh.cpp:435-443`, `:548-556`) | PROVEN decode | An older radio answers V1 frames; the app decodes both, so the SNR cell is simply empty | `frame_codec_test.dart` (V1 + V3 cases), `interop_replay_test.dart` |
| `appTargetVer` 3 request | PROVEN | PROVEN | firmware that ignores the second byte keeps emitting V1 | `constants.dart` `kAppTargetVer`, `conformance_test.dart` |
| `0x3E` channel datagram send | PROVEN encoder + fake-transport round trip | PROVEN encoder | `kErrUnsupportedCmd` before the write, refused with the catalogue sentence | `packages/meshcore/test/channel_data_test.dart`, plus the app-side round trip in `test/meshcore/channel_datagram_test.dart` |
| Inbound `0x1B` profile/via byte | Always `0` on mainline (`MyMesh.cpp:601-602`) | Carries the receiving profile (`rxViaTag`) | Shows "not reported" rather than a fabricated profile | `inbound_push_test.dart`, diagnostics screen test |
| `CHANNEL_INFO` secret width | 16 bytes (`MyMesh.cpp:1715-1721`) | 16 or 32 | A third width is a named decode failure, not a guess | `decode` cases in `frame_codec_test.dart` |
| `0x1D` CLI reply | PROVEN decode | PROVEN decode | — | `packages/meshcore/test/cli_command_test.dart` |
| `0x91` one-key DM rejected | Not emitted | PROVEN decode (`1 + 32`, `MyMesh.cpp:2602-2611` in the two-profile tree) | The capability stays `unknown`, so the app cannot claim it will be told | `packages/meshcore/test/one_key_reject_test.dart` |
| `0x42` typed CLI whitelist | Only `get/set buzzer`, `get/set vibration` are documented as unambiguous typed operations (`docs/cli_commands.md:2716-2722`) | Same | An undocumented selector is not offered; the row stays open | `packages/meshcore/test/cli_command_test.dart` |
| `0x4A`/`0x4B` firmware OTA | Status decode only; an install consumes the offline queue to `OTA_RETAINED_OFFLINE_FRAMES` (`MyMesh.cpp:607-611`) | Same | Start is refused with its reason, never attempted | the start refusal in the package's OTA codec test |
| ATT MTU for one whole frame (179) | **UNVERIFIED** — mainline asks 176 (`src/helpers/esp32/SerialBLEInterface.cpp:29`), which is 3 short of its own largest frame | **UNVERIFIED** | The app refuses a link below 179 and shows the negotiated value; short frames still cross, and the truncation counter names what did not | `MeshcoreBle.requiredMtu`; needs a measured `mtuNow` per radio at W10 |
| Java port (`libmeshcore`) | PROVEN against the same vectors (`m1`–`m6`, pinned to `companion-v1.15.0`) | Not modelled | The port is a host-side mirror, not shipped to the phone | `libmeshcore/src/test/.../GoldenVectorsTest`, `DecodeContractTest` |

Two rows are deliberately `UNVERIFIED` rather than asserted: the MTU a real
phone negotiates with each firmware family, and whether any shipping build
emits `0x91`. Both are W10 measurements, and the matrix is where their result
lands. Until then the app's behaviour is the capability probe's: refuse, with
the reason, not attempt.

### The Java port's opcode coverage, measured 2026-11-05

`libmeshcore` is a host-side mirror of the wire contract, not shipped to the phone, and it decodes **24** of the
**45** opcodes the Dart codec models. The 21 it does not model: `0x0b`, `0x0e`, `0x0f`, `0x13`, `0x14`, `0x16`,
`0x17`, `0x18`, `0x19`, `0x81`, `0x84`, `0x85`, `0x86`, `0x87`, `0x89`, `0x8a`, `0x8d`, `0x8e`, `0x8f`, `0x90`,
`0x91` (counted with `grep -oE "case 0x.."` on `frame_codec.dart` and `MeshcoreFrameCodec.java`).

This is a named divergence, not a mis-decode: an unmodelled opcode becomes `UnsupportedFrame`, which the decode
contract already treats as "not a failure, not a message", so a Java consumer of an unmodelled push sees nothing
rather than something wrong. The golden vectors (`m1`–`m6`) still pass because they cover only the modelled set.

What closes it: adding a case per missing opcode in `MeshcoreFrameCodec.decodeBody` with the same field layout and
the same consumption rule as the Dart side, and extending the shared vector file with one frame per opcode so the
two implementations cannot drift again. Until then, anything built on the Java port (a desktop or host tool) must
treat those codes as unknown rather than assume it can read them.

## 8. Sources

- `examples/companion_radio/MyMesh.cpp` @ `companion-v1.17.1` (`d929643`):
  command defines `:30-65`, path hash mode `:1466-1473`, flood scope key
  `:1936-1945`, default flood scope `:1947-1973`, allowed repeat freq
  `:1994-2002`, radio params `:1386-1421`, repeat freq ranges `:1005-1021`.
- `examples/simple_repeater/MyMesh.cpp:434-459` — `allowPacketForward`, no
  frequency gate, no payload-type gate, no per-key ACL.
- `docs/companion_protocol.md` at `dee3e26` and `d929643`.
- `packages/meshcore/lib/src/codec/constants.dart`,
  `frame_codec.dart`, `test/network_shaping_test.dart`.
