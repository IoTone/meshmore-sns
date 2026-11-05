// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../chat/channel_read_store.dart';
import '../../chat/unread_counts.dart';
import '../../gen/app_localizations.dart';
import '../../meshcore/block_filter.dart';
import '../../meshcore/block_store.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../places/place.dart';
import '../../places/place_history_sheet.dart';
import '../../places/place_store.dart';
import '../../sos/sos_controller.dart';
import '../../sos/sos_engine.dart';
import '../../telemetry/coverage_session.dart';
import '../../theme/mm_skin.dart';
import '../../ui/dashboard_pins_controller.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_pin_card.dart';
import '../../shell/shell_view_request.dart';

/// The pinned summaries, in the order the user put them.
///
/// One section for every skin: the skin paints the cards, it does not
/// reimplement them, so a card added here exists in all seven presets.
///
/// The section renders nothing when nothing is pinned. That is deliberate:
/// the dashboard is useful before anyone pins anything, and an empty state
/// asking to be filled would be a second job for the home screen.
///
/// A card is a summary and a tap-through. It reads `ChangeNotifier`s that are
/// already provided at the root and never asks the radio on rebuild: a
/// dashboard that polls is worse than the tab it duplicates.
class PinnedCardsSection extends StatefulWidget {
  const PinnedCardsSection({super.key, this.maxHeight});

  /// Bounds the strip for the two skins whose body does not scroll (the radar
  /// and the recon body own their viewport). Null means "as tall as the pins
  /// need".
  final double? maxHeight;

  @override
  State<PinnedCardsSection> createState() => _PinnedCardsSectionState();
}

