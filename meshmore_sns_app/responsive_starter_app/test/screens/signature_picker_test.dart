// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/peer/peer_profiles.dart';
import 'package:meshmore_sns_app/screens/node_detail_sheet.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

final String peerHex = 'ab' * 32;

/// Records dispatched cues without touching platform channels.
class _RecordingCue extends CueService {
  _RecordingCue(ThemeController t) : super(theme: t);
  final List<CueKind> calls = <CueKind>[];
  @override
  Future<void> play(CueKind k) async {
    calls.add(k);
  }
}

DiscoveredNode _node() => DiscoveredNode(
      pubKeyHex: peerHex,
      name: 'Alpha',
      type: 1,
      lastHeardUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      viaAdvert: true,
    );

Widget _host({
  required PeerProfiles peers,
  required CueService cue,
  required ThemeController theme,
  required MeshcoreController mc,
}) =>
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<PeerProfiles>.value(value: peers),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ],
      child: Provider<CueService>.value(
        value: cue,
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NodeDetailSheet(
                node: _node(),
                distanceMeters: null,
                isFavourite: false,
                isKnown: true,
                onToggleFavourite: () {},
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, PeerProfiles peers, _RecordingCue cue,
      ThemeController theme) async {
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport(connected: true));
    addTearDown(mc.dispose);
    await t.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
        _host(peers: peers, cue: cue, theme: theme, mc: mc));
    await t.pump();
  }

  testWidgets('R58 the picker offers Default plus every slot',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController theme = ThemeController();
    await pump(t, PeerProfiles(), _RecordingCue(theme), theme);

    expect(find.text('Arrival signature'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    for (int i = 1; i <= kSignatureSlots.length; i++) {
      expect(find.text('Signature $i'), findsOneWidget);
    }
  });

  // Choosing and auditioning are deliberately the same gesture: a
  // signature has to be recognised, not read.
  testWidgets('R58 tapping a slot selects it AND plays it',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController theme = ThemeController();
    final PeerProfiles peers = PeerProfiles();
    final _RecordingCue cue = _RecordingCue(theme);
    await pump(t, peers, cue, theme);

    await t.tap(find.text('Signature 3'));
    await t.pumpAndSettle();

    expect(peers.signatureFor(peerHex), CueKind.sig3);
    expect(cue.calls, contains(CueKind.sig3));
  });

  testWidgets('R58 Default clears the slot and previews the ordinary dmIn',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController theme = ThemeController();
    final PeerProfiles peers = PeerProfiles();
    await peers.setSignature(peerHex, CueKind.sig2);
    final _RecordingCue cue = _RecordingCue(theme);
    await pump(t, peers, cue, theme);

    await t.tap(find.text('Default'));
    await t.pumpAndSettle();

    expect(peers.signatureFor(peerHex), isNull);
    expect(cue.calls, contains(CueKind.dmIn));
  });

  testWidgets('R58 the current slot shows as selected on open',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController theme = ThemeController();
    final PeerProfiles peers = PeerProfiles();
    await peers.setSignature(peerHex, CueKind.sig5);
    await pump(t, peers, _RecordingCue(theme), theme);

    final ChoiceChip chip = t.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('Signature 5'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chip.selected, isTrue);
  });

  // The vibration still lands when audio is muted, and the user should
  // be told that is what they are auditioning.
  testWidgets('R58 a muted audio master is called out, not hidden',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController theme = ThemeController();
    await theme.setAudioMaster(false);
    await pump(t, PeerProfiles(), _RecordingCue(theme), theme);

    expect(
      find.textContaining('Audio is muted'),
      findsOneWidget,
    );
  });
}
