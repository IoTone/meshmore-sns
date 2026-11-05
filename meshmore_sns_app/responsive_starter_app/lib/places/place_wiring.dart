// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

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
