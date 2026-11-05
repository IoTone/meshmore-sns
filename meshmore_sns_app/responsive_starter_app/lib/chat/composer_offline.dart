// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';

/// What a composer shows when there is no radio to send through.
///
/// A disabled text field whose hint says "connect a radio" is a dead end: the
/// only route out is a different screen's link chip. This says the state and
/// carries the action, so the way forward is where the user already is.
class ComposerOffline extends StatelessWidget {
  const ComposerOffline({super.key, required this.connecting});

  /// True while a connect is already in flight. The action is withdrawn then,
  /// because a second tap would start a second attempt, and the line says what
  /// is happening instead.
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    // The state and its action stack when the width cannot hold them side by
    // side: at 320 dp with text at 200 % a Row clips the button off the edge,
    // and a control that cannot be reached is worse than a taller one.
    final Widget state = Text(
      connecting ? l.chatConnecting : l.chatNoRadio,
      style: TextStyle(
        color: skin.color.fgMuted,
        fontSize: skin.type.sizeBody,
      ),
    );
    final Widget? connect = connecting
        ? null
        : FilledButton.tonalIcon(
            key: const ValueKey<String>('composer-connect'),
            onPressed: () => context.push('/pair'),
            icon: const Icon(Icons.bluetooth, size: 18),
            label: Text(l.chatConnectRadio),
          );
    // A wrap, not a row: at 320 dp with text at 200 % the button does not fit
    // beside the sentence, and a control clipped off the edge cannot be
    // reached. The wrap moves it to its own line when it must.
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        state,
        if (connect != null) connect,
      ],
    );
  }
}
