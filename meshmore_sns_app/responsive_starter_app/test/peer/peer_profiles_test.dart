// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/peer/peer_profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String full =
    'b727fe054a4212345678901234567890123456789012345678901234567890ab';
const String prefix = 'b727fe054a42';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PeerProfile record', () {
    test('a record with nothing set is empty and is never written', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await PeerProfileStore.save(<String, PeerProfile>{
        full: const PeerProfile(),
      });
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.getString(PeerProfileStore.kKey), isNull);
    });

    test('speak and signature round-trip independently', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await PeerProfileStore.save(<String, PeerProfile>{
        full: const PeerProfile(
          speak: PeerSpeechMode.always,
          signature: CueKind.sig3,
        ),
        prefix: const PeerProfile(signature: CueKind.sig1),
      });
      final Map<String, PeerProfile> back = await PeerProfileStore.load();
      expect(back[full]!.speak, PeerSpeechMode.always);
      expect(back[full]!.signature, CueKind.sig3);
      expect(back[prefix]!.speak, PeerSpeechMode.inherit);
      expect(back[prefix]!.signature, CueKind.sig1);
    });

    // A hand-edited or downgraded prefs file must not be able to make an
    // arbitrary cue the DM arrival sound.
    test('a non-signature cue name in storage is ignored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PeerProfileStore.kKey: json.encode(<String, Object>{
          full: <String, Object>{'sig': 'alert'},
        }),
      });
      final Map<String, PeerProfile> back = await PeerProfileStore.load();
      // 'alert' is rejected, leaving an empty record, which is dropped.
      expect(back, isEmpty);
    });

    test('a corrupt payload starts clean rather than throwing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PeerProfileStore.kKey: 'not json at all',
      });
      expect(await PeerProfileStore.load(), isEmpty);
    });
  });

  group('v1 -> v2 migration', () {
    test('v1 speech overrides are carried forward', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PeerProfileStore.kLegacyKey: <String>[
          '$full|always',
          '$prefix|never',
        ],
      });
      final Map<String, PeerProfile> back = await PeerProfileStore.load();
      expect(back[full]!.speak, PeerSpeechMode.always);
      expect(back[prefix]!.speak, PeerSpeechMode.never);
      expect(back[full]!.signature, isNull);
    });

    test('migration writes v2 and leaves v1 in place for rollback',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PeerProfileStore.kLegacyKey: <String>['$full|always'],
      });
      await PeerProfileStore.load();
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.getString(PeerProfileStore.kKey), isNotNull);
      expect(p.getStringList(PeerProfileStore.kLegacyKey), isNotNull,
          reason: 'v1 is kept so a rollback shows stale, not empty');
    });

    test('v2 wins when both exist — the stale v1 is never re-read',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PeerProfileStore.kLegacyKey: <String>['$full|always'],
        PeerProfileStore.kKey: json.encode(<String, Object>{
          full: <String, Object>{'speak': 'never'},
        }),
      });
      final Map<String, PeerProfile> back = await PeerProfileStore.load();
      expect(back[full]!.speak, PeerSpeechMode.never);
    });

    test('malformed v1 rows are dropped, not fatal', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PeerProfileStore.kLegacyKey: <String>['garbage', '|always', full],
      });
      expect(await PeerProfileStore.load(), isEmpty);
    });
  });

  group('PeerProfiles owner', () {
    test('signature and speech coexist on one peer', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PeerProfiles peers = PeerProfiles();
      await peers.setSpeechMode(full, PeerSpeechMode.always);
      await peers.setSignature(full, CueKind.sig2);

      expect(peers.speechMode(full), PeerSpeechMode.always);
      expect(peers.signatureFor(full), CueKind.sig2);
      expect(peers.all.length, 1, reason: 'one peer, one row');
    });

    test('clearing both fields drops the peer entirely', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PeerProfiles peers = PeerProfiles();
      await peers.setSpeechMode(full, PeerSpeechMode.never);
      await peers.setSignature(full, CueKind.sig4);
      expect(peers.all, isNotEmpty);

      await peers.setSignature(full, null);
      await peers.setSpeechMode(full, PeerSpeechMode.inherit);
      expect(peers.all, isEmpty);
      expect(await PeerProfileStore.load(), isEmpty);
    });

    // A DM carries the full pubkey when the fabric resolves it and only
    // a 12-hex prefix when it cannot; both must find the same record.
    test('a prefix-set signature is found by the full key, and converges',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PeerProfiles peers = PeerProfiles();
      await peers.setSignature(prefix, CueKind.sig5);
      expect(peers.signatureFor(full), CueKind.sig5);

      await peers.setSpeechMode(full, PeerSpeechMode.always);
      expect(peers.all.length, 1, reason: 'converged onto one row');
      expect(peers.all.keys.single, full,
          reason: 'and onto the longer key');
      expect(peers.signatureFor(prefix), CueKind.sig5,
          reason: 'still reachable by the short form');
    });

    test('records survive a reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PeerProfiles a = PeerProfiles();
      await a.setSignature(full, CueKind.sig3);
      await a.setSpeechMode(full, PeerSpeechMode.never);

      final PeerProfiles b = PeerProfiles();
      await b.load();
      expect(b.signatureFor(full), CueKind.sig3);
      expect(b.speechMode(full), PeerSpeechMode.never);
    });

    test('an unknown peer inherits everything', () {
      final PeerProfiles peers = PeerProfiles();
      expect(peers.speechMode(full), PeerSpeechMode.inherit);
      expect(peers.signatureFor(full), isNull);
      expect(peers.profileFor(full).isEmpty, isTrue);
    });

    test('notifies listeners on change', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PeerProfiles peers = PeerProfiles();
      int n = 0;
      peers.addListener(() => n++);
      await peers.setSignature(full, CueKind.sig1);
      expect(n, 1);
      // Setting the same value again is a no-op, not a notify storm.
      await peers.setSignature(full, CueKind.sig1);
      expect(n, 1);
    });
  });
}
