// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../maps/maps_controller.dart';
import '../meshcore/chat_store.dart';
import '../theme/mm_skin.dart';
import 'mm_components.dart';

/// What the app is holding, in one place.
///
/// Every store states its own bound — chat keeps 250 rows a thread, places 500,
/// the trail 2000 points, media 16 transfers, maps a byte budget — and none of
/// that was visible anywhere but inside the store that owned it. The numbers
/// here are the ones that can be measured honestly: the map store's own byte
/// counter and the sealed history's record size. Nothing is estimated, and a
/// store that cannot measure itself is absent rather than guessed at.
class StorageUseBlock extends StatelessWidget {
  const StorageUseBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final MapsController? maps = context.watch<MapsController?>();
    final int mapBytes =
        maps == null ? 0 : maps.tileBytes + maps.archiveBytes;
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
            text: l.storageMapsSplit(
                _mb(maps.viewBytes), _mb(maps.archiveBytes)),
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
      ],
    );
  }

  static String _mb(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0);
  static String _kb(int bytes) => (bytes / 1024).toStringAsFixed(0);
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
