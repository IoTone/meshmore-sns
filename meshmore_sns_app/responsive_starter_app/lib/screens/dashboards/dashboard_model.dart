// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/mesh_event.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../meshcore/region_presets.dart';

/// The dashboard's content as **skin-agnostic data** (the slot model).
/// Both the SEELE monolith and the NERV terminal render from this same
/// struct — the layout/identity differs, the data doesn't. Gathering
/// here keeps the per-skin layouts declarative.
class DashboardModel {
  const DashboardModel({
    required this.statusLabel,
    required this.alert,
    required this.busy,
    required this.linked,
    required this.peersInRange,
    required this.knownCount,
    required this.nodeName,
    required this.pubKeyHex,
    required this.radioFields,
    required this.channelLabel,
    required this.region,
    required this.batteryLine,
    required this.contactsLabel,
    required this.events,
  });

  final String statusLabel;
  final bool alert;

  /// R97 — the link is up. Distinct from "not alert": a handshake is
  /// neither. Skins that tint the status use [MmTokens.link] for it.
  final bool linked;
  final bool busy;
  final int peersInRange;

  /// What the count above may be called.
  ///
  /// `proximityFor` answers "near" from a *stored position* within 10 km and
  /// "recent" from a hearing inside five minutes, so with the link down the
  /// count is a fact about the last positions the app heard, not about what the
  /// radio can reach now. Measured on the handset: LINK LOST beside "NODES IN
  /// RANGE 52", which is a claim no dead link can support.
  String peersLabel(AppLocalizations l) =>
      linked ? l.dashboardPeersInRange : l.dashboardPeersInRangeStale;
  final int knownCount;

  /// Radio (MeshCore firmware) contact-list level — `"12/350"` or `"12"`
  /// when the max is unknown, or null before the first contact sync. This
  /// is the device's routable contact table (DM routing), distinct from
  /// app favourites/known.
  final String? contactsLabel;

  /// Device advertised name, or null when SelfInfo isn't in yet.
  final String? nodeName;

  /// Our own 64-hex public key, or null awaiting SelfInfo. This is
  /// the identifier another operator needs before their DMs can route
  /// to us, so every skin should surface it somewhere — see
  /// [MyPubkeyLine], which renders it consistently.
  final String? pubKeyHex;

  /// `915.0MHz SF7 CR5 22dBm`, or null awaiting SelfInfo.
  /// The radio's own settings, one field each.
  ///
  /// A joined string was rendered as a bare `Text` and broke wherever the width
  /// ran out, so "910.525MHz  SF7" ended a line and "CR5  22dBm" began the next
  /// — a config readout split mid-tuple. The fields are kept apart so
  /// [MmValueFields] can decide where a line may break.
  final List<String>? radioFields;

  /// The same facts on one line, for a caller that has its own sentence to
  /// build around them.
  String? get radioLine => radioFields?.join('  ');
  final String channelLabel;
  final String region;
  final String? batteryLine;

  final List<({String time, String text})> events;

