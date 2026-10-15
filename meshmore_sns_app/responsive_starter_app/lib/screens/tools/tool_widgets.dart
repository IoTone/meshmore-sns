// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../tools/mesh_tool.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_scaffold.dart';

/// One sentence per [ToolFailure] (spec rule 7: never a bare "failed").
String toolFailureText(AppLocalizations l, ToolFailure f) => switch (f) {
      ToolFailure.notConnected => l.toolFailNotConnected,
      ToolFailure.busy => l.toolFailBusy,
      ToolFailure.unsupported => l.toolFailUnsupported,
      ToolFailure.notFound => l.toolFailNotFound,
      ToolFailure.tableFull => l.toolFailTableFull,
      ToolFailure.rejected => l.toolFailRejected,
      ToolFailure.noConfirm => l.toolFailNoConfirm,
      ToolFailure.publicScope => l.toolFailPublic,
      ToolFailure.unknownChannel => l.toolFailUnknownChannel,
      ToolFailure.noTarget => l.toolFailNoTarget,
    };

String fmtDb(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

String fmtDuration(AppLocalizations l, Duration d) => d.inSeconds >= 60 &&
        d.inSeconds % 60 == 0
    ? l.toolsMinutes(d.inMinutes)
    : l.toolsSeconds(d.inSeconds);

/// The shared skeleton of every tool screen (spec "Information
/// architecture"): an offline banner, setup, one primary action,
/// a failure line, then results.
class ToolPage extends StatelessWidget {
  const ToolPage({
    super.key,
    required this.title,
    required this.tool,
    required this.children,
    this.actions = const <Widget>[],
  });

  final String title;
  final MeshTool tool;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ready = context.select<MeshcoreController, bool>(
        (MeshcoreController mc) => mc.isReady);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: MmScaffold(
        child: ListenableBuilder(
          listenable: tool,
          builder: (BuildContext context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              if (!ready) ...<Widget>[
                ToolNotice(text: l.toolsOffline, icon: Icons.link_off),
                const SizedBox(height: 12),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + text strip; alert-coloured but never colour-only (R13).
class ToolNotice extends StatelessWidget {
  const ToolNotice({
    super.key,
    required this.text,
    this.icon = Icons.error_outline,
    this.alert = true,
  });

  final String text;
  final IconData icon;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final Color c = alert ? skin.color.alert : skin.color.fgMuted;
    return MmPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: skin.color.fg, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// The failure of the last run, if any.
class ToolFailureLine extends StatelessWidget {
  const ToolFailureLine(this.tool, {super.key});
  final MeshTool tool;

  @override
  Widget build(BuildContext context) {
    final ToolFailure? f = tool.failure;
    if (f == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ToolNotice(text: toolFailureText(AppLocalizations.of(context), f)),
    );
  }
}

/// Start ⇄ Stop, plus an optional copy action.
class ToolActionRow extends StatelessWidget {
  const ToolActionRow({
    super.key,
    required this.tool,
    required this.onStart,
    this.startLabel,
    this.copyLabel,
    this.copyText,
  });

  final MeshTool tool;
  final VoidCallback? onStart;
  final String? startLabel;
  final String? copyLabel;

  /// Builds the clipboard payload; null hides the copy action.
  final String Function()? copyText;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ready = context.select<MeshcoreController, bool>(
        (MeshcoreController mc) => mc.isReady);
    return Row(
      children: <Widget>[
        Expanded(
          child: tool.running
              ? FilledButton.icon(
                  icon: const Icon(Icons.stop),
                  label: Text(l.toolsStop),
                  onPressed: tool.stop,
                )
              : FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(startLabel ?? l.toolsStart),
                  onPressed: ready ? onStart : null,
                ),
        ),
        if (copyText != null) ...<Widget>[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: Text(copyLabel ?? l.toolsCopyReport),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyText!()));
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(l.toolsCopied)));
            },
          ),
        ],
      ],
    );
  }
}

/// A labelled setup row: `LABEL   [ control ]`.
class ToolField extends StatelessWidget {
  const ToolField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(label,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: 11,
                    letterSpacing: 1.5)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A dropdown of [values] shown through [label]; disabled while
/// [enabled] is false (setup is locked during a run).
class ToolChoice<T> extends StatelessWidget {
  const ToolChoice({
    super.key,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DropdownButton<T>(
        value: values.contains(value) ? value : null,
        isDense: true,
        onChanged: enabled
            ? (T? v) {
                if (v != null) onChanged(v);
              }
            : null,
        items: <DropdownMenuItem<T>>[
          for (final T v in values)
            DropdownMenuItem<T>(value: v, child: Text(label(v))),
        ],
      ),
    );
  }
}

/// A tappable target that opens a picker.
class ToolPickerButton extends StatelessWidget {
  const ToolPickerButton({
    super.key,
    required this.text,
    required this.onTap,
  });
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.arrow_drop_down),
        label: Text(text, overflow: TextOverflow.ellipsis),
        onPressed: onTap,
      ),
    );
  }
}

/// Monospace line for results.
class ToolLine extends StatelessWidget {
  const ToolLine(this.text, {super.key, this.muted = false, this.leading});
  final String text;
  final bool muted;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: skin.type.monoFamily,
                fontSize: 12.5,
                color: muted ? skin.color.fgMuted : skin.color.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ✓ / ✕ / … glyph for an attempt (shape, not just colour — R13).
Widget outcomeIcon(BuildContext context, bool? ok) {
  final MmSkin skin = context.skin;
  return switch (ok) {
    true => Icon(Icons.check, size: 16, color: skin.color.ok),
    false => Icon(Icons.close, size: 16, color: skin.color.alert),
    null => Icon(Icons.more_horiz, size: 16, color: skin.color.fgMuted),
  };
}
