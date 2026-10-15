// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// R60 Tools against the fake radio. testWidgets for its fake timers:
// `t.pump(d)` advances them; the injected clock moves with it so RTTs
// are deterministic.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/bot/bot_scope.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/tools/mesh_tool.dart';
import 'package:meshmore_sns_app/tools/ping_tool.dart';
import 'package:meshmore_sns_app/tools/range_test_tool.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/tools/trace_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

Uint8List _sent({int tag = 0xabcd, int timeoutMs = 4000}) {
  final Uint8List f = Uint8List(10)..[0] = 0x06;
  ByteData.view(f.buffer)
    ..setUint32(2, tag, Endian.little)
    ..setUint32(6, timeoutMs, Endian.little);
  return f;
}

final List<int> _key = List<int>.generate(32, (int i) => 0x40 + i);
final String _keyHex = hexOf(_key);

/// Fake clock the test moves together with the fake timers.
class _Clock {
  DateTime t = DateTime.utc(2026, 10, 14, 12);
  DateTime now() => t;
}

class _Rig {
  _Rig(this.fake, this.mc, this.tools, this.clock);
  final FakeMeshcoreTransport fake;
  final MeshcoreController mc;
  final ToolsController tools;
  final _Clock clock;

  /// Frames sent since [from], by opcode.
  List<Uint8List> sentOp(int op, {int from = 0}) => <Uint8List>[
        for (final Uint8List f in fake.sent.skip(from))
          if (f.isNotEmpty && f[0] == op) f,
      ];

  Future<void> advance(WidgetTester t, Duration d) async {
    clock.t = clock.t.add(d);
    await t.pump(d);
  }

  Future<void> emit(WidgetTester t, Uint8List f) async {
    fake.emit(f);
    await t.pump();
  }

  Future<void> dispose(WidgetTester t) async {
    tools.dispose();
    mc.dispose();
    await t.pump(const Duration(minutes: 5));
  }
}

Future<_Rig> _rig(WidgetTester t) async {
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  fake.emit(selfInfoFrame());
  await t.pump();
  expect(mc.isReady, isTrue);
  final _Clock clock = _Clock();
  return _Rig(fake, mc, ToolsController(mc, now: clock.now), clock);
}