  static DashboardModel gather(MeshcoreController mc, AppLocalizations l) {
    final ({String label, bool alert, bool busy}) st = switch (mc.state) {
      MeshcoreConnectionState.ready =>
        (label: l.statusLinked, alert: false, busy: false),
      MeshcoreConnectionState.handshaking =>
        (label: l.statusHandshaking, alert: false, busy: true),
      MeshcoreConnectionState.reconnecting =>
        (label: l.statusReconnecting, alert: true, busy: true),
      MeshcoreConnectionState.failed =>
        (label: l.statusLinkLost, alert: true, busy: false),
      MeshcoreConnectionState.disconnected => (
          label: mc.isConnecting ? l.statusConnecting : l.statusOffline,
          alert: !mc.isConnecting,
          busy: mc.isConnecting,
        ),
    };

    final int inRange = mc.nodes.where((DiscoveredNode n) {
      final NodeProximity p = mc.proximityFor(n);
      return p == NodeProximity.near || p == NodeProximity.recent;
    }).length;

    final SelfInfo? si = mc.selfInfo;
    final RegionPreset? rp = si == null
        ? null
        : matchPresetByRadioParams(
            frequencyMhz: si.frequencyMhz,
            bandwidthKhz: si.bandwidthKhz,
            spreadingFactor: si.spreadingFactor,
            codingRate: si.codingRate,
          );

    String? battery;
    if (mc.batteryVolts != null) {
      final int pct = mc.batteryEstimate.socPercent.isNaN
          ? (mc.batteryPercent ?? 0)
          : mc.batteryEstimate.socPercent.round();
      battery = '${mc.batteryVolts!.toStringAsFixed(2)}V  $pct%'
          '${mc.charging == true ? '  ${l.batteryChargingShort}' : ''}';
    }

    return DashboardModel(
      statusLabel: st.label,
      alert: st.alert,
      linked: mc.state == MeshcoreConnectionState.ready,
      busy: st.busy,
      peersInRange: inRange,
      knownCount: mc.nodes.length,
      nodeName: si == null
          ? null
          : (si.name.isEmpty ? l.dashboardUnnamed : si.name),
      pubKeyHex: mc.ownPubKeyHex,
      radioFields: si == null
          ? null
          : <String>[
              '${si.frequencyMhz}MHz',
              'SF${si.spreadingFactor}',
              'CR${si.codingRate}',
              '${si.txPowerDbm}dBm',
            ],
      channelLabel: 'CH${mc.activeChannel}',
      region: rp == null ? l.deviceRegionCustom : localizedPresetLabel(l, rp.id),
      batteryLine: battery,
      contactsLabel: mc.deviceContactCount == null
          ? null
          : (mc.maxContacts == null
              ? '${mc.deviceContactCount}'
              : '${mc.deviceContactCount}/${mc.maxContacts}'),
      events: <({String time, String text})>[
        for (final MeshEvent e in mc.recentEvents.take(8))
          (
            time: '${e.at.hour.toString().padLeft(2, '0')}:'
                '${e.at.minute.toString().padLeft(2, '0')}:'
                '${e.at.second.toString().padLeft(2, '0')}',
            text: _eventLine(l, e),
          ),
      ],
    );
  }
}

String _eventLine(AppLocalizations l, MeshEvent e) {
  final Map<String, String> a = e.args;
  return switch (e.kind) {
    MeshEventKind.advert => l.eventAdvert(a['name'] ?? '?'),
    MeshEventKind.channelMsg =>
      l.eventChannelMsg(a['channel'] ?? '?', a['text'] ?? ''),
    MeshEventKind.dm => l.eventDm(a['text'] ?? ''),
    MeshEventKind.contact => l.eventContact(a['name'] ?? '?'),
    MeshEventKind.battery => l.eventBattery(a['volts'] ?? '?'),
    MeshEventKind.deviceError =>
      l.eventDeviceError(a['reason'] ?? a['code'] ?? '?'),
    MeshEventKind.deviceClockSynced => l.eventDeviceClockSynced,
    MeshEventKind.deviceClockSkew =>
      l.eventDeviceClockSkew(a['seconds'] ?? '?'),
    MeshEventKind.msgSent => l.eventMsgSent,
    MeshEventKind.deviceInfo => l.eventDeviceInfo(a['version'] ?? '?'),
    MeshEventKind.selfInfo => l.eventSelfInfo(a['name'] ?? '?'),
    MeshEventKind.queuedWaiting => a.containsKey('count')
        ? l.eventQueuedWaitingN(a['count']!)
        : l.eventQueuedWaiting,
    MeshEventKind.oneKeyRejected => l.eventOneKeyRejected(a['key'] ?? '?'),
    MeshEventKind.radioRefused => l.eventRadioRefused,
  };
}