class _PinnedCardsSectionState extends State<PinnedCardsSection> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final DashboardPinsController? pins =
        context.watch<DashboardPinsController?>();
    if (pins == null || pins.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;

    final List<Widget> cards = <Widget>[
      for (int i = 0; i < pins.pins.length; i++)
        _card(context, pins, pins.pins[i], index: i, l: l),
    ];

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            skin.space.step(5),
            skin.space.step(3),
            skin.space.step(3),
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.dashboardPinsTitle,
                  style: mmSectionLabelStyle(skin),
                ),
              ),
              IconButton(
                tooltip: _editing ? l.dashboardPinsDone : l.dashboardPinsEdit,
                icon: Icon(_editing ? Icons.check : Icons.tune),
                iconSize: skin.type.sizeXl,
                onPressed: () => setState(() => _editing = !_editing),
              ),
            ],
          ),
        ),
        ...cards,
      ],
    );

    final double? max = widget.maxHeight;
    if (max == null) return body;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: max),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _card(
    BuildContext context,
    DashboardPinsController pins,
    String id, {
    required int index,
    required AppLocalizations l,
  }) {
    final MmSkin skin = context.skin;
    final _PinContent c = _contentFor(context, id, l);
    return MmPinCard(
      key: ValueKey<String>('pin-card-$id'),
      title: c.title,
      summary: c.summary,
      trailing: c.trailing,
      leading: c.leading,
      expanded: pins.isOpen(id),
      onToggle: () => pins.setOpen(id, !pins.isOpen(id)),
      onOpen: c.onOpen,
      openLabel: c.openLabel,
      editActions: _editing
          ? <Widget>[
              IconButton(
                key: ValueKey<String>('pin-up-$id'),
                tooltip: l.dashboardPinsMoveUp,
                icon: const Icon(Icons.arrow_upward),
                iconSize: skin.type.sizeXl,
                onPressed: index == 0 ? null : () => pins.move(id, index - 1),
              ),
              IconButton(
                key: ValueKey<String>('pin-down-$id'),
                tooltip: l.dashboardPinsMoveDown,
                icon: const Icon(Icons.arrow_downward),
                iconSize: skin.type.sizeXl,
                onPressed: index == pins.pins.length - 1
                    ? null
                    : () => pins.move(id, index + 1),
              ),
              IconButton(
                key: ValueKey<String>('pin-remove-$id'),
                tooltip: l.dashboardPinsUnpin,
                icon: const Icon(Icons.close),
                iconSize: skin.type.sizeXl,
                onPressed: () => pins.unpin(id),
              ),
            ]
          : const <Widget>[],
      detail: c.detail,
    );
  }

  _PinContent _contentFor(
    BuildContext context,
    String id,
    AppLocalizations l,
  ) {
    switch (id) {
      case MmPinIds.sos:
        return _sos(context, l);
      case MmPinIds.activity:
        return _activity(context, l);
      case MmPinIds.places:
        return _places(context, l);
      case MmPinIds.coverage:
        return _coverage(context, l);
    }
    // Unreachable: the controller drops ids outside MmPinIds.all on load. A
    // card with no content is still a card, so an unknown id renders its own
    // absence rather than throwing inside a dashboard build.
    return _PinContent(title: l.dashboardPinsTitle, summary: l.pinUnavailable);
  }

  _PinContent _sos(BuildContext context, AppLocalizations l) {
    final SosController sos = context.watch<SosController>();
    final String summary;
    final String trailing;
    if (sos.isRunning) {
      final Duration? next = sos.untilNextSend;
      summary = l.pinSosRunning;
      trailing = next == null ? '' : _clock(next);
    } else if (sos.state == SosState.acknowledged) {
      summary = l.pinSosAcknowledged;
      trailing = '';
    } else {
      summary = l.pinSosIdle;
      trailing = '';
    }
    return _PinContent(
      title: l.sosTitle,
      summary: summary,
      trailing: trailing.isEmpty ? null : trailing,
      leading: Icon(
        sos.isRunning ? Icons.emergency : Icons.emergency_outlined,
        color: sos.isRunning
            ? context.skin.color.alert
            : context.skin.color.fgMuted,
        size: context.skin.type.sizeXl,
      ),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sos.isRunning ? l.pinSosDetailRunning : l.pinSosDetailIdle,
            style: TextStyle(
              color: context.skin.color.fgMuted,
              fontSize: context.skin.type.sizeSm,
            ),
          ),
        ],
      ),
      onOpen: () => context.push('/sos'),
      openLabel: l.pinOpenSos,
    );
  }

  _PinContent _activity(BuildContext context, AppLocalizations l) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ChannelReadStore? reads = context.watch<ChannelReadStore?>();
    final BlockStore? blocks = context.watch<BlockStore?>();
    final BlockFilter filter = BlockFilter(blocks ?? BlockStore());
    final Map<int, int> per = UnreadCounts.perChannel(
      channels: mc.channels.map((MapEntry<int, String> e) => e.key),
      history: mc.messagesFor,
      reads: reads,
      filter: filter,
    );
    final int total = per.values.fold<int>(0, (int a, int b) => a + b);
    final int slot = mc.activeChannel;
    // `channels` is a list of entries, so a slot with no name is not an
    // absent map key: it simply has no entry yet.
    String nameOf(int i) => mc.channels
        .firstWhere((MapEntry<int, String> e) => e.key == i,
            orElse: () => MapEntry<int, String>(i, '#$i'))
        .value;
    final String name = nameOf(slot);
    return _PinContent(
      title: l.pinActivityTitle,
      summary: total == 0 ? l.pinActivityNone : l.pinActivityUnread(total),
      trailing: total == 0 ? null : '$total',
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MapEntry<int, int> e in per.entries)
            Padding(
              padding: EdgeInsets.only(bottom: context.skin.space.step(1)),
              child: Text(
                '${nameOf(e.key)} · ${l.pinActivityUnread(e.value)}',
                style: TextStyle(
                  color: context.skin.color.fgMuted,
                  fontSize: context.skin.type.sizeSm,
                ),
              ),
            ),
        ],
      ),
      onOpen: () => context.read<ShellViewRequest?>()?.openChat(slot),
      openLabel: l.pinOpenChat(name),
    );
  }

  _PinContent _places(BuildContext context, AppLocalizations l) {
    final PlaceStore store = context.watch<PlaceStore>();
    final DateTime now = DateTime.now();
    final List<Place> live = <Place>[
      for (final Place p in store.all)
        if (p.isLiveAt(now)) p,
    ];
    return _PinContent(
      title: l.pinPlacesTitle,
      summary: live.isEmpty ? l.pinPlacesNone : l.pinPlacesCount(live.length),
      trailing: live.isEmpty ? null : '${live.length}',
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final Place p in live.take(3))
            Padding(
              padding: EdgeInsets.only(bottom: context.skin.space.step(1)),
              child: Text(
                '${p.label} · ${p.type.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.skin.color.fgMuted,
                  fontSize: context.skin.type.sizeSm,
                ),
              ),
            ),
        ],
      ),
      onOpen: () => PlaceHistorySheet.show(context, store: store),
      openLabel: l.pinOpenPlaces,
    );
  }

  _PinContent _coverage(BuildContext context, AppLocalizations l) {
    final CoverageSession session = context.watch<CoverageSession>();
    final int tried = session.tried;
    final int answered = session.answeredPings;
    return _PinContent(
      title: l.pinCoverageTitle,
      summary: tried == 0
          ? l.pinCoverageNone
          : l.pinCoverageAnswered(answered, tried),
      trailing: tried == 0 ? null : '$answered/$tried',
      detail: Text(
        session.running ? l.pinCoverageRunning : l.pinCoverageIdle,
        style: TextStyle(
          color: context.skin.color.fgMuted,
          fontSize: context.skin.type.sizeSm,
        ),
      ),
      onOpen: () => context.push('/settings/coverage'),
      openLabel: l.pinOpenCoverage,
    );
  }

  static String _clock(Duration d) {
    final int m = d.inMinutes;
    final int s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// What one card shows, resolved before the primitive is built so a card's
/// content is data, not a widget tree the primitive has to know about.
final class _PinContent {
  const _PinContent({
    required this.title,
    required this.summary,
    this.trailing,
    this.leading,
    this.detail = const SizedBox.shrink(),
    this.onOpen,
    this.openLabel,
  });

  final String title;
  final String summary;
  final String? trailing;
  final Widget? leading;
  final Widget detail;
  final VoidCallback? onOpen;
  final String? openLabel;
}
