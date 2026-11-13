// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../util/mm_format.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/node_telemetry.dart';
import '../sns/weather_inference.dart';
import '../sns/weather_lexicon.dart';
import '../util/geo.dart' as geo;
import 'grid_notice.dart';
import 'node_detail_sheet.dart';
import '../theme/viz_palette.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_shape.dart';
import '../util/relative_time.dart';

/// Mesh weather — a glanceable view of the environment telemetry
/// reported across the fabric: a summary band (how many nodes are
/// reporting + min/avg/max temperature) and a list of reporting nodes
/// sorted warmest-first, each with a colour-scaled temperature chip.
///
/// Data is whatever telemetry we already hold (self + any polled or
/// overheard contact) — the background poller fills this in over time.
/// Empty until at least one node reports a sensor reading.
class WeatherView extends StatefulWidget {
  const WeatherView({super.key, this.filteredNodes});

  final List<DiscoveredNode>? filteredNodes;

  @override
  State<WeatherView> createState() => _WeatherViewState();
}

class _WeatherViewState extends State<WeatherView> {
  @override
  void initState() {
    super.initState();
    // Refetch our own telemetry on open so self environment (if the
    // device reports it) is current. Peer readings come from the
    // background poller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final MeshcoreController mc = context.read<MeshcoreController>();
      if (mc.isReady) mc.requestSelfTelemetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;

    // Build (node, telemetry) pairs that actually report environment.
    final List<_Reading> readings = <_Reading>[];
    final String? ownHex = mc.ownPubKeyHex;
    final List<DiscoveredNode> source = widget.filteredNodes ?? mc.nodes;
    for (final DiscoveredNode n in source) {
      final NodeTelemetry? t = mc.telemetryFor(n.pubKeyHex);
      if (t != null && t.hasEnvironment) {
        readings.add(_Reading(
            name: n.name.isEmpty ? n.shortId : n.name,
            isSelf: n.pubKeyHex == ownHex,
            pubKeyHex: n.pubKeyHex,
            t: t));
      }
    }
    // Self may not be in the node list — add it explicitly.
    final NodeTelemetry? self = mc.selfTelemetry;
    if (self != null &&
        self.hasEnvironment &&
        !readings.any((_Reading r) => r.isSelf)) {
      readings.add(_Reading(
          name: l.weatherSelf, isSelf: true, pubKeyHex: ownHex, t: self));
    }

    // --- Microclimate: weather mined from chat on the selected channel,
    // split into a last-hour and a rolling last-24h rollup. This is the
    // *only* weather signal when the firmware reports no environment
    // telemetry, so it always shows.
    final List<WxObservation> scanned = _scanObservations(mc, context);
    final DateTime now = DateTime.now();
    final AmbientWx? lastHour = aggregateAmbient(scanned.where(
        (WxObservation o) => now.difference(o.at) <= const Duration(hours: 1)));
    final AmbientWx? last24h = aggregateAmbient(scanned);
    // The newest mention in the window, so the strip can say how old the
    // reading is. A rollup that states no age is the kind of number a reader
    // trusts for a week after it stopped being true.
    DateTime? newest;
    for (final WxObservation o in scanned) {
      if (newest == null || o.at.isAfter(newest)) newest = o.at;
    }
    final Widget micro = _MicroclimateStrip(
      lastHour: lastHour,
      last24h: last24h,
      // The channel's own name, not its slot number: "CH0" is an index the
      // firmware uses, and the user picked a name.
      channelLabel: mc.activeChannelName,
      newestAt: newest,
      l: l,
      cs: cs,
    );

    // Measured (sensor) telemetry section.
    final List<double> temps = <double>[
      for (final _Reading r in readings)
        if (r.t.temperatureC != null) r.t.temperatureC!,
    ];
    readings.sort((_Reading a, _Reading b) =>
        (b.t.temperatureC ?? -999).compareTo(a.t.temperatureC ?? -999));

    final List<Widget> measured = <Widget>[];
    if (readings.isEmpty) {
      // Diagnostic: distinguish "no self telemetry received at all"
      // from "received, but the device reports no environment sensor".
      final NodeTelemetry? selfT = mc.selfTelemetry;
      final String selfDiag = selfT == null
          ? l.weatherSelfNoTelemetry
          : l.weatherSelfNoEnv(selfT.entries.isEmpty
              ? '—'
              : selfT.entries
                  .map((e) => '0x${e.type.toRadixString(16)}')
                  .join(', '));
      measured.add(GridNotice(
        message: l.weatherEmpty,
        icon: Icons.thermostat,
        // Which of two causes this is, in one line rather than a panel: the
        // radio has not answered yet, or this firmware has no sensor.
        detail: selfDiag,
        actionLabel: l.weatherOpenTelemetrySettings,
        onAction: () => context.push('/settings/app'),
      ));
    } else {
      if (temps.isNotEmpty) {
        measured.add(_SummaryCard(
          count: readings.length,
          minC: temps.reduce((double a, double b) => a < b ? a : b),
          maxC: temps.reduce((double a, double b) => a > b ? a : b),
          avgC: temps.reduce((double a, double b) => a + b) / temps.length,
          cs: cs,
          l: l,
        ));
      }
      measured.add(const SizedBox(height: 8));
      for (final _Reading r in readings) {
        measured.add(_ReadingTile(r: r, cs: cs, l: l));
      }
    }

    // P2 — per-place microclimate bubbles (located weather chatter).
    final List<Microclimate> climates = mc.microclimatesFor(mc.activeChannel);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        micro,
        if (climates.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(l.wxMicroclimatesHeader,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeSm, letterSpacing: 2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Microclimate m in climates)
                _MicroclimateBubble(climate: m, mc: mc, cs: cs, l: l),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Text(l.weatherMeasuredHeader,
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: context.skin.type.sizeSm,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        ...measured,
      ],
    );
  }

