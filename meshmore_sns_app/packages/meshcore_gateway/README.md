# meshcore_gateway

The wire contract between MeshMore (which owns the radio) and a local client
app (LDMUX). Pure Dart, no Flutter, no socket: this package is the bytes.

The design is `meshmore-sns-architecture.md` §5.5 in the repository root. This
package implements v1 of that contract.

## What it is not

- Not a transport. `dart:io` sockets, the BLE link and the radio are the
  caller's problem.
- Not the end-to-end session. Records carried by `RECORD` and `RECV` are opaque
  here, by design: the gateway is a blind carrier.
