# meshcore_host

The MeshMore gateway for a machine with a **USB-serial** companion radio: the same
L2 tunnel the phone serves (`packages/meshcore_gateway`), over the same L1 link
(`packages/meshcore`), with a serial transport instead of BLE. It carries opaque
records and knows nothing about what is in them.

## Firmware prerequisite

The radio must run a companion build that defines `ENABLE_USB_INTERFACE`. For the
Heltec V4 that is **`heltec_v4_companion_radio_usb`**. The `heltec_v4_companion_radio_ble`
build does not define it, so it has no USB companion interface and the gateway
times out with exit code 69 ("did not answer APP_START"). Evidence:
`variants/heltec_v4/platformio.ini` in the firmware tree: the flag is in the
`_usb` env (line 190) and absent from the `_ble` env (the block after it).

Flashing a Heltec V4 over USB needs an explicit `esptool.py --after hard_reset`
afterwards; see `meshmore-sns-meshcore-interop.md` §12.7.

## Run

```
dart run bin/meshmore_gateway.dart --port /dev/ttyACM0 [--listen 41731] [--token <hex>] [--state <path>]
```

The pairing token is kept in a 0600 file (the host has no Keystore). It listens on
loopback only. Install as a service with `deploy/meshmore-gateway.service`; the
instructions are at the top of that file.

## Version

`0.1.0` (not published). It follows the repo, not a release train: update by
`git pull` and restart the unit. The gateway wire version is
`GatewayLimits`/`VERSION` in `meshcore_gateway`.

## Tests

`dart test` (30 tests, including a fake radio speaking the real firmware framing).
Against hardware: `dart run tool/hardware_smoke.dart /dev/ttyACM0`.

## Provisioning a second radio

A freshly flashed companion radio has **no radio settings**: `NodePrefs.freq`,
`sf`, `cr` and `bw` default to zero and the firmware applies no region default,
so it cannot transmit until an app sets them. The phone app does that for its own
radio. A host driving a second radio over USB has no app, so use:

    dart run tool/configure_radio.dart /dev/ttyACM0 910.525 62.5 7 5 22

The last five numbers are frequency MHz, bandwidth kHz, spreading factor, coding
rate and TX power dBm. It prints the radio's own read-back and exits non-zero if
the radio did not accept them. These four numbers must match the phone's radio
exactly; only the coding rate is a safe local deviation.

## Configuring a host without copying keys

The firmware's raw-data push carries no sender key — `PUSH_CODE_RAW_DATA` is
`[0x84][snr][rssi][0xFF][payload]` (`examples/companion_radio/MyMesh.cpp:800`) —
so a host must be told which radio it is talking to exactly once. Typing a
64-hex public key is the wrong way to say it, because the radio already knows the
names of its contacts.

```
meshmore_gateway --port /dev/ttyACM1 --peer-name HELTEC-BASE --state ~/.local/state/meshmore/gateway.json
```

`--peer-name` resolves against the radio's own contact table (case-insensitive,
first exact match) and writes what a client needs into the state file:

```json
{"pairingToken":"…","gatewayAddr":"127.0.0.1:41731",
 "radioKey":"<this radio>","peerName":"HELTEC-BASE","peerKey":"<the peer radio>"}
```

A name that does not resolve is a startup error that lists the names the radio
does hold, because guessing a peer would send records into the wrong path. The
state file is written 0600 and merged, never clobbered: saving a rotated token
keeps the identity fields.