  static const Duration _wxWindow = Duration(hours: 24);

  /// Scan the selected channel's chat within the rolling 24h window for
  /// weather mentions. The caller buckets these into last-hour / last-24h
  /// rollups. Pure logic lives in `weather_inference.dart`.
  List<WxObservation> _scanObservations(
      MeshcoreController mc, BuildContext context) {
    final String lang = Localizations.localeOf(context).languageCode;
    final DateTime now = DateTime.now();
    final List<WxObservation> obs = <WxObservation>[];
    for (final ChatMessage m in mc.messagesFor(mc.activeChannel)) {
      if (now.difference(m.at) > _wxWindow) continue;
      final WxObservation? o = WeatherInferenceEngine.scan(
        m.text,
        languageCode: lang,
        at: m.at,
        sourceMsgId: m.id,
      );
      if (o != null && o.confidence >= 0.5) obs.add(o);
    }
    return obs;
  }
}

class _Reading {
  const _Reading({
    required this.name,
    required this.isSelf,
    required this.pubKeyHex,
    required this.t,
  });
  final String name;
  final bool isSelf;
  final String? pubKeyHex;
  final NodeTelemetry t;
}

/// Map a temperature to a cold→hot colour ramp (blue → teal → amber →
/// red), clamped to a comfortable everyday range.
Color temperatureColor(double c) {
  const double lo = -10, hi = 40;
  final double f = ((c - lo) / (hi - lo)).clamp(0.0, 1.0);
  // Three-stop gradient: cold → mild → hot (the ramp lives in the palette so a
  // screen holds no colour literal and the encoding is declared once).
  if (f < 0.5) {
    return Color.lerp(kThermalCold, kThermalMild, f / 0.5)!;
  }
  return Color.lerp(kThermalMild, kThermalHot, (f - 0.5) / 0.5)!;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.minC,
    required this.maxC,
    required this.avgC,
    required this.cs,
    required this.l,
  });
  final int count;
  final double minC;
  final double maxC;
  final double avgC;
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, double c) => Column(
          children: <Widget>[
            Text('${c.toStringAsFixed(1)}°',
                style: TextStyle(
                    color: temperatureColor(c),
                    fontSize: context.skin.type.size(22),
                    fontWeight: FontWeight.w700,
                    fontFamily: context.skin.type.monoFamily)),
            Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeMicro)),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: mmRadius(context, 14),
        border: Border.all(color: cs.outline.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.weatherReporting(count),
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeSm, letterSpacing: 2)),
          const SizedBox(height: 10),
          // Three numbers side by side at 200 % text are wider than a
          // 320 dp screen (measured: 402 px of overflow), and there is no
          // useful truncation for a temperature. They wrap instead, and each
          // column takes an equal share of the line when they fit.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final bool oneLine = box.maxWidth >= 300;
              final List<Widget> stats = <Widget>[
                stat(l.weatherMin, minC),
                stat(l.weatherAvg, avgC),
                stat(l.weatherMax, maxC),
              ];
              if (!oneLine) {
                return Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: 16,
                  runSpacing: 8,
                  children: stats,
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  for (final Widget w in stats) Flexible(child: w)
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({required this.r, required this.cs, required this.l});
  final _Reading r;
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final double? c = r.t.temperatureC;
    final List<String> extra = <String>[
      if (r.t.humidityPct != null) '${r.t.humidityPct!.toStringAsFixed(0)}%',
      if (r.t.pressureHpa != null)
        '${r.t.pressureHpa!.toStringAsFixed(0)} hPa',
      // Luminosity — unit varies by device (lux vs the T1000-E's 0-100
      // scale), so show the bare reading behind a sun glyph.
      if (r.t.luminosity != null) '☀ ${r.t.luminosity!.toStringAsFixed(0)}',
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        width: 52,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: (c != null ? temperatureColor(c) : cs.onSurfaceVariant)
              .withValues(alpha: .18),
          borderRadius: mmRadius(context, 10),
        ),
        child: Text(
          c != null ? '${c.toStringAsFixed(1)}°' : '—',
          style: TextStyle(
              color: c != null ? temperatureColor(c) : cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontFamily: context.skin.type.monoFamily),
        ),
      ),
      title: Row(
        children: <Widget>[
          if (r.isSelf)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.my_location, size: 14, color: cs.primary),
            ),
          Flexible(
              child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(
        <String>[if (extra.isNotEmpty) extra.join(' · '), _ago(r.t.receivedAt, l)]
            .where((String s) => s.isNotEmpty)
            .join('  ·  '),
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody),
      ),
      onTap: r.pubKeyHex == null
          ? null
          : () {
              final MeshcoreController mc =
                  context.read<MeshcoreController>();
              DiscoveredNode? node;
              for (final DiscoveredNode n in mc.nodes) {
                if (n.pubKeyHex == r.pubKeyHex) {
                  node = n;
                  break;
                }
              }
              if (node == null) return;
              final DiscoveredNode peer = node;
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => NodeDetailSheet(
                  node: peer,
                  distanceMeters: peer.hasLocation
                      ? mc.distanceMetersTo(peer.latitude!, peer.longitude!)
                      : null,
                  isFavourite: mc.favorites.contains(peer.pubKeyHex),
                  isKnown: mc.known.contains(peer.pubKeyHex),
                  onToggleFavourite: () => mc.toggleFavorite(peer.pubKeyHex),
                  proximity: mc.proximityFor(peer),
                  recentDms: mc.dmHistoryFor(peer.pubKeyHex),
                  tags: mc.tagsFor(peer.pubKeyHex),
                  tagSuggestions: mc.allTags,
                  onAddTag: (String t) => mc.addTagTo(peer.pubKeyHex, t),
                  onRemoveTag: (String t) =>
                      mc.removeTagFrom(peer.pubKeyHex, t),
                ),
              );
            },
    );
  }

}

