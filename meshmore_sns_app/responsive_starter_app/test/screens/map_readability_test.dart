// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The Map tab is readable at every text size the app allows.
///
/// The owner's report was that text and buttons on the map were unreadable, and
/// the audit found the reason: control borders were drawn in the *hairline*
/// token, which is 1.30:1 on this preset's surface — a chip and a segmented
/// control were outlined in a colour nobody could see, while the `edge` tier
/// exists precisely because the hairline fails 3:1. The theme now uses `edge`,
/// and this test holds the floor for both the borders and the text.
///
/// It walks the rendered tree rather than a list of hard-coded pairs, so a
/// colour added later is measured without anybody remembering to add it here.

double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double contrast(Color a, Color b) {
  final double la = _lum(a);
  final double lb = _lum(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] composited over [bg] the way the screen composites it.
Color flatten(Color fg, Color bg) => Color.from(
      alpha: 1,
      red: fg.r * fg.a + bg.r * (1 - fg.a),
      green: fg.g * fg.a + bg.g * (1 - fg.a),
      blue: fg.b * fg.a + bg.b * (1 - fg.a),
    );

class _NoPermissions implements PermissionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(false);
}

/// The palette itself, before any widget reads it.
///
/// The hyperlocal preset is the one the owner is looking at, and its text tiers
/// are checked against every layer they can land on: a role that reads well on
/// the page and badly on a raised panel is the same defect one layer up.
void _presetFloors() {
  final MmTokens t = kMmPresets[MmThemePreset.hyperlocal]!;
  for (final (String name, Color layer) in <(String, Color)>[
    ('page', t.base),
    ('surface', t.surface),
    ('raised', t.surfaceAlt),
  ]) {
    for (final (String role, Color ink) in <(String, Color)>[
      ('fg', t.fg),
      ('fgMuted', t.fgMuted),
      ('accent', t.accent),
      ('ok', t.ok),
      ('alertInk', t.alertInk),
    ]) {
      expect(contrast(ink, layer), greaterThanOrEqualTo(4.5),
          reason: '$role on $name');
    }
    expect(contrast(t.edge, layer), greaterThanOrEqualTo(3.0),
        reason: 'a control edge on $name is non-text UI');
    // `alert` stays the fill and the graphic, so it answers to the 3:1 floor.
    expect(contrast(t.alert, layer), greaterThanOrEqualTo(3.0),
        reason: 'the alert fill on $name is a graphic');
  }
}

void main() {
  test('the hyperlocal palette clears its floors on every layer',
      _presetFloors);

  setUp(() {
    // The street map subscribes to the compass; without a handler the missing
    // plugin throws into the test zone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('hemanthraj/flutter_compass'),
            (MethodCall call) async => null);
  });

  for (final double scale in <double>[1.0, 1.3, 2.0]) {
    for (final double width in <double>[320, 411]) {
      testWidgets('map is legible and laid out at ${scale}x on ${width}dp',
          (WidgetTester t) async {
        await t.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));

        // Any overflow is a failure: the map must not stripe or clip controls
        // when the text grows.
        final List<String> overflows = <String>[];
        final void Function(FlutterErrorDetails)? previous =
            FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) {
          final String text = d.exceptionAsString();
          if (text.contains('overflowed')) overflows.add(text.split('\n').first);
        };
        addTearDown(() => FlutterError.onError = previous);

        final FakeMeshcoreTransport fake =
            FakeMeshcoreTransport(connected: true);
        final MeshcoreController mc = MeshcoreController(
          transportFactory: () async => fake,
          locationService: NoopLocationService(),
          connection: MeshcoreConnection(
              handshakeTimeout: const Duration(seconds: 5)),
        );
        final ThemeController theme = ThemeController()
          ..setPreset(MmThemePreset.hyperlocal);
        await t.pumpWidget(MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: theme.theme,
            locale: const Locale('en'),
            supportedLocales: LocaleController.supported,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MultiProvider(
              providers: <SingleChildWidget>[
                ChangeNotifierProvider<MeshcoreController>.value(value: mc),
                ChangeNotifierProvider<ThemeController>.value(value: theme),
                ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
                Provider<PlaceReportBudget>(
                    create: (_) => PlaceReportBudget(clock: DateTime.now)),
                Provider<PermissionsService>.value(value: _NoPermissions()),
                Provider<MapsController?>.value(value: null),
              ],
              child: const Scaffold(body: MapScreen()),
            ),
          ),
        ));
        await mc.connect();
        fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        final Color base = kMmPresets[MmThemePreset.hyperlocal]!.base;
        final List<String> unreadable = <String>[];
        for (final Element e in find.byType(Text).evaluate()) {
          final Text w = e.widget as Text;
          final String label =
              (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('\n', ' ');
          if (label.trim().isEmpty) continue;
          // A chip paints its own fill with a custom render object that is not
          // a Material, so a walk up from the label cannot see it. The chip's
          // pairs are asserted separately, below.
          bool inChip = false;
          e.visitAncestorElements((Element a) {
            if (a.widget is RawChip || a.widget is Chip) {
              inChip = true;
              return false;
            }
            return true;
          });
          if (inChip) continue;

          Color? fg = w.style?.color ?? DefaultTextStyle.of(e).style.color;
          if (fg == null) continue;
          Color bg = base;
          e.visitAncestorElements((Element a) {
            final Widget aw = a.widget;
            Color? c;
            if (aw is ColoredBox) {
              c = aw.color;
            } else if (aw is Material) {
              c = aw.color;
            } else if (aw is DecoratedBox && aw.decoration is BoxDecoration) {
              c = (aw.decoration as BoxDecoration).color;
            } else if (aw is Container) {
              final Decoration? d = aw.decoration;
              if (d is BoxDecoration) c = d.color;
              c ??= aw.color;
            }
            if (c != null && c.a > 0) {
              bg = c.a >= 1 ? c : flatten(c, base);
              return false;
            }
            return true;
          });
          final double r = contrast(flatten(fg, bg), bg);
          if (r < 4.5) {
            unreadable.add('"$label" ${r.toStringAsFixed(2)}:1');
          }
        }
        expect(unreadable, isEmpty,
            reason: 'these labels fail the 4.5:1 floor at ${scale}x on '
                '${width}dp: $unreadable');
        expect(overflows, isEmpty,
            reason: 'the map overflowed at ${scale}x on ${width}dp: '
                '$overflows');

        // The chip pairs, measured from the theme it actually renders with.
        final ChipThemeData chips = theme.theme.chipTheme;
        expect(
            contrast(chips.labelStyle!.color!, base), greaterThanOrEqualTo(4.5),
            reason: 'an unselected chip label must clear 4.5:1 on the page');
        expect(
            contrast(chips.secondaryLabelStyle!.color!,
                chips.selectedColor ?? base),
            greaterThanOrEqualTo(4.5),
            reason: 'a selected chip label sits on the accent fill');
        // And the chip's own border, which is the defect the audit found.
        expect(contrast(chips.side!.color, base), greaterThanOrEqualTo(3.0),
            reason: 'a control border is non-text UI, so its floor is 3:1');

        mc.dispose();
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 30));
      });
    }
  }
}
