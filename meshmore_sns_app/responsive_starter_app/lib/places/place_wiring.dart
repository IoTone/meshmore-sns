// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../meshcore/block_store.dart';
import '../meshcore/meshcore_controller.dart';
import 'place_report_budget.dart';
import 'place_sender.dart';
import 'place_store.dart';

/// The composer every place surface uses, built from the app-scoped store, the
/// send-side budget and the live radio.
///
/// One function so a screen cannot accidentally build a second budget (which
/// would double the 6-per-hour allowance) or a sender bound to another channel.
PlaceComposer placeComposerOf(BuildContext context, {int? channelIdx}) =>
    PlaceComposer(
      store: context.read<PlaceStore>(),
      budget: context.read<PlaceReportBudget>(),
      sender: ChannelPlaceSender(
        context.read<MeshcoreController>(),
        channelIdx: channelIdx,
      ),
    );

/// A block takes the reporter's stored places with it (`meshmore-places-spec.md`
/// §10).
///
/// Hiding a blocked reporter's rows at read time is not enough: the rows would
/// still be on disk, and the history list, the ledger export and search all
/// read the store rather than the map. So the rows are deleted on the block,
/// and again whenever the list changes, because a blocked key can also arrive
/// from a restored export or a reload.
///
/// Returns the detach function for a caller that needs to stop listening.
VoidCallback attachPlaceBlockDeletion(BlockStore blocks, PlaceStore places) {
  void drop() {
    for (final BlockedKey key in blocks.all) {
      places.deleteByReporterKey(key.pubKeyHex);
    }
  }

  blocks.addListener(drop);
  drop();
  return () => blocks.removeListener(drop);
}