/// Localized one-word label for a weather condition.
String wxConditionLabel(WxCondition c, AppLocalizations l) => switch (c) {
      WxCondition.clear => l.wxCondClear,
      WxCondition.clouds => l.wxCondClouds,
      WxCondition.fog => l.wxCondFog,
      WxCondition.rain => l.wxCondRain,
      WxCondition.snow => l.wxCondSnow,
      WxCondition.wind => l.wxCondWind,
      WxCondition.storm => l.wxCondStorm,
      WxCondition.heat => l.wxCondHeat,
      WxCondition.cold => l.wxCondCold,
    };

/// The chat-derived microclimate summary for the selected channel, broken
/// into two windows: the **last hour** and the rolling **last 24h**. Each
/// row shows the dominant condition glyph + label, temperature range and
/// mention count. Renders a quiet "no chatter yet" hint when 24h is empty.
class _MicroclimateStrip extends StatelessWidget {
  const _MicroclimateStrip({
    required this.lastHour,
    required this.last24h,
    required this.channelLabel,
    required this.newestAt,
    required this.l,
    required this.cs,
  });

  final AmbientWx? lastHour;
  final AmbientWx? last24h;
  final String channelLabel;

  /// The most recent message this rollup read, or null when there is none.
  final DateTime? newestAt;
  final AppLocalizations l;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: mmRadius(context, 14),
        border: Border.all(color: cs.outline.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_queue, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              // The title and the channel name together are wider than a
              // 320 dp screen at 200 % text, and an unconstrained Text in a
              // Row overflows rather than wrapping. It takes the rest of the
              // line and wraps inside it.
              Expanded(
                child: Text('${l.wxMicroclimateTitle} · $channelLabel',
                    softWrap: true,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: context.skin.type.sizeSm,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // What this block is made of. It is inferred from what people wrote
          // in the channel, not measured by a sensor, and the header alone
          // does not say so — a reader would take it for telemetry.
          Text(
            newestAt == null
                ? l.wxMicroclimateFromChatNoMessages
                : l.wxMicroclimateFromChat(_ago(newestAt!, l)),
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: context.skin.type.sizeSm,
                height: 1.3),
          ),
          const SizedBox(height: 10),
          if (last24h == null)
            Text(l.wxAmbientEmpty,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBodyLg))
          else ...<Widget>[
            _WindowRow(label: l.wxLastHour, ambient: lastHour, l: l, cs: cs),
            Divider(
                height: context.skin.space.screenEdge,
                color: cs.outline.withValues(alpha: .25)),
            _WindowRow(label: l.wxLast24h, ambient: last24h, l: l, cs: cs),
          ],
        ],
      ),
    );
  }
}

