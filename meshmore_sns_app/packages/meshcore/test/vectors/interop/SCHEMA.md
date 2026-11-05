# Interop fixture schema (M6)

Drop **real captured** device data here as `*.json` files. The
`test/interop_replay_test.dart` harness picks them up automatically:
absent → the test is skipped (CI stays green); present → it asserts
our codec/crypto against the real device and resolves the
channel-secret tail.

**Never hand-write or synthesise these — they must come from a real
capture** (see `meshmore-sns/M6-interop-runbook.md`). The capture's own
decode is the expectation the test compares against, so a fixture that was
produced by this codec proves nothing and must not be committed.

## `ota_advert_capture` — everyday framing + advert conformance

```json
{
  "kind": "ota_advert_capture",
  "captured_at": "2026-10-10T17:20:35.961",
  "capture": "what was running, where",
  "snr_db": -16.0,
  "rssi_dbm": -103,
  "route_code": 2,
  "sender_key_hex": "26f607…",
  "sender_name": "WIOld",
  "advert_lat": 45.63811,
  "advert_lon": -111.104321,
  "rf_log_payload_hex": "c0991200…"
}
```

`rf_log_payload_hex` is the `PUSH_CODE_LOG_RX_DATA` (0x88) **payload**
without the opcode — `[SNR×4][RSSI][OTA packet …]`. Prepend `0x88` to get
the notification the radio sent. `snr_db`, `rssi_dbm`, `sender_key_hex`,
`sender_name`, `advert_lat` and `advert_lon` are what the listening side
recorded for that same event, so the test compares this codec against an
independent decode rather than against itself.

The test asserts the SNR/RSSI bytes, the OTA packet's route and payload
type, and the advert's public key, name and position. Add one per radio you
validate; three or more from different sites and signal levels is the useful
spread.

## `grp_txt_capture` — closes the channel-secret-tail open item

```json
{
  "kind": "grp_txt_capture",
  "description": "Public-channel msg from node B, captured on node A via 0x88",
  "firmware": "companion-v1.15.0 / dee3e26ac0 (Seeed T1000-E)",
  "channel_name": "Public",
  "psk_hex": "8b3387e9c5cdea6ac9e5edbaa115cd72",
  "known_plaintext_utf8": "M6 interop test 1",
  "rf_log_frame_hex": "88<snr><rssi><raw OTA packet…>"
}
```

`rf_log_frame_hex` is the **entire** `PUSH_CODE_LOG_RX_DATA` (0x88)
BLE notification, hex, exactly as received (including the leading
`88`). One file per captured message; ≥2 distinct messages are
recommended so the 2-byte MAC match is unambiguous.

The harness asserts `resolveChannelTail(...)` returns `resolved:true`
and reports which `ChannelTailHypothesis` the real device uses — that
is the answer to open item #1.
