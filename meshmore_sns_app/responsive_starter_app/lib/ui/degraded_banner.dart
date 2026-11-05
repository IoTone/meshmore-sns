// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

import '../app/degraded_state.dart';
import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';

/// APP-N4 — what is degraded, said once, where the reader already looks.
///
/// The widget renders a [DegradedState] the caller observed; it does not read
/// the radio itself, because a banner is only honest if the same state can be
/// handed to it in a test. [DashboardScreen] is the observer today: it knows
/// the link state and, through the stats tool, the radio's own battery
/// reading. A state nothing observes (no location, no tiles) is left out of
/// the set rather than guessed — `DegradedState.observe` takes only what was
/// measured.
class DegradedBanner extends StatelessWidget {
  const DegradedBanner({super.key, required this.state});

  final DegradedState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isDegraded) return const SizedBox.shrink();
    final MmSkin skin = context.skin;
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(skin.space.step(4)),
      margin: EdgeInsets.only(bottom: skin.space.step(5)),
      decoration: BoxDecoration(
        color: skin.color.surfaceAlt,
        border: Border(left: BorderSide(color: skin.color.alert, width: 3)),
        borderRadius: BorderRadius.circular(skin.shape.cornerSize),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: skin.color.alert),
          SizedBox(width: skin.space.step(3)),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                state.text(l),
                style: TextStyle(
                  color: skin.color.fg,
                  fontSize: skin.type.sizeBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
