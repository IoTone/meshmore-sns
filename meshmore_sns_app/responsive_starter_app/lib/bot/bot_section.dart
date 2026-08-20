// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import 'bot_controller.dart';
import 'bot_guards.dart';
import 'bot_scope.dart';
import 'bot_scope_config.dart';
import 'responder.dart';

/// The bot section for one scope (R59).
///
/// Shared between the per-channel dialog and the per-peer sheet, so
/// both answer the same question in the same words: when this
/// conversation receives a message, do we answer it?
///
/// When the scope is ineligible the section still renders, showing the
/// **reason**. The spec asks for a structural refusal rather than a
/// hidden control, and a control that vanishes teaches nobody why —
/// "the bot cannot run on Public" is the thing worth saying.
class BotSection extends StatelessWidget {
  const BotSection({super.key, required this.scope});

  final BotScope scope;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final BotController bot = context.watch<BotController>();
    final BotRefusal? refusal = bot.refusalFor(scope);
    final bool on = bot.isEnabled(scope);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l.botTitle),
          subtitle: Text(refusal == null
              ? l.botSubtitle
              : _refusalText(l, refusal)),
          value: on,
          // Refused scopes present a dead switch rather than no switch:
          // the reason is in the subtitle, where it can be read.
          onChanged: refusal != null
              ? null
              : (bool v) => bot.setEnabled(scope, v),
        ),
        if (on && refusal == null) ...<Widget>[
          Text(l.botOnWire,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _ModePicker(scope: scope),
          const SizedBox(height: 4),
          _Instrumentation(scope: scope),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.rule, size: 16),
              label: Text(l.botEditRules),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (BuildContext _) => RulepackEditor(scope: scope),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _refusalText(AppLocalizations l, BotRefusal r) =>
      switch (r) {
        BotRefusal.publicSlot => l.botRefusedPublicSlot,
        BotRefusal.publicPsk => l.botRefusedPublicPsk,
        BotRefusal.unknownPsk => l.botRefusedUnknownPsk,
      };
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.scope});
  final BotScope scope;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final BotController bot = context.watch<BotController>();
    final BotMode mode = bot.bindingFor(scope).mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l.botMode,
            style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SegmentedButton<BotMode>(
          segments: <ButtonSegment<BotMode>>[
            ButtonSegment<BotMode>(
                value: BotMode.deterministic,
                label: Text(l.botModeDeterministic)),
            ButtonSegment<BotMode>(
                value: BotMode.random, label: Text(l.botModeRandom)),
          ],
          selected: <BotMode>{mode},
          showSelectedIcon: false,
          onSelectionChanged: (Set<BotMode> s) =>
              bot.setMode(scope, s.first),
        ),
        const SizedBox(height: 2),
        Text(
          mode == BotMode.deterministic
              ? l.botModeDeterministicSub
              : l.botModeRandomSub,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        // The seed is only meaningful in random mode, and it is shown
        // rather than hidden: a "random" soak that cannot be replayed
        // from its seed is not evidence of anything.
        if (mode == BotMode.random) ...<Widget>[
          const SizedBox(height: 6),
          _SeedField(scope: scope),
        ],
      ],
    );
  }
}

class _SeedField extends StatefulWidget {
  const _SeedField({required this.scope});
  final BotScope scope;

  @override
  State<_SeedField> createState() => _SeedFieldState();
}

class _SeedFieldState extends State<_SeedField> {
  late final TextEditingController _c = TextEditingController(
      text: '${context.read<BotController>().bindingFor(widget.scope).seed}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      width: 180,
      child: TextField(
        controller: _c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l.botSeed,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (String v) {
          final int? seed = int.tryParse(v.trim());
          if (seed == null) return;
          context.read<BotController>().setSeed(widget.scope, seed);
        },
      ),
    );
  }
}

/// Remaining budget and the soak counters.
///
/// Surfaced rather than enforced silently: a bot that has gone quiet
/// should be able to say why without the operator reading logs.
class _Instrumentation extends StatelessWidget {
  const _Instrumentation({required this.scope});
  final BotScope scope;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final BotController bot = context.watch<BotController>();
    final BotCounters c = bot.countersFor(scope);
    final int left = bot.remainingBudgetFor(scope);
    final int held =
        c.suppressedOwn + c.suppressedLoop + c.suppressedRate + c.noMatch;

    final TextStyle mono = TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 11,
        color: cs.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l.botBudget(left),
            style: mono.copyWith(
                color: left == 0 ? cs.error : cs.onSurfaceVariant)),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                  l.botCounters(c.received, c.replied, held),
                  style: mono),
            ),
            TextButton(
              onPressed: () => bot.resetCounters(scope),
              child: Text(l.botResetCounters,
                  style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }
}
