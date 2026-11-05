// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/block_store.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';
import '../util/clock_model.dart';

/// The blocked keys this device holds, and the one action that matters there:
/// unblock.
///
/// APP-F3 is why the footer exists: a block is the app's own filter, so the
/// copy has to say what it cannot stop - the radio still receives and relays
/// the packet - instead of letting a reader believe a key was cut off the air.
class BlockedKeysScreen extends StatelessWidget {
  const BlockedKeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final BlockStore store = context.watch<BlockStore>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<BlockedKey> keys = store.all.toList()
      ..sort((BlockedKey a, BlockedKey b) => b.sinceMs.compareTo(a.sinceMs));

    return Scaffold(
      appBar: AppBar(title: Text(l.blockedKeysTitle)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                skin.space.step(4),
                skin.space.step(3),
                skin.space.step(4),
                skin.space.step(2),
              ),
              child: Text(
                l.blockedKeysSubtitle(keys.length),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: skin.type.sizeSm,
                ),
              ),
            ),
            if (store.unreadable)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: skin.space.step(4)),
                child: Text(
                  l.blockedKeysUnreadable,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: skin.type.sizeSm,
                  ),
                ),
              )
            else if (!store.persisted)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: skin.space.step(4)),
                child: Text(
                  l.blockedKeysNotPersisted,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: skin.type.sizeSm,
                  ),
                ),
              ),
            if (keys.isEmpty)
              Padding(
                padding: EdgeInsets.all(skin.space.step(4)),
                child: Text(
                  l.blockedKeysEmpty,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: skin.type.sizeBody,
                  ),
                ),
              )
            else
              for (final BlockedKey k in keys)
                ListTile(
                  key: ValueKey<String>('blocked-${k.pubKeyHex}'),
                  leading: Icon(Icons.block, color: cs.error),
                  title: Text(k.name ?? l.blockedKeysUnknownName),
                  subtitle: Text(
                    '${k.pubKeyHex.substring(0, 12)}'
                    '  ·  ${l.blockedKeysSince(clockStamp(l, DateTime.fromMillisecondsSinceEpoch(k.sinceMs)))}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: skin.type.sizeSm,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      // The list is the answer to the press: it removes the
                      // entry and notifies before the write, so the row goes
                      // and the confirmation appears without waiting on disk.
                      final String? name = k.name;
                      unawaited(store.unblock(k.pubKeyHex));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(name == null
                              ? l.blockedKeysUnblockedUnnamed
                              : l.blockedKeysUnblocked(name)),
                        ),
                      );
                    },
                    child: Text(l.blockedKeysUnblock),
                  ),
                ),
            if (store.atCapacity)
              Padding(
                padding: EdgeInsets.all(skin.space.step(4)),
                child: Text(
                  l.blockedKeysCapacity(BlockStore.capacity),
                  style: TextStyle(
                    color: cs.error,
                    fontSize: skin.type.sizeSm,
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.all(skin.space.step(4)),
              child: Text(
                l.blockedKeysCannotStop,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: skin.type.sizeSm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
