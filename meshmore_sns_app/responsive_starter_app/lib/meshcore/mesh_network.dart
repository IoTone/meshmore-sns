// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

import 'region_presets.dart';

/// A MeshCore network: the radio parameters every member must share, and
/// who the members are.
///
/// MeshCore has no network object of its own. A "network" is the set of
/// radios that agree on frequency, bandwidth and spreading factor
/// (`meshmore-sns-radio-config.md` section 3). Coding rate is carried in the
/// packet header and need not match. Path hash size is the length a node
/// stamps on what it sends; forwarders follow each packet's own length
/// (`Mesh.cpp:89`), so it is a convention kept here for consistency and for
/// the directed payload budget, not a compatibility requirement. This class
/// is that agreement, written down once, so N radios can be configured
/// identically instead of by retyping numbers N times.
///
/// It holds NO secrets: no channel key, no private key, no pairing token.
/// Members are identified by public key only (`meshmore-sns-ux-coverage.md`
/// rule 3).
class MeshNetwork {
  MeshNetwork({
    required this.id,
    required this.name,
    required this.frequencyMhz,
    required this.bandwidthKhz,
    required this.spreadingFactor,
    required this.codingRate,
    this.txPowerDbm = 14,
    this.pathHashSize = 1,
    List<NetworkMember> members = const <NetworkMember>[],
  }) : members = List<NetworkMember>.unmodifiable(members) {
    final List<String> problems = validate();
    if (problems.isNotEmpty) {
      throw ArgumentError('invalid MeshNetwork: ${problems.join('; ')}');
    }
  }

  /// A network that copies a region preset. The preset's path hash size is
  /// used when it has one, otherwise [pathHashSize] (default 1 byte).
  factory MeshNetwork.fromPreset(
    RegionPreset p, {
    required String id,
    required String name,
    int pathHashSize = 1,
    List<NetworkMember> members = const <NetworkMember>[],
  }) =>
      MeshNetwork(
        id: id,
        name: name,
        frequencyMhz: p.frequencyMhz,
        bandwidthKhz: p.bandwidthKhz,
        spreadingFactor: p.spreadingFactor,
        codingRate: p.codingRate,
        txPowerDbm: p.txPowerDbm,
        pathHashSize: p.pathHashSize ?? pathHashSize,
        members: members,
      );

  /// Stable, never shown.
  final String id;
  final String name;
  final double frequencyMhz;
  final double bandwidthKhz;
  final int spreadingFactor;
  final int codingRate;
  final int txPowerDbm;

  /// 1..3 bytes. Sent as wire mode `size - 1`.
  final int pathHashSize;
  final List<NetworkMember> members;

  /// Firmware limits, `MyMesh.cpp` CMD_SET_RADIO_PARAMS and
  /// CMD_SET_RADIO_TX_POWER handlers. Checked here so a bad network is
  /// refused when it is made, not by the radio at apply time.
  List<String> validate() {
    final List<String> out = <String>[];
    if (id.isEmpty) out.add('id is empty');
    if (name.trim().isEmpty) out.add('name is empty');
    if (frequencyMhz < 150 || frequencyMhz > 2500) {
      out.add('frequency must be 150..2500 MHz');
    }
    if (bandwidthKhz < 7 || bandwidthKhz > 500) {
      out.add('bandwidth must be 7..500 kHz');
    }
    if (spreadingFactor < 5 || spreadingFactor > 12) {
      out.add('spreading factor must be 5..12');
    }
    if (codingRate < 5 || codingRate > 8) out.add('coding rate must be 5..8');
    if (txPowerDbm < -9 || txPowerDbm > 30) {
      out.add('tx power must be -9..30 dBm');
    }
    if (pathHashSize < 1 || pathHashSize > 3) {
      out.add('path hash size must be 1..3 bytes');
    }
    final Set<String> seen = <String>{};
    for (final NetworkMember m in members) {
      if (!seen.add(m.publicKeyHex)) out.add('duplicate member ${m.shortKey}');
    }
    return out;
  }

  /// The public preset this network's radio tuple equals, ignoring coding
  /// rate (which need not match), or null for a tuple no preset uses.
  ///
  /// Non-null means these radios share the air with the public mesh on that
  /// preset: a private KEY or NAME would not isolate them, only a different
  /// frequency does (`meshmore-sns-private-mesh-investigation.md` section 6).
  /// The UI should say so rather than call such a network "private".
  RegionPreset? get overlappingPublicPreset {
    for (final RegionPreset p in kRegionPresets) {
      if ((p.frequencyMhz - frequencyMhz).abs() <= 0.001 &&
          (p.bandwidthKhz - bandwidthKhz).abs() <= 0.5 &&
          p.spreadingFactor == spreadingFactor) {
        return p;
      }
    }
    return null;
  }

