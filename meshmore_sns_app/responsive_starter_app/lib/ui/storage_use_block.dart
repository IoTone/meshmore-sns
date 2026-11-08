// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../field/position_history.dart';
import '../gen/app_localizations.dart';
import '../maps/maps_controller.dart';
import '../media/media_journal.dart';
import '../meshcore/chat_store.dart';
import '../meshcore/meshcore_controller.dart';
import '../places/place_store.dart';
import '../theme/mm_skin.dart';
import 'mm_components.dart';

/// What the app is holding, in one place.
///
/// Every store states its own bound — chat keeps 250 rows a thread, places 500,
/// the trail 2000 points over seven days, the media journal one record per
/// unfinished transfer, maps a byte budget — and none of that was visible
/// anywhere but inside the store that owned it. The numbers here are the ones
/// that can be measured honestly: the map store's own byte counter, the sealed
/// history's record size, and the row counts the stores hold in memory. Nothing
/// is estimated, and a store that is not in the tree is absent rather than
/// shown as a zero that would read as "empty".
class StorageUseBlock extends StatelessWidget {
  const StorageUseBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final MapsController? maps = context.watch<MapsController?>();
    final PlaceStore? places = context.watch<PlaceStore?>();
    final PositionRecorder? trail = context.watch<PositionRecorder?>();
    final MediaInterruptions? media = context.watch<MediaInterruptions?>();
    final MeshcoreController? mc = context.watch<MeshcoreController?>();
    final int mapBytes = maps == null ? 0 : maps.tileBytes + maps.archiveBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Line(
          text: maps == null
              ? l.storageMapsUnknown
              : l.storageMaps(_mb(mapBytes), _mb(maps.budgetBytes)),
          skin: skin,
        ),
        if (maps != null) ...<Widget>[
          _Line(
            text:
                l.storageMapsSplit(_mb(maps.viewBytes), _mb(maps.archiveBytes)),
            skin: skin,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MmAction(
                key: const ValueKey<String>('storage-clear-view-cache'),
                icon: Icons.cleaning_services_outlined,
                label: l.storageClearCache,
                dense: true,
                onPressed: () async {
                  await maps.clearViewCache();
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(l.storageCacheCleared)));
                },
              ),
            ),
          ),
        ],
        ValueListenableBuilder<int>(
          valueListenable: ChatStore.bytes,
          builder: (BuildContext _, int bytes, Widget? __) => _Line(
            text: l.storageHistory(_kb(bytes)),
            skin: skin,
          ),
        ),
        // The three stores below are watched rather than read once, so a
        // deletion repaints these lines in the same frame it lands. Absent
        // rather than zero when the store is not in the tree: this block's
        // whole claim is that it states what it can measure.
        if (places != null)
          _Line(
            text: l.storagePlaces(places.all.length, PlaceStore.capacity),
            skin: skin,
          ),
        if (trail != null)
          _Line(
            text: l.storageTrail(
                trail.rows.length, PositionHistoryStore.capacity),
            skin: skin,
          ),
        if (media != null)
          _Line(
            text: l.storageMedia(media.count),
            skin: skin,
          ),
        // Deleting the history is the one act here that cannot be undone, and
        // the dialog is its whole safety: it names both halves — what goes and
        // what the radio keeps — and the confirm stays disabled until the word
        // is typed. Offered only when a controller is present, because the
        // promise the copy makes ("the history this app kept") is false
        // without one.
        if (mc != null)
          Padding(
            // The jobs, not numbers: the gap above the destructive action is a
            // row gap and its left inset is a screen edge, so the action sits
            // on the same rhythm as the lines above it.
            padding: EdgeInsets.fromLTRB(
                skin.space.screenEdge,
                skin.space.rowGap,
                skin.space.screenEdge,
                skin.space.insideText),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MmAction(
                key: const ValueKey<String>('storage-clear-everything'),
                icon: Icons.delete_forever_outlined,
                label: l.storageClearAll,
                dense: true,
                onPressed: () => _clearEverything(context, l,
                    mc: mc,
                    maps: maps,
                    places: places,
                    trail: trail,
                    media: media),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _clearEverything(
    BuildContext context,
    AppLocalizations l, {
    required MeshcoreController mc,
    required MapsController? maps,
    required PlaceStore? places,
    required PositionRecorder? trail,
    required MediaInterruptions? media,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => _ClearEverythingDialog(l: l),
    );
    if (confirmed != true) return;
    // Each store is cleared on its own, under a bounded wait, and the answer is
    // reported either way. Two reasons, both learned the hard way. One store
    // throwing used to abandon the rest and skip the snack, so the user saw a
    // confirmed dialog and then nothing — no sentence, no evidence, no reason.
    // And a clear that never returns (a platform store that stops answering)
    // must not leave the action silent forever: a delete that reports nothing
    // is indistinguishable from one that did nothing.
    //
    // The controller owns the in-memory rows, so it clears both the memory and
    // the sealed record; clearing only the file would let the next inbound
    // message write the history back and make the snack a lie.
    int attempted = 0;
    int unfinished = 0;
    Future<void> step(Future<void>? Function() run) async {
      attempted++;
      try {
        await run()?.timeout(_clearTimeout);
      } catch (_) {
        unfinished++;
      }
    }

    await step(mc.clearAllHistory);
    await step(() async => places?.clear());
    await step(() async => trail?.clear());
    await step(() async => media?.acknowledge());
    await step(() async => maps?.clearViewCache());
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(clearEverythingMessage(l, unfinished, attempted))));
  }

  /// The one sentence the action leaves behind.
  ///
  /// Split out so both halves are provable without a platform store: a host has
  /// no Keystore, so a test can only reach the unfinished branch through the
  /// real action, and the branch a phone takes would otherwise never be
  /// covered at all.
  @visibleForTesting
  static String clearEverythingMessage(
          AppLocalizations l, int unfinished, int attempted) =>
      unfinished == 0
          ? l.storageClearAllDone
          : l.storageClearAllPartly(unfinished, attempted);

  /// How long one store may take before the action calls it unfinished.
  ///
  /// Generous against a slow phone and short enough that a stuck platform
  /// store cannot swallow the confirmation the user is waiting for.
  static const Duration _clearTimeout = Duration(seconds: 15);

  static String _mb(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0);
  static String _kb(int bytes) => (bytes / 1024).toStringAsFixed(0);
}