DiscoveredNode _node({int type = kAdvTypeRepeater, List<int>? route}) =>
    DiscoveredNode(
      pubKeyHex: _keyHex,
      name: 'Hilltop',
      type: type,
      lastHeardUnix: 0,
      viaAdvert: false,
      outPathHashes: route,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('trace path construction', () {
    test('a repeater: its route plus itself, mirrored back', () {
      expect(tracePathFor(_node(route: <int>[0xa1])), <int>[0xa1, 0x40, 0xa1]);
      expect(tracePathFor(_node(route: <int>[0xa1]), roundTrip: false),
          <int>[0xa1, 0x40]);
    });

    test('a direct repeater is one hop; its retransmission comes back', () {
      expect(tracePathFor(_node(route: <int>[])), <int>[0x40]);
    });

    test('a chat node: the repeater chain only', () {
      expect(
          tracePathFor(
              _node(type: kAdvTypeChat, route: <int>[0xa1, 0x7f])),
          <int>[0xa1, 0x7f, 0xa1]);
    });

    test('nothing to trace without a route, or with no repeater', () {
      expect(tracePathFor(_node(route: null)), isNull);
      expect(tracePathFor(_node(type: kAdvTypeChat, route: <int>[])),
          isNull);
    });

    test('manual paths', () {
      expect(parseManualPath('a1,7F a1'), <int>[0xa1, 0x7f, 0xa1]);
      expect(parseManualPath('a17'), isNull);
      expect(parseManualPath('zz'), isNull);
      expect(parseManualPath(''), isNull);
    });
  });

  testWidgets('ping by status request: RTT, loss, and the poller held',
      (WidgetTester t) async {
    final _Rig r = await _rig(t);
    final PingTool ping = r.tools.ping
      ..setTarget(_node())
      ..configure(count: 2, interval: const Duration(seconds: 5));
    expect(ping.method, PingMethod.status);
    final int from = r.fake.sent.length;
    final Future<void> run = ping.start();
    await t.pump();
    expect(r.tools.running, ToolKind.ping);
    expect(r.mc.backgroundRequestsHeld, isTrue);
    expect(r.sentOp(0x1B, from: from), hasLength(1));

    // #1: confirmed, answered 800 ms later.
    await r.emit(t, _sent());
    await r.advance(t, const Duration(milliseconds: 800));
    await r.emit(
        t,
        Uint8List.fromList(
            <int>[0x87, 0, ..._key.take(6), ...List<int>.filled(24, 0)]));
    expect(ping.attempts.first.replied, isTrue);
    expect(ping.attempts.first.rttMs, 800);

    // #2: confirmed, never answered → lost after 4 s × 1.5.
    await r.advance(t, const Duration(seconds: 5));
    expect(r.sentOp(0x1B, from: from), hasLength(2));
    await r.emit(t, _sent());
    await r.advance(t, const Duration(seconds: 7));
    await run;
    expect(ping.attempts[1].replied, isFalse);
    expect(ping.lossPercent, 50);
    expect(ping.rttAvg, 800);
    expect(r.tools.running, isNull);
    expect(r.mc.backgroundRequestsHeld, isFalse);
    await r.dispose(t);
  });

  testWidgets('a tool request\'s SENT never confirms a chat message',
      (WidgetTester t) async {
    final _Rig r = await _rig(t);
    r.tools.ping
      ..setTarget(_node())
      ..configure(count: 1);
    final Future<void> run = r.tools.ping.start();
    await t.pump();
    // A chat message goes out while the status request is in flight.
    final ChatMessage? m = await r.mc.sendDirectText(_keyHex, 'hello');
    await r.emit(t, _sent(tag: 1)); // the tool's
    expect(m!.delivery, MessageDelivery.sending);
    await r.emit(t, _sent(tag: 2)); // the message's
    expect(m.delivery, MessageDelivery.sent);
    expect(m.expectedAck, 2);
    await r.advance(t, const Duration(seconds: 7));
    await run;
    await r.dispose(t);
  });

  testWidgets('unsupported firmware ends the ping with that reason',
      (WidgetTester t) async {
    final _Rig r = await _rig(t);
    r.tools.ping
      ..setTarget(_node())
      ..configure(count: 5);
    final Future<void> run = r.tools.ping.start();
    await t.pump();
    await r.emit(t, errorFrame(kErrUnsupportedCmd));
    await run;
    expect(r.tools.ping.failure, ToolFailure.unsupported);
    expect(r.tools.ping.attempts, hasLength(1));
    await r.dispose(t);
  });

  testWidgets('one tool at a time', (WidgetTester t) async {
    final _Rig r = await _rig(t);
    r.tools.ping
      ..setTarget(_node())
      ..configure(count: 1);
    final Future<void> run = r.tools.ping.start();
    await t.pump();
    await r.tools.discover.start();
    expect(r.tools.discover.failure, ToolFailure.busy);
    r.tools.stopRunning();
    await r.advance(t, const Duration(seconds: 6));
    await run;
    expect(r.tools.running, isNull);
    await r.dispose(t);
  });

  testWidgets('trace: matched by tag, per-hop SNR', (WidgetTester t) async {
    final _Rig r = await _rig(t);
    final int from = r.fake.sent.length;
    final Future<void> run =
        r.tools.trace.trace(<int>[0xa1, 0x7f, 0xa1], label: 'x');
    await t.pump();
    final Uint8List req = r.sentOp(0x24, from: from).single;
    final int tag = ByteData.view(req.buffer).getUint32(1, Endian.little);
    await r.emit(t, _sent(tag: tag));
    await r.advance(t, const Duration(milliseconds: 1500));
    // Someone else's trace first — ignored.
    final Uint8List other = Uint8List.fromList(<int>[
      0x89, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0xa1, 8, 8,
    ]);
    await r.emit(t, other);
    expect(r.tools.trace.runs.first.done, isFalse);
    final ByteData tb = ByteData(4)..setUint32(0, tag, Endian.little);
    await r.emit(
        t,
        Uint8List.fromList(<int>[
          0x89, 0, 3, 0, ...tb.buffer.asUint8List(), 0, 0, 0, 0,
          0xa1, 0x7f, 0xa1, 24, 0xf6, 17, 22,
        ]));
    await run;
    final TraceRun tr = r.tools.trace.runs.first;
    expect(tr.result!.hopSnrsDb, <double>[6.0, -2.5, 4.25]);
    expect(tr.rttMs, 1500);
    expect(tr.weakest, (1, -2.5));
    await r.dispose(t);
  });

  testWidgets('discover: collects repeaters for our tag, weakest link '
      'ordering', (WidgetTester t) async {
    final _Rig r = await _rig(t);
    final int from = r.fake.sent.length;
    final Future<void> run = r.tools.discover.start();
    await t.pump();
    final Uint8List req = r.sentOp(0x37, from: from).single;
    final List<int> tag = req.sublist(3, 7);
    await r.emit(t, Uint8List.fromList(<int>[0x00])); // OK
    Uint8List resp(int theirs4, int ours4, int firstKey) =>
        Uint8List.fromList(<int>[
          0x8e, ours4, 0xa6, 0, 0x92, theirs4, ...tag,
          ...List<int>.generate(32, (int i) => firstKey + i),
        ]);
    await r.emit(t, resp(40, 40, 1)); // 10 dB both ways
    await r.emit(t, resp(0xd8, 40, 100)); // −10 / 10 → asymmetric
    await r.advance(t, const Duration(seconds: 13));
    await run;
    expect(r.tools.discover.found, hasLength(2));
    expect(r.tools.discover.found.first.weakerSnrDb, 10);
    expect(r.tools.discover.found.last.asymmetric, isTrue);
    await r.dispose(t);
  });

  testWidgets('soak refuses Public, structurally', (WidgetTester t) async {
    final _Rig r = await _rig(t);
    r.tools.soak.configure(scope: const ChannelScope(0));
    await r.tools.soak.start();
    expect(r.tools.soak.failure, ToolFailure.publicScope);
    expect(r.tools.running, isNull);
    await r.dispose(t);
  });

  testWidgets('soak over DM: delivery, echoes, dups and reordering',
      (WidgetTester t) async {
    final _Rig r = await _rig(t);
    r.mc.markKnown(_keyHex);
    r.tools.soak.configure(
      scope: DmScope(_keyHex),
      count: 3,
      interval: const Duration(seconds: 5),
    );
    final Future<void> run = r.tools.soak.start();
    await t.pump();
    final String id = r.tools.soak.runId!;
    expect(r.tools.soak.entries.single.message!.text, 'echo soak $id 1/3');
    await r.emit(t, _sent(tag: 11));
    await r.emit(t, Uint8List.fromList(<int>[0x82, 11, 0, 0, 0, 0xf4, 1, 0, 0]));
    expect(r.tools.soak.delivered, 1);
    expect(r.tools.soak.entries.first.ackRttMs, 500);

    await r.advance(t, const Duration(seconds: 5));
    await r.advance(t, const Duration(seconds: 5));
    expect(r.tools.soak.sent, 3);
    // Echoes: 2, then 1 (reordered), then 2 again (duplicate).
    Uint8List echo(int seq) => contactMessageFrame(
        prefix: _key.take(6).toList(), text: '#9 echo soak $id $seq/3');
    await r.emit(t, echo(2));
    await r.emit(t, echo(1));
    await r.emit(t, echo(2));
    expect(r.tools.soak.echoed, 2);
    expect(r.tools.soak.reordered, 1);
    expect(r.tools.soak.duplicates, 1);
    expect(r.tools.soak.missingEchoes, <int>[3]);
    expect(r.tools.soak.listening, isTrue);
    await r.advance(t, const Duration(seconds: 61));
    await run;
    final Map<String, dynamic> rep =
        jsonDecode(r.tools.soak.exportReport()) as Map<String, dynamic>;
    expect(rep['run'], id);
    expect(rep['echoed'], 2);
    expect((rep['messages'] as List<dynamic>).length, 3);
    await r.dispose(t);
  });

  testWidgets('range test receiver: logs beacons, counts gaps, exports CSV',
      (WidgetTester t) async {
    final _Rig r = await _rig(t);
    // Slot 2 holds a private key.
    r.fake.emit(Uint8List.fromList(<int>[
      0x12, 2, ...utf8.encode('Ops').followedBy(List<int>.filled(29, 0)),
      ...List<int>.generate(16, (int i) => i + 1),
    ]));
    await t.pump();
    r.tools.range.configure(mode: RangeMode.receiver, channelIdx: 2);
    final Future<void> run = r.tools.range.start();
    await t.pump();
    expect(r.tools.running, ToolKind.range);
    await r.emit(
        t, channelMsgFrame(idx: 2, text: 'base: RT 1 47.60000,-122.30000'));
    await r.emit(t, channelMsgFrame(idx: 2, text: 'base: RT 4'));
    await r.emit(t, channelMsgFrame(idx: 2, text: 'unrelated chatter'));
    expect(r.tools.range.received, 2);
    expect(r.tools.range.lost, 2);
    final List<String> csv = r.tools.range.exportCsv().trim().split('\n');
    expect(csv, hasLength(3));
    expect(csv[1], startsWith('1,'));
    expect(csv[1], contains('47.6,-122.3'));
    r.tools.stopRunning();
    await t.pump();
    await run;
    await r.dispose(t);
  });

  test('range beacon text', () {
    expect(RangeTestTool.beaconText(3, null), 'RT 3');
  });

  testWidgets('radio stats: three sub-types, duty cycle',
      (WidgetTester t) async {
    final _Rig r = await _rig(t);
    final int from = r.fake.sent.length;
    final Future<void> run = r.tools.stats.fetch();
    await t.pump();
    await r.emit(t, Uint8List.fromList(<int>[
      0x18, 0, 0x68, 0x10, 0xe8, 0x03, 0, 0, 0, 0, 0, // up 1000 s
    ]));
    await r.emit(t, Uint8List.fromList(<int>[
      0x18, 1, 0x92, 0xff, 0xa6, 0x14, 10, 0, 0, 0, 40, 0, 0, 0,
    ]));
    await r.emit(
        t, Uint8List.fromList(<int>[0x18, 2, ...List<int>.filled(24, 1)]));
    await run;
    expect(r.sentOp(0x38, from: from), hasLength(3));
    expect(r.tools.stats.radio!.noiseFloorDbm, -110);
    expect(r.tools.stats.dutyCyclePercent, 5.0);
    expect(r.tools.stats.failure, isNull);
    await r.dispose(t);
  });

  testWidgets('radio stats on old firmware says so', (WidgetTester t) async {
    final _Rig r = await _rig(t);
    final Future<void> run = r.tools.stats.fetch();
    await t.pump();
    await r.emit(t, errorFrame(kErrUnsupportedCmd));
    await run;
    expect(r.tools.stats.failure, ToolFailure.unsupported);
    await r.dispose(t);
  });
}
