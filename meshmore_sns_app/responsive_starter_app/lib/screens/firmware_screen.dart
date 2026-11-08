// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart'
    show CapabilityState, FirmwareOta, OtaStartRefusal;
import 'package:provider/provider.dart';

import '../app_state_model.dart';
import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';

/// What the radio is running, and what this app will do about it.
///
/// D8.19's decision was **status only**: an install consumes the companion's
/// offline queue down to a handful of frames (`MyMesh.cpp:607-611`), and until
/// this app can re-sync the messages the radio would discard it must not start
/// one. That refusal is a value (`OtaStartRefusal`) rather than an exception a
/// caller can swallow, and this page writes it out in the words the app uses
/// for every other thing it declines to do: what it would cost.
///
/// No button installs, and none pretends to check: the capability state is what
/// the radio's own answers have already established, so a page that has never
/// spoken to a radio says exactly that.
class FirmwareScreen extends StatelessWidget {
  const FirmwareScreen({super.key});

  String _otaLine(AppLocalizations l, CapabilityState state) => switch (state) {
        CapabilityState.supported => l.firmwareOtaSupported,
        CapabilityState.absent => l.firmwareOtaAbsent,
        CapabilityState.unknown => l.firmwareOtaUnknown,
      };

  /// The gate's answer as one sentence, read from the gate rather than
  /// restated, so the page cannot describe a decision that has moved.
  String _refusalLine(AppLocalizations l, OtaStartRefusal? refusal) =>
      switch (refusal) {
        null => l.firmwareNoInstallWhy,
        OtaStartRefusal.queueDrainUnhandled => l.firmwareNoInstallWhy,
        OtaStartRefusal.unsupportedByFirmware => l.firmwareOtaAbsent,
        OtaStartRefusal.capabilityUnknown => l.firmwareOtaUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppState app = context.watch<AppState>();
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String radioFirmware = mc.deviceInfo == null
        ? '—'
        : '${mc.deviceInfo!.firmwareVersion} · '
            '${mc.deviceInfo!.firmwareBuildDate}';

    Widget row(String label, String value) => Padding(
          padding: EdgeInsets.symmetric(vertical: skin.space.labelToControl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                // The label column, at the width the Device page's own rows
                // use, so a value starts at the same offset on both pages.
                width: 88 * MediaQuery.textScalerOf(context).scale(1),
                child: Text(label,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: skin.type.sizeSm)),
              ),
              Expanded(
                child: Text(value,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontFamily: skin.type.monoFamily,
                        height: 1.4)),
              ),
            ],
          ),
        );

    final OtaStartRefusal? refusal =
        const FirmwareOta().startRefusalFor(mc.capabilities);

    return Scaffold(
      appBar: AppBar(title: Text(l.firmwareTitle)),
      body: MmScaffold(
        child: ListView(
          padding: skin.space.padScreen,
          children: <Widget>[
            Text(l.firmwareIntro,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
            SizedBox(height: skin.space.sectionGap),
            row(l.firmwareRadioLabel, radioFirmware),
            row(l.firmwareOtaLabel,
                _otaLine(l, mc.capabilities.stateOf(FirmwareOta.control))),
            row(l.firmwareAppLabel, app.getAppVersion()),
            SizedBox(height: skin.space.sectionGap),
            Text(l.firmwareNoInstallWhy,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
            SizedBox(height: skin.space.rowGap),
            Text(_refusalLine(l, refusal),
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: skin.type.sizeSm,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