/// The confirmation for the one destructive action in the app that has no undo.
///
/// A yes/no dialog is the wrong shape for deleting a sealed history: the
/// decision needs the two lists in front of it (what goes, what survives) and
/// a deliberate act, so the confirm is gated on the word the dialog names.
class _ClearEverythingDialog extends StatefulWidget {
  const _ClearEverythingDialog({required this.l});

  final AppLocalizations l;

  @override
  State<_ClearEverythingDialog> createState() => _ClearEverythingDialogState();
}

class _ClearEverythingDialogState extends State<_ClearEverythingDialog> {
  static const String _word = 'DELETE';

  final TextEditingController _typed = TextEditingController();
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() {
      final bool armed = _typed.text.trim() == _word;
      if (armed != _armed) setState(() => _armed = armed);
    });
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = widget.l;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l.storageClearAllTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.storageClearAllGoes),
            const SizedBox(height: 8),
            Text(l.storageClearAllStays,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('storage-clear-all-field'),
              controller: _typed,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                isDense: true,
                labelText: l.storageClearAllTypeWord(_word),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('storage-clear-all-confirm'),
          onPressed: _armed ? () => Navigator.of(context).pop(true) : null,
          child: Text(l.storageClearAllConfirm),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.skin});

  final String text;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Text(
          text,
          style: TextStyle(
              color: skin.color.fgMuted,
              fontSize: skin.type.sizeSm,
              fontFamily: skin.type.monoFamily),
        ),
      );
}
