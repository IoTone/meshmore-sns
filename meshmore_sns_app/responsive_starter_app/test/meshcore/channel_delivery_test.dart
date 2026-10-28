// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import 'delivery_status_test.dart' show ackFrame, msgSentFrame;
import 'fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// R76: the firmware answers a channel text with RESP_CODE_OK (0x00),
/// not RESP_CODE_SENT. Spec: companion `MyMesh.cpp` handler
/// CMD_SEND_CHANNEL_TXT_MSG (line 1131 in tag companion-v1.17.1).
Uint8List okFrame() => Uint8List.fromList(<int>[0x00]);
Uint8List errFrame(int code) => Uint8List.fromList(<int>[0x01, code]);

Future<MeshcoreController> ready(FakeMeshcoreTransport fake,
    {Duration? timeout}) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    deliveryTimeoutOverride: timeout,
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

class _NoTts implements TtsSpeaker {
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVoice(TtsVoice? voice) async {}
  @override
  Future<List<TtsVoice>> listVoices() async => const <TtsVoice>[];
  @override
  Future<bool> isLanguageAvailable(String locale) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('channel send + OK -> sent promptly, and it stays sent', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c =
        await ready(fake, timeout: const Duration(milliseconds: 40));
    await c.sendChannelText('hi');
    fake.emit(okFrame());
    await tick();
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sent);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sent,
        reason: 'the watchdog must not flip a confirmed message');
    c.dispose();
  });

  test('channel send + ERR(3) -> failed at once with the device reason',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake); // 15 s watchdog
    await c.sendChannelText('hi');
    fake.emit(errFrame(3));
    await tick();
    final ChatMessage m = c.messagesFor(0).single;
    expect(m.delivery, MessageDelivery.failed);
    expect(m.failReason, deviceErrorReason(3));
    c.dispose();
  });

  test('failure reason survives persistence; old rows load without it', () {
    final ChatMessage m = ChatMessage(
        channelIdx: 0,
        text: 'x',
        outgoing: true,
        delivery: MessageDelivery.failed,
        failReason: 'not found');
    expect(ChatMessage.fromJson(m.toJson()).failReason, 'not found');
    final Map<String, Object?> old = m.toJson()..remove('r');
    expect(ChatMessage.fromJson(old).failReason, isNull);
  });

  test('DM + SENT -> sent, then matching ACK -> delivered', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    const String peer = 'aabbccddeeff00112233';
    await c.sendDirectText(peer, 'yo');
    fake.emit(msgSentFrame(ack: 0xBEEF, flood: false));
    await tick();
    expect(c.dmHistoryFor(peer).single.delivery, MessageDelivery.sent);
    fake.emit(ackFrame(0xBEEF));
    await tick();
    expect(c.dmHistoryFor(peer).single.delivery, MessageDelivery.delivered);
    c.dispose();
  });

  test('a SENT never confirms a channel message, an OK never a DM', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    const String peer = 'aabbccddeeff00112233';
    await c.sendChannelText('chan');
    await c.sendDirectText(peer, 'dm');
    fake.emit(msgSentFrame(ack: 0x1, flood: false));
    await tick();
    expect(c.dmHistoryFor(peer).single.delivery, MessageDelivery.sent);
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sending);
    fake.emit(okFrame());
    await tick();
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sent);
    c.dispose();
  });

  test('no reply at all -> failed after the watchdog', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c =
        await ready(fake, timeout: const Duration(milliseconds: 30));
    await c.sendChannelText('hi');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final ChatMessage m = c.messagesFor(0).single;
    expect(m.delivery, MessageDelivery.failed);
    expect(m.failReason, isNotNull);
    c.dispose();
  });

  test('a late OK after the watchdog never revives or re-credits', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c =
        await ready(fake, timeout: const Duration(milliseconds: 30));
    await c.sendChannelText('first');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await c.sendChannelText('second');
    fake.emit(okFrame()); // belongs to the second, first is gone
    await tick();
    final List<ChatMessage> l = c.messagesFor(0);
    expect(l[0].delivery, MessageDelivery.failed);
    expect(l[1].delivery, MessageDelivery.sent);
    c.dispose();
  });

  test('a self-advert OK does not confirm a pending channel message', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    await c.sendSelfAdvert(flood: false); // OK #1 is the advert's
    await c.sendChannelText('hi'); //          OK #2 is the message's
    fake.emit(okFrame());
    await tick();
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sending,
        reason: 'first OK answers the advert');
    fake.emit(okFrame());
    await tick();
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sent);
    c.dispose();
  });

  test('retry re-sends once, re-arms tracking, only for failed rows', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    await c.sendChannelText('again');
    final ChatMessage m = c.messagesFor(0).single;
    expect(await c.retryMessage(m.id), isFalse, reason: 'still sending');
    fake.emit(errFrame(3));
    await tick();
    expect(m.delivery, MessageDelivery.failed);
    final int before = fake.sent.where((f) => f[0] == 0x03).length;
    expect(await c.retryMessage(m.id), isTrue);
    expect(fake.sent.where((f) => f[0] == 0x03).length, before + 1);
    expect(c.messagesFor(0), hasLength(1), reason: 'row is reused');
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sending);
    expect(c.messagesFor(0).single.failReason, isNull);
    fake.emit(okFrame()); // tracking was re-armed
    await tick();
    expect(c.messagesFor(0).single.delivery, MessageDelivery.sent);
    expect(await c.retryMessage(m.id), isFalse, reason: 'no longer failed');
    c.dispose();
  });

  testWidgets('the chat row repaints when the watchdog fails a send',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      deliveryTimeoutOverride: const Duration(milliseconds: 200),
    );
    final TtsController tts = TtsController(speaker: _NoTts());
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: MultiProvider(providers: [
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<TtsController>.value(value: tts),
        ], child: const ChatScreen()),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    await mc.sendChannelText('stuck?');
    await t.pump();
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget,
        reason: 'context.select deep-compares the same message objects');
    expect(find.byIcon(Icons.schedule), findsNothing);
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
