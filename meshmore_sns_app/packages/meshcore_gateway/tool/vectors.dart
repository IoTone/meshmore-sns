import 'package:meshcore_gateway/meshcore_gateway.dart';

String hex(List<int> b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final List<(String, Frame)> frames = <(String, Frame)>[
    ('hello', GatewayMessages.hello(capabilities: 3)),
    ('hello_ok', GatewayMessages.helloOk(
        radioState: RadioState.connected, capabilities: 2)),
    ('hello_err', GatewayMessages.helloErr(HelloError.versionMismatch)),
    ('pair', GatewayMessages.pair(List<int>.generate(16, (int i) => i))),
    ('pair_ok', GatewayMessages.pairOk()),
    ('pair_err', GatewayMessages.pairErr(PairError.badToken)),
    ('bind', GatewayMessages.bind(List<int>.generate(32, (int i) => i))),
    ('bind_ok', GatewayMessages.bindOk(capabilities: 1, uplinkRecordMax: 172)),
    ('bind_err', GatewayMessages.bindErr(BindError.noPath)),
    ('record', GatewayMessages.record(seq: 7, opaqueRecord: <int>[0xAA, 0xBB])),
    ('recv', GatewayMessages.recv(<int>[1, 2, 3])),
    ('send_result', GatewayMessages.sendResult(
        seq: 7, outcome: SendOutcome.sentDirect)),
    ('status5', GatewayMessages.status(
        radioState: RadioState.radioLost,
        rssi: -128,
        batteryPercent: 0xFF,
        txAirtimeTenthsThisHour: 0x1234)),
    ('status6', GatewayMessages.status(
        radioState: RadioState.noContact,
        rssi: -71,
        batteryPercent: 88,
        txAirtimeTenthsThisHour: 0x1234,
        opsLeftThisHour: 57)),
    ('close', GatewayMessages.close(CloseReason.shutdown)),
  ];
  for (final (String name, Frame f) in frames) {
    print("('$name', '${hex(f.encode())}'),");
  }
}
