// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../field/field_export_action.dart';
import '../gen/app_localizations.dart';
import '../telemetry/coverage_model.dart';
import '../telemetry/coverage_pacing.dart';
import '../telemetry/coverage_session.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// Settings → Tools → Coverage, or the field screen.
///
/// The screen says exactly what the record is: pings this device sent, and
/// whether anything answered them. It is not a map of the mesh, and the copy
/// is written so it cannot be read as one
/// (`meshmore-telemetry-coverage-spec.md` §10).
class CoverageScreen extends StatelessWidget {
  const CoverageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final CoverageSession s = context.watch<CoverageSession>();

    return Scaffold(
      appBar: AppBar(title: Text(l.coverageTitle)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.all(skin.space.step(5)),
          children: <Widget>[
            Text(
              l.coverageBeforeStart,
              key: const ValueKey<String>('coverage-before-start'),
              style: TextStyle(
                  color: skin.color.fgMuted,
                  fontSize: skin.type.sizeBody,
                  height: 1.5),
            ),
            SizedBox(height: skin.space.step(4)),
            if (!s.running)
              MmAction(
                key: const ValueKey<String>('coverage-start'),
                icon: Icons.play_arrow,
                label: l.coverageStart,
                onPressed: s.start,
              )
            else ...<Widget>[
              MmAction(
                key: const ValueKey<String>('coverage-stop'),
                icon: Icons.stop,
                label: l.coverageStop,
                onPressed: s.stop,
              ),
              SizedBox(height: skin.space.step(4)),
              Text(
                l.coverageCounts(s.answeredPings, s.tried),
                key: const ValueKey<String>('coverage-counts'),
                style: TextStyle(
                    color: skin.color.fg,
                    fontSize: skin.type.sizeBodyLg,
                    fontWeight: FontWeight.w600),
              ),
              if (s.unmatched > 0)
                Text(l.coverageUnmatched(s.unmatched),
                    key: const ValueKey<String>('coverage-unmatched'),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm)),
              if (s.lastRefusal != null)
                Text(_refusalCopy(l, s.lastRefusal!),
                    key: const ValueKey<String>('coverage-refusal'),
                    style: TextStyle(
                        color: skin.color.alert, fontSize: skin.type.sizeSm)),
              SizedBox(height: skin.space.step(3)),
              Text(l.coveragePacingNote,
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
              SizedBox(height: skin.space.step(2)),
              MmAction(
                key: const ValueKey<String>('coverage-ping'),
                icon: Icons.cell_tower,
                label: l.coveragePingNow,
                onPressed: s.busy ? null : () => s.ping(manual: true),
              ),
              SizedBox(height: skin.space.step(5)),
              MmSectionHeader(l.coverageCellsSection),
              if (s.samples.isEmpty)
                Text(l.coverageNoSamples,
                    key: const ValueKey<String>('coverage-empty'),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm))
              else
                for (final CoverageCellSummary c in s.summaries())
                  _CellRow(summary: c),
              if (s.samples.isNotEmpty) ...<Widget>[
                SizedBox(height: skin.space.step(3)),
                Text(l.coverageEdges(s.edges().length),
                    key: const ValueKey<String>('coverage-edges'),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm)),
                Text(l.coverageNotAMap,
                    style: TextStyle(
                        color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
              ],
              SizedBox(height: skin.space.step(5)),
              MmSectionHeader(l.fieldExportSection),
              Text(l.fieldExportExplainer,
                  key: const ValueKey<String>('field-export-explainer'),
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm,
                      height: 1.4)),
              SizedBox(height: skin.space.step(2)),
              const FieldExportAction(),
            ],
          ],
        ),
      ),
    );
  }

  static String _refusalCopy(
      AppLocalizations l, CoveragePacingRefusal refusal) {
    switch (refusal) {
      case CoveragePacingRefusal.tooSoon:
        return l.coverageRefusedTooSoon;
      case CoveragePacingRefusal.cellFresh:
        return l.coverageRefusedCellFresh;
      case CoveragePacingRefusal.manualAlreadyUsed:
        return l.coverageRefusedManualUsed;
    }
  }
}

class _CellRow extends StatelessWidget {
  const _CellRow({required this.summary});

  final CoverageCellSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final int percent = (summary.score * 100).round();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: skin.space.step(1)),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l.coverageCellLine(summary.cell, percent, summary.samples),
              style: TextStyle(
                  color: skin.color.fg, fontSize: skin.type.sizeBody),
            ),
          ),
          if (summary.hidden > 0)
            Text(l.coverageHidden(summary.hidden),
                key: ValueKey<String>('coverage-hidden-${summary.cell}'),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
        ],
      ),
    );
  }
}
