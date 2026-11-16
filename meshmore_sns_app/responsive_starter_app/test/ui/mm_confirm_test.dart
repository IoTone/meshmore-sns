// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/ui/mm_confirm.dart';

/// The one confirmation dialog (R130).
///
/// Seventeen screens had written this by hand, and the confirm's affordance
/// drifted while they did: a deletion was a filled button on two screens, a
/// plain label on a third, and the region-pack delete had no title at all. The
/// property these cases pin is the one that makes the class usable: a
/// destructive confirm looks destructive, a non-destructive one does not, and
/// nothing except the confirm returns true.
void main() {
  ThemeData themeFor(MmThemePreset p) {
    final MmSkin s = mmSkinFor(p);
    return buildMmTheme(s.color,
        fontFamily: s.type.displayFamily, shape: s.shape);
  }

  /// Pumps a page whose only control opens the dialog and records the answer.
  Future<List<bool>> pumpConfirm(
    WidgetTester t, {
    required bool destructive,
  }) async {
    final List<bool> answers = <bool>[];
    await t.pumpWidget(MaterialApp(
      theme: themeFor(MmThemePreset.seele),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answers.add(await mmConfirm(
                  context,
                  title: 'Delete this?',
                  body: 'It cannot be undone.',
                  cancelLabel: 'Cancel it',
                  confirmLabel: 'Delete it',
                  destructive: destructive,
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return answers;
  }

  testWidgets('the title, the body and both labels are the ones passed in',
      (WidgetTester t) async {
    await pumpConfirm(t, destructive: false);
    expect(find.text('Delete this?'), findsOneWidget);
    expect(find.text('It cannot be undone.'), findsOneWidget);
    expect(find.text('Cancel it'), findsOneWidget);
    expect(find.text('Delete it'), findsOneWidget);
  });

  testWidgets('a destructive confirm carries the error tone, and confirming '
      'answers true', (WidgetTester t) async {
    final List<bool> answers = await pumpConfirm(t, destructive: true);
    final FilledButton confirm =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete it'));
    final ColorScheme cs = themeFor(MmThemePreset.seele).colorScheme;
    expect(confirm.style?.backgroundColor?.resolve(<WidgetState>{}),
        cs.errorContainer,
        reason: 'a delete must not look like the ordinary yes');
    expect(confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
        cs.onErrorContainer);

    await t.tap(find.text('Delete it'));
    await t.pumpAndSettle();
    expect(answers, <bool>[true]);
  });

  testWidgets('a plain confirm stays a plain filled action',
      (WidgetTester t) async {
    await pumpConfirm(t, destructive: false);
    final FilledButton confirm =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete it'));
    expect(confirm.style, isNull,
        reason: 'only a destructive act gets the error tone');
  });

  testWidgets('cancelling answers false', (WidgetTester t) async {
    final List<bool> answers = await pumpConfirm(t, destructive: true);
    await t.tap(find.text('Cancel it'));
    await t.pumpAndSettle();
    expect(answers, <bool>[false]);
  });

  testWidgets('a barrier tap answers false rather than dismiss-into-yes',
      (WidgetTester t) async {
    final List<bool> answers = await pumpConfirm(t, destructive: true);
    // The dialog's barrier is the only thing outside it.
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    expect(find.text('Delete this?'), findsNothing);
    expect(answers, <bool>[false]);
  });

  testWidgets('the back gesture answers false', (WidgetTester t) async {
    final List<bool> answers = await pumpConfirm(t, destructive: true);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Delete this?'), findsNothing);
    expect(answers, <bool>[false]);
  });

  testWidgets('a dialog with no title renders one, and none is invented',
      (WidgetTester t) async {
    // The region-pack delete never had a title; inventing one here would have
    // changed what that dialog says.
    await t.pumpWidget(MaterialApp(
      theme: themeFor(MmThemePreset.seele),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => mmConfirm(
                context,
                body: 'Only a body',
                cancelLabel: 'Cancel',
                confirmLabel: 'Go',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final AlertDialog dialog =
        t.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.title, isNull);
    expect(find.text('Only a body'), findsOneWidget);
  });
}
