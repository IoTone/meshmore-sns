// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/cue_bridge.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

/// Records dispatched cues without touching platform channels.
class _RecordingCue extends CueService {
  _RecordingCue(ThemeController t) : super(theme: t);
  final List<CueKind> calls = <CueKind>[];
  @override
  Future<void> play(CueKind k) async {
    calls.add(k);
  }
}

/// Minimal speaker so the bridge's speech path is observable without
/// the platform plugin.
class _RecordingSpeaker implements TtsSpeaker {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
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

  group('R5 channel speech is app-scoped, not screen-scoped', () {
    test('an inbound channel message is spoken with no ChatScreen mounted',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      final _RecordingSpeaker spk = _RecordingSpeaker();
      final TtsController tts = TtsController(speaker: spk);
      await tts.setEnabled(true);

      final CueBridge bridge =
          CueBridge(ctrl, _RecordingCue(ThemeController()), tts);
      await ctrl.connect();
      fake.emit(channelMsgFrame(idx: 0, text: 'anyone on frequency'));
      await Future<void>.delayed(Duration.zero);

      // No widget tree at all — this is the whole point of the move.
      expect(spk.spoken, <String>['anyone on frequency']);
      bridge.dispose();
      ctrl.dispose();
    });

    test('the per-channel mute still wins, and only for that channel',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      final _RecordingSpeaker spk = _RecordingSpeaker();
      final TtsController tts = TtsController(speaker: spk);
      await tts.setEnabled(true);
      tts.toggleChannelMute(2);

      final CueBridge bridge =
          CueBridge(ctrl, _RecordingCue(ThemeController()), tts);
      await ctrl.connect();
      fake.emit(channelMsgFrame(idx: 2, text: 'muted channel'));
      await Future<void>.delayed(Duration.zero);
      fake.emit(channelMsgFrame(idx: 1, text: 'other channel'));
      await Future<void>.delayed(Duration.zero);

      expect(spk.spoken, <String>['other channel']);
      bridge.dispose();
      ctrl.dispose();
    });

    test('the audio master silences channel speech', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      final _RecordingSpeaker spk = _RecordingSpeaker();
      final ThemeController theme = ThemeController();
      await theme.setAudioMaster(false);
      final TtsController tts =
          TtsController(speaker: spk, theme: theme);
      await tts.setEnabled(true);

      final CueBridge bridge = CueBridge(ctrl, _RecordingCue(theme), tts);
      await ctrl.connect();
      fake.emit(channelMsgFrame(text: 'should stay quiet'));
      await Future<void>.delayed(Duration.zero);

      expect(spk.spoken, isEmpty);
      bridge.dispose();
      ctrl.dispose();
    });
  });

  group('R58 DM speech is app-scoped, not screen-scoped', () {
    test('an inbound DM from an always-peer is spoken with no DM screen open',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      final _RecordingSpeaker spk = _RecordingSpeaker();
      final TtsController tts = TtsController(speaker: spk);
      // Global speech OFF — `always` must still be heard.
      await tts.setPeerSpeechMode('010203040506', PeerSpeechMode.always);

      final CueBridge bridge =
          CueBridge(ctrl, _RecordingCue(ThemeController()), tts);
      await ctrl.connect();
      fake.emit(contactMessageFrame(
          prefix: <int>[1, 2, 3, 4, 5, 6], text: 'wake up'));
      await Future<void>.delayed(Duration.zero);

      expect(tts.enabled, isFalse);
      expect(spk.spoken, <String>['wake up']);
      bridge.dispose();
      ctrl.dispose();
    });

    test('a never-peer is not spoken even with global speech on', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      final _RecordingSpeaker spk = _RecordingSpeaker();
      final TtsController tts = TtsController(speaker: spk);
      await tts.setEnabled(true);
      await tts.setPeerSpeechMode('010203040506', PeerSpeechMode.never);

      final CueBridge bridge =
          CueBridge(ctrl, _RecordingCue(ThemeController()), tts);
      await ctrl.connect();
      fake.emit(contactMessageFrame(
          prefix: <int>[1, 2, 3, 4, 5, 6], text: 'shush'));
      await Future<void>.delayed(Duration.zero);

      expect(spk.spoken, isEmpty);
      bridge.dispose();
      ctrl.dispose();
    });

    test('no TtsController wired → cues still fire, nothing speaks',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      final _RecordingCue cue = _RecordingCue(ThemeController());
      final CueBridge bridge = CueBridge(ctrl, cue); // no tts

      await ctrl.connect();
      fake.emit(contactMessageFrame(
          prefix: <int>[1, 2, 3, 4, 5, 6], text: 'hi'));
      await Future<void>.delayed(Duration.zero);

      expect(cue.calls, contains(CueKind.dmIn));
      bridge.dispose();
      ctrl.dispose();
    });
  });

  test('reaching ready fires linkUp', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final _RecordingCue cue = _RecordingCue(ThemeController());
    final CueBridge bridge = CueBridge(ctrl, cue);

    await ctrl.connect();
    fake.emit(selfInfoFrame()); // → ready
    await Future<void>.delayed(Duration.zero);

    expect(cue.calls, contains(CueKind.linkUp));
    bridge.dispose();
    ctrl.dispose();
  });

  test('incoming DM fires dmIn', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl =
        MeshcoreController(transportFactory: () async => fake);
    final _RecordingCue cue = _RecordingCue(ThemeController());
    final CueBridge bridge = CueBridge(ctrl, cue);

    await ctrl.connect();
    fake.emit(contactMessageFrame(
        prefix: <int>[1, 2, 3, 4, 5, 6], text: 'hi'));
    await Future<void>.delayed(Duration.zero);

    expect(cue.calls, contains(CueKind.dmIn));
    bridge.dispose();
    ctrl.dispose();
  });

  test('a newly heard node fires discovery (the Geiger tick)', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl =
        MeshcoreController(transportFactory: () async => fake);
    final _RecordingCue cue = _RecordingCue(ThemeController());
    final CueBridge bridge = CueBridge(ctrl, cue);

    await ctrl.connect();
    // A fresh advert → a brand-new node in mc.nodes → discovery cue.
    fake.emit(advertFrame(name: 'NewNode', firstPubByte: 80));
    await Future<void>.delayed(Duration.zero);

    expect(cue.calls, contains(CueKind.discovery));

    // A repeat advert from the same node does NOT re-fire discovery —
    // it fires the ambient `advert` ping instead.
    cue.calls.clear();
    fake.emit(advertFrame(name: 'NewNode', firstPubByte: 80));
    await Future<void>.delayed(Duration.zero);
    expect(cue.calls, isNot(contains(CueKind.discovery)));
    expect(cue.calls, contains(CueKind.advert));

    bridge.dispose();
    ctrl.dispose();
  });

  test('incoming channel message fires messageIn', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl =
        MeshcoreController(transportFactory: () async => fake);
    final _RecordingCue cue = _RecordingCue(ThemeController());
    final CueBridge bridge = CueBridge(ctrl, cue);

    await ctrl.connect();
    fake.emit(channelMsgFrame(text: 'hi'));
    await Future<void>.delayed(Duration.zero);

    expect(cue.calls, contains(CueKind.messageIn));
    bridge.dispose();
    ctrl.dispose();
  });
}
