import 'dart:typed_data';
import 'package:meshcore_gateway/meshcore_gateway.dart';

Future<void> main(List<String> a) async {
  final c = GatewayClient();
  try {
    await c.connect(port: 43000);
    final h = await c.hello();
    print('hello ok caps=${h.capabilities} state=${h.radioState}');
    await c.pair(_hex(a[0]));
    print('pair ok');
    final b = await c.bind(_hex(a[1]));
    print('BIND OK caps=${b.capabilities} max=${b.uplinkRecordMax}');
  } catch (e) {
    print('FAILED: $e');
  } finally {
    await c.close();
  }
}

Uint8List _hex(String s) => Uint8List.fromList(
    List.generate(s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));
