// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/mesh_network.dart';
import 'package:meshmore_sns_app/meshcore/mesh_network_store.dart';
import 'package:meshmore_sns_app/meshcore/region_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

String key(int fill) => (fill.toRadixString(16).padLeft(2, '0')) * 32;

MeshNetwork privateNet({double freq = 912.5, int ph = 2, List<NetworkMember>? m}) =>
    MeshNetwork(
      id: 'n1',
      name: 'Field',
      frequencyMhz: freq,
      bandwidthKhz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      txPowerDbm: 20,
      pathHashSize: ph,
      members: m ?? <NetworkMember>[],
    );

void main() {
  group('validation mirrors the firmware limits', () {
    test('a good network is accepted', () => expect(privateNet().validate(), isEmpty));

    for (final (String, MeshNetwork Function()) c in <(String, MeshNetwork Function())>[
      ('freq 149', () => privateNet(freq: 149)),
      ('freq 2501', () => privateNet(freq: 2501)),
      ('hash 0', () => privateNet(ph: 0)),
      ('hash 4', () => privateNet(ph: 4)),
    ]) {
      test('${c.$1} is refused at construction', () {
        expect(c.$2, throwsArgumentError);
      });
    }

    test('SF, CR, BW, tx and duplicate members are refused', () {
      MeshNetwork mk({int sf = 7, int cr = 5, double bw = 62.5, int tx = 14}) =>
          MeshNetwork(
              id: 'x',
              name: 'x',
              frequencyMhz: 910,
              bandwidthKhz: bw,
              spreadingFactor: sf,
              codingRate: cr,
              txPowerDbm: tx);
      expect(() => mk(sf: 4), throwsArgumentError);
      expect(() => mk(sf: 13), throwsArgumentError);
      expect(() => mk(cr: 4), throwsArgumentError);
      expect(() => mk(cr: 9), throwsArgumentError);
      expect(() => mk(bw: 6), throwsArgumentError);
      expect(() => mk(bw: 501), throwsArgumentError);
      expect(() => mk(tx: -10), throwsArgumentError);
      expect(
          () => privateNet(m: <NetworkMember>[
                NetworkMember(publicKeyHex: key(1), label: 'a'),
                NetworkMember(publicKeyHex: key(1).toUpperCase(), label: 'b'),
              ]),
          throwsArgumentError,
          reason: 'case must not let one key be added twice');
    });

    test('a member key must be 64 hex characters', () {
      expect(() => NetworkMember(publicKeyHex: 'abc', label: 'x'), throwsArgumentError);
      expect(() => NetworkMember(publicKeyHex: 'z' * 64, label: 'x'), throwsArgumentError);
    });
  });

  group('framesToApply', () {
    test('radio params, tx power, then path hash mode, as exact wire bytes', () {
      final List<Uint8List> f = privateNet(freq: 912.5, ph: 3).framesToApply();
      expect(f, hasLength(3));
      // CMD_SET_RADIO_PARAMS: [0x0B][freq kHz u32 LE][bw Hz u32 LE][sf][cr]
      final ByteData d = ByteData.sublistView(f[0]);
      expect(f[0][0], 0x0B);
      expect(d.getUint32(1, Endian.little), 912500);
      expect(d.getUint32(5, Endian.little), 62500);
      expect(f[0][9], 7);
      expect(f[0][10], 5);
      expect(f[1], <int>[0x0C, 20]);
      // CMD_SET_PATH_HASH_MODE: [0x3D][0][mode], mode = size - 1
      expect(f[2], <int>[0x3D, 0, 2]);
    });

    test('a network built from a preset takes the preset hash size', () {
      final MeshNetwork n = MeshNetwork.fromPreset(presetById('hu')!,
          id: 'h', name: 'HU');
      expect(n.pathHashSize, 2);
      final MeshNetwork us = MeshNetwork.fromPreset(presetById('us_canada')!,
          id: 'u', name: 'US', pathHashSize: 1);
      expect(us.pathHashSize, 1);
    });
  });

  group('is it actually private?', () {
    test('a network on a public preset tuple is NOT isolated', () {
      final MeshNetwork n = MeshNetwork.fromPreset(presetById('us_canada')!,
          id: 'p', name: 'Pretend private');
      expect(n.isolatedFromPublicMesh, isFalse);
      expect(n.overlappingPublicPreset!.id, 'us_canada');
    });

    test('coding rate does not hide the overlap (it is not a separator)', () {
      final MeshNetwork n = MeshNetwork(
          id: 'p',
          name: 'p',
          frequencyMhz: 910.525,
          bandwidthKhz: 62.5,
          spreadingFactor: 7,
          codingRate: 8);
      expect(n.isolatedFromPublicMesh, isFalse);
    });

    test('a frequency a hair off a public preset is still the same channel',
        () {
      // 1 kHz and 10 kHz off the 62.5 kHz USA preset: a receiver decodes
      // both, so neither is a separate network.
      expect(privateNet(freq: 910.526).isolatedFromPublicMesh, isFalse);
      expect(privateNet(freq: 910.535).isolatedFromPublicMesh, isFalse);
      // A whole bandwidth away is separate.
      expect(privateNet(freq: 910.600).isolatedFromPublicMesh, isTrue);
    });

    test('a different frequency, SF or bandwidth is isolated', () {
      expect(privateNet(freq: 912.5).isolatedFromPublicMesh, isTrue);
      final MeshNetwork sf = MeshNetwork(
          id: 'p',
          name: 'p',
          frequencyMhz: 910.525,
          bandwidthKhz: 62.5,
          spreadingFactor: 9,
          codingRate: 5);
      expect(sf.isolatedFromPublicMesh, isTrue);
    });
  });

  group('matches() compares only what must agree', () {
    final MeshNetwork n = privateNet(ph: 2);
    test('same four = on network; CR and tx are not compared', () {
      expect(
          n.matches(
              frequencyMhz: 912.5,
              bandwidthKhz: 62.5,
              spreadingFactor: 7,
              pathHashSize: 2),
          isTrue);
    });
    test('a different path hash size is a different network', () {
      expect(
          n.matches(
              frequencyMhz: 912.5,
              bandwidthKhz: 62.5,
              spreadingFactor: 7,
              pathHashSize: 1),
          isFalse);
    });
  });

  group('persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('round-trips networks and members', () async {
      final MeshNetwork a = privateNet(m: <NetworkMember>[
        NetworkMember(publicKeyHex: key(0xAB), label: 'Host', role: NetworkRole.client),
        NetworkMember(publicKeyHex: key(0xCD), label: 'Hill', role: NetworkRole.repeater),
      ]);
      await MeshNetworkStore.save(<MeshNetwork>[a]);
      final List<MeshNetwork> back = await MeshNetworkStore.load();
      expect(back.single.toJson(), a.toJson());
      expect(back.single.members.last.role, NetworkRole.repeater);
    });

    test('one corrupt entry does not lose the others', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mm.networks.v1': jsonEncode(<Object>[
          privateNet().toJson(),
          <String, Object>{'v': 1, 'id': 'bad', 'name': 'x', 'freq': 9999.0},
          'garbage',
          <String, Object?>{...privateNet().toJson(), 'v': 99},
        ]),
      });
      final List<MeshNetwork> back = await MeshNetworkStore.load();
      expect(back, hasLength(1));
      expect(back.single.id, 'n1');
    });

    test('unparseable storage is an empty list, not a crash', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'mm.networks.v1': '{not json'});
      expect(await MeshNetworkStore.load(), isEmpty);
    });

    test('duplicate ids are refused on save', () async {
      expect(() => MeshNetworkStore.save(<MeshNetwork>[privateNet(), privateNet()]),
          throwsArgumentError);
    });

    test('the stored JSON contains no key material beyond public keys', () async {
      await MeshNetworkStore.save(<MeshNetwork>[
        privateNet(m: <NetworkMember>[NetworkMember(publicKeyHex: key(1), label: 'a')]),
      ]);
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String s = p.getString('mm.networks.v1')!;
      for (final String banned in <String>['secret', 'psk', 'private', 'token']) {
        expect(s.toLowerCase(), isNot(contains(banned)));
      }
    });
  });
}
