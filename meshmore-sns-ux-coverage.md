# UX coverage: which protocol capabilities MeshMore exposes, and why

Written 2026-10-24, after completing all 58 companion-protocol opcodes in
`packages/meshcore`. The package now speaks the whole firmware surface. The
app deliberately does not.

**Principle: protocol completeness is not a UI surface.** An opcode earns a
control only when it serves something a user is trying to do. A settings
screen that mirrors the firmware is not "complete", it is unreadable, and on
a radio link the cost of a wrong tap is minutes of airtime or a dead node.

## 1. The three rules

1. **No control without a user goal.** If the only reason to tap it is that
   the firmware has it, it stays out.
2. **Destructive or irreversible means typed confirmation, or absent.**
   Not a switch, not a dialog with a default-active OK.
3. **Secret material never enters the UI.** An export button is a
   vulnerability with a friendly label.

## 2. Exposed

| Capability | Where | Why it is there |
|---|---|---|
| Radio params (freq/bw/SF/CR) | Device → Radio | Defines the network. |
| TX power | Device → Radio | Regulatory limit, battery. |
| **Path hash size (1–3 bytes)** | Device → Radio | New. The length this radio stamps on packets it sends; nodes need not agree (corrected 2026-10-28, `Mesh.cpp:89`). It shrinks the directed-payload budget to `174 − hops × size`, which is why it is visible. |
| Preset band table | Device → Region | Fills the four numbers correctly. |
| Advert name / location / policy | Device → Identity | What other nodes see. |
| Channels | Device → Channels | Group chat. |
| Manual-add, telemetry policy, multi-ack | Device → Other params | Contact and reply behaviour. |
| Battery, firmware, manufacturer, contact/channel limits, BLE pin | Device → Device (read-only) | Support and diagnostics. |

The path-hash control is a bare `1 / 2 / 3` segmented row, not a numeric
field or a worded choice: it is a three-value decision, and worded segments
overflow the row at 1.3× text. When the selected value differs from the
radio's reported `path_hash_mode`, the helper line turns into an error
explaining that nodes with different sizes cannot forward each other's
directed traffic. That mismatch is the whole reason the control exists, so
it is surfaced before the user applies anything.

## 3. Implemented, deliberately not exposed

| Opcode | Why not |
|---|---|
| `FACTORY_RESET` | Formats the filesystem, wipes identity/contacts/channels, and disables the serial interface *before* replying, so the OK may never arrive. Would need a typed confirmation and a clear "you will lose this node's identity" boundary. |
| `IMPORT_PRIVATE_KEY` / `EXPORT_PRIVATE_KEY` | Import silently replaces the node identity. Export leaks it to any BLE-connected client, and `ENABLE_PRIVATE_KEY_EXPORT=1` is the default build (`platformio.ini:33-34`). No undo, no authentication beyond the link. Not a user-facing action in a mesh chat app. |
| `SET_DEVICE_PIN` | Persisted and applied at the next pairing with no verify step. A typo can lock the user out of their own radio. |
| `SIGN_START` / `SIGN_DATA` / `SIGN_FINISH` | A three-step signing protocol with an 8 KiB buffer. No user goal in this app. |
| `SEND_LOGIN` / `LOGOUT` / `HAS_CONNECTION` | Repeater administration. Belongs to a repeater-management flow, not a settings toggle. |
| `SHARE_CONTACT` / `EXPORT_CONTACT` / `IMPORT_CONTACT` | Wants a QR exchange flow, which is a feature, not a control. |
| `GET_ADVERT_PATH` / `SEND_PATH_DISCOVERY_REQ` | Wants a "why can't I reach this node" diagnostic in the node sheet. |
| `SEND_ANON_REQ` | Side effect: an unknown key is added as a transient contact and can evict one. |
| `GET_TUNING_PARAMS` / `SET_AUTOADD_CONFIG` / `GET_AUTOADD_CONFIG` | Advanced. `GET_TUNING_PARAMS` is the natural read-only companion to the airtime-budget story and is the next candidate. |
| `REBOOT` | Low risk, but it drops the link with no reply, which looks like a crash to the user. Needs a "the app will disconnect" confirmation to be honest. |
| `SET_FLOOD_SCOPE_KEY` / `SET_DEFAULT_FLOOD_SCOPE` / `GET_DEFAULT_FLOOD_SCOPE` | Network shaping that only matters for a multi-repeater deployment. Note the scope key is `SHA256("#name")`, so a scope name is a convention and not a secret; describing it as privacy would be wrong. |
| `GET_ALLOWED_REPEAT_FREQ` | Read-only curiosity. It also reports the *companion build's* repeat allow-list, which is not what a `simple_repeater` node may relay, so showing it invites a wrong conclusion. |

## 4. What this means for the private-network product

A network of N radios needs only the exposed set: the four radio numbers,
path hash size, and the repeater nodes flashed with `simple_repeater`
firmware. Nothing else. The remaining opcodes are diagnostic, administrative
or destructive, and adding them would not bring a private mesh any closer.

## 5. Sources

- `packages/meshcore/lib/src/codec/constants.dart`, `frame_codec.dart`,
  `lib/src/model/admin.dart`.
- `examples/companion_radio/MyMesh.cpp` @ `companion-v1.17.1` (`d929643`),
  handlers cited per opcode in `meshmore-sns-protocol-coverage.md`.
- `platformio.ini:33-34` — private-key export/import are on by default.