/// "3 min ago", "2 h ago" — the reading tiles' side of the app's one ladder.
String _ago(DateTime at, AppLocalizations l) =>
    weatherAgo(l, DateTime.now().difference(at));

/// One window's ambient rollup (e.g. "1H" or "24H"): a window pill, the
/// dominant glyph + condition + temp, and a mention count — or a muted "—"
/// when that window saw no chatter.
class _WindowRow extends StatelessWidget {
  const _WindowRow({
    required this.label,
    required this.ambient,
    required this.l,
    required this.cs,
  });

  final String label;
  final AmbientWx? ambient;
  final AppLocalizations l;
  final ColorScheme cs;

  String _tempLabel(AmbientWx a, FormatPrefs? prefs) {
    if (!a.hasTemp) return '';
    return MmFormat.range(a.tempMinC!, a.tempMaxC!, prefs: prefs);
  }

  List<WxCondition> _others(AmbientWx a) {
    final List<WxCondition> rest = a.tally.keys
        .where((WxCondition c) => c != a.dominant)
        .toList(growable: false);
    return rest.length <= 3 ? rest : rest.sublist(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final AmbientWx? a = ambient;
    final Widget pill = Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: a == null ? .08 : .16),
        borderRadius: mmRadius(context, 6),
      ),
      child: Text(label,
          style: TextStyle(
              color: a == null ? cs.onSurfaceVariant : cs.primary,
              fontSize: context.skin.type.sizeMicro,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              fontFamily: context.skin.type.monoFamily)),
    );

    if (a == null) {
      return Row(
        children: <Widget>[
          pill,
          const SizedBox(width: 12),
          Text('—',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeLg)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        pill,
        const SizedBox(width: 10),
        Text(a.dominant != null ? wxGlyph(a.dominant!) : '🌡',
            style: TextStyle(fontSize: context.skin.type.size(26))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (a.dominant != null)
                    Text(wxConditionLabel(a.dominant!, l),
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: context.skin.type.size(17),
                            fontWeight: FontWeight.w600)),
                  if (a.hasTemp) ...<Widget>[
                    if (a.dominant != null) const SizedBox(width: 8),
                    Text(_tempLabel(a, context.formatPrefs),
                        style: TextStyle(
                            color: cs.onSurface,
                            fontFamily: context.skin.type.monoFamily,
                            fontSize: context.skin.type.size(15))),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              // The measured quantities, when any message carried them: a
              // pressure or a humidity that was parsed and never shown is the
              // same as one that was never parsed.
              if (a.hasMeasurement)
                Wrap(
                  spacing: 10,
                  children: <Widget>[
                    if (a.humidityAvgPct != null)
                      Text('RH ${a.humidityAvgPct!.round()}%',
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontFamily: context.skin.type.monoFamily,
                              fontSize: context.skin.type.sizeBody)),
                    if (a.pressureAvgHpa != null)
                      Text('${a.pressureAvgHpa!.round()} hPa',
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontFamily: context.skin.type.monoFamily,
                              fontSize: context.skin.type.sizeBody)),
                    if (a.windMaxMps != null)
                      Text('${a.windMaxMps!.toStringAsFixed(1)} m/s',
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontFamily: context.skin.type.monoFamily,
                              fontSize: context.skin.type.sizeBody)),
                  ],
                ),
              Text(l.wxMentionsShort(a.mentions),
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody)),
            ],
          ),
        ),
        ..._others(a).map((WxCondition c) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child:
                  Text(wxGlyph(c), style: TextStyle(fontSize: context.skin.type.size(15))),
            )),
      ],
    );
  }
}