  /// True when the radio tuple is on no public preset.
  bool get isolatedFromPublicMesh => overlappingPublicPreset == null;

  /// The frames that put a radio on this network, in the order to send them.
  /// Each is one companion frame (one BLE write).
  List<Uint8List> framesToApply() => <Uint8List>[
        MeshcoreFrameCodec.setRadioParams(RadioParams(
          frequencyMhz: frequencyMhz,
          bandwidthKhz: bandwidthKhz,
          spreadingFactor: spreadingFactor,
          codingRate: codingRate,
        )),
        MeshcoreFrameCodec.setRadioTxPower(txPowerDbm),
        MeshcoreFrameCodec.setPathHashMode(pathHashSize),
      ];

  /// Whether a radio's reported state is already on this network: the three
  /// things that must match (frequency, bandwidth, SF) plus the path hash
  /// size, which this network wants its members to share. Coding rate and TX
  /// power are deliberately not compared.
  bool matches({
    required double frequencyMhz,
    required double bandwidthKhz,
    required int spreadingFactor,
    required int pathHashSize,
  }) =>
      (this.frequencyMhz - frequencyMhz).abs() <= 0.001 &&
      (this.bandwidthKhz - bandwidthKhz).abs() <= 0.5 &&
      this.spreadingFactor == spreadingFactor &&
      this.pathHashSize == pathHashSize;

  MeshNetwork copyWith({
    String? name,
    List<NetworkMember>? members,
  }) =>
      MeshNetwork(
        id: id,
        name: name ?? this.name,
        frequencyMhz: frequencyMhz,
        bandwidthKhz: bandwidthKhz,
        spreadingFactor: spreadingFactor,
        codingRate: codingRate,
        txPowerDbm: txPowerDbm,
        pathHashSize: pathHashSize,
        members: members ?? this.members,
      );

  static const int schemaVersion = 1;

  Map<String, Object?> toJson() => <String, Object?>{
        'v': schemaVersion,
        'id': id,
        'name': name,
        'freq': frequencyMhz,
        'bw': bandwidthKhz,
        'sf': spreadingFactor,
        'cr': codingRate,
        'tx': txPowerDbm,
        'ph': pathHashSize,
        'members': <Map<String, Object?>>[
          for (final NetworkMember m in members) m.toJson(),
        ],
      };

  /// Returns null for anything that is not a valid v1 network, so one
  /// corrupt entry never takes the rest of the list down.
  static MeshNetwork? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    if (raw['v'] != schemaVersion) return null;
    try {
      final List<NetworkMember> members = <NetworkMember>[];
      for (final Object? m in (raw['members'] as List<dynamic>? ?? <dynamic>[])) {
        final NetworkMember? nm = NetworkMember.tryFromJson(m);
        if (nm != null) members.add(nm);
      }
      return MeshNetwork(
        id: raw['id'] as String,
        name: raw['name'] as String,
        frequencyMhz: (raw['freq'] as num).toDouble(),
        bandwidthKhz: (raw['bw'] as num).toDouble(),
        spreadingFactor: raw['sf'] as int,
        codingRate: raw['cr'] as int,
        txPowerDbm: raw['tx'] as int,
        pathHashSize: raw['ph'] as int,
        members: members,
      );
    } catch (_) {
      return null;
    }
  }
}

/// How a member attaches to the network. Only the radio-side fact the app
/// can act on: a repeater is provisioned by flashing `simple_repeater`
/// firmware, which a phone cannot do (`meshmore-sns-protocol-coverage.md`).
enum NetworkRole { client, repeater }

/// One radio in a network, by public key.
class NetworkMember {
  NetworkMember({
    required String publicKeyHex,
    required this.label,
    this.role = NetworkRole.client,
  }) : publicKeyHex = publicKeyHex.toLowerCase() {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(this.publicKeyHex)) {
      throw ArgumentError.value(
          publicKeyHex, 'publicKeyHex', 'must be 64 hex characters');
    }
  }

  final String publicKeyHex;
  final String label;
  final NetworkRole role;

  String get shortKey => publicKeyHex.substring(0, 8);

  Map<String, Object?> toJson() => <String, Object?>{
        'key': publicKeyHex,
        'label': label,
        'role': role.name,
      };

  static NetworkMember? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      return NetworkMember(
        publicKeyHex: raw['key'] as String,
        label: raw['label'] as String,
        role: NetworkRole.values.firstWhere(
          (NetworkRole r) => r.name == raw['role'],
          orElse: () => NetworkRole.client,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
