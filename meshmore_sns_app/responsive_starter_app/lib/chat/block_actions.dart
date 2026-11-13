// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/block_store.dart';
import '../ui/mm_confirm.dart';

/// Blocking a key, from the place the reader met it.
///
/// The app could *unblock* from Settings and nothing else: `BlockStore.block`
/// had no caller in `lib/`, so the blocked-keys screen explained a feature no
/// screen in the app could reach. A block is a decision made while reading a
/// message or looking at a node, so the offer lives on the row and the sheet,
/// and this is the one confirmation both of them use.
///
/// The sentence matters as much as the button: a block is this app's filter. The
/// radio still receives and relays the packet, and nobody on the mesh learns
/// anything — someone who blocks expecting the traffic to stop has been misled
/// by their own app.
Future<bool> confirmAndBlock(
  BuildContext context, {
  required String pubKeyHex,
  String? name,
}) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final BlockStore? store = context.read<BlockStore?>();
  if (store == null) return false;
  final bool ok = await mmConfirm(
    context,
    title: l.blockConfirmTitle,
    body: name == null ? l.blockConfirmBody : '$name\n\n${l.blockConfirmBody}',
    cancelLabel: l.actionCancel,
    confirmLabel: l.blockConfirmGo,
    // Not destructive: nothing is deleted. What stops is what this device shows.
    destructive: false,
  );
  if (!ok || !context.mounted) return false;
  final bool added = await store.block(BlockedKey(
    pubKeyHex: pubKeyHex.toLowerCase(),
    sinceMs: DateTime.now().millisecondsSinceEpoch,
    name: name,
  ));
  if (!context.mounted) return added;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(added ? l.blockDone : l.blockFull),
      duration: const Duration(seconds: 3)));
  return added;
}