/// A per-place microclimate bubble (P2): condition glyph + place label
/// (or a distance/bearing when un-named) + temp + mention count.
class _MicroclimateBubble extends StatelessWidget {
  const _MicroclimateBubble({
    required this.climate,
    required this.mc,
    required this.cs,
    required this.l,
  });

  final Microclimate climate;
  final MeshcoreController mc;
  final ColorScheme cs;
  final AppLocalizations l;

  String _label(FormatPrefs? prefs) {
    if (climate.placeName != null && climate.placeName!.isNotEmpty) {
      return climate.placeName!;
    }
    final double? d = mc.distanceMetersTo(climate.lat, climate.lon);
    final String? fd = d == null ? null : geo.formatDistance(d, prefs: prefs);
    return fd ?? l.wxMicroclimateNearby;
  }

  String? _temp(FormatPrefs? prefs) {
    if (climate.measuredTempC != null) {
      return MmFormat.temperature(climate.measuredTempC!, prefs: prefs);
    }
    if (climate.tempAvgC == null) return null;
    return MmFormat.range(climate.tempMinC!, climate.tempMaxC!, prefs: prefs);
  }

  @override
  Widget build(BuildContext context) {
    final FormatPrefs? prefs = context.formatPrefs;
    final String? t = _temp(prefs);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: mmRadius(context, 20),
        border: Border.all(color: cs.outline.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(climate.dominant != null ? wxGlyph(climate.dominant!) : '🌡',
              style: TextStyle(fontSize: context.skin.type.sizeXl)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_label(prefs),
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: context.skin.type.sizeBodyLg,
                      fontWeight: FontWeight.w600)),
              Text(
                  <String>[
                    if (climate.dominant != null)
                      wxConditionLabel(climate.dominant!, l),
                    if (t != null) climate.measured ? '$t ✓${l.wxMeasured}' : t,
                    '×${climate.mentions}',
                  ].join(' · '),
                  style: TextStyle(
                      color: climate.measured ? cs.tertiary : cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm)),
            ],
          ),
        ],
      ),
    );
  }
}
