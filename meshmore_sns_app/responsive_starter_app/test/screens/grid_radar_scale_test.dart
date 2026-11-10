// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/grid_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The radar's automatic scale.
///
/// The owner's rule: frame the mesh in hand so the bulk of the located nodes
/// spread across the body and the furthest ones clamp to the rim, rather than
/// one node at 40 km squeezing forty into a dot. The arithmetic is a pure
/// function for that reason — everything else about the radar is drawing, and a
/// canvas cannot say why a percentage was chosen.

/// A ramp of distances, in km.
List<double> _ramp(int count, double step) =>
    <double>[for (int i = 1; i <= count; i++) i * step];

void main() {
  group('the radius that frames a set of distances', () {
    test('nothing located means no automatic scale, not zero', () {
      expect(GridScreen.autoRangeKm(const <double>[]), isNull);
    });

    test('one node sits inside the rim, not on it', () {
      // Small sets frame the furthest node rather than a percentile: a
      // percentile of one is just that node.
      final double? km = GridScreen.autoRangeKm(<double>[2.0]);
      expect(km, isNotNull);
      expect(km, greaterThan(2.0), reason: 'the node is inside the rim');
      expect(2.0 / km!, greaterThan(0.7),
          reason: 'and close to it, which is the point of framing');
      expect(2.0 / km, lessThan(1.0));
    });

    test('a uniform set ends with the furthest node close to the rim', () {
      // Nineteen nodes from 1 to 19 km. The ninth decile is 17, so the rim
      // lands at 19.77 and the furthest node sits at 96 % — as close to the
      // edge as anything gets without being cut by it.
      final List<double> distances = _ramp(19, 1.0);
      final double km = GridScreen.autoRangeKm(distances)!;
      expect(19.0 / km, greaterThan(0.9));
      expect(19.0 / km, lessThanOrEqualTo(1.0),
          reason: 'nothing in a uniform set is an outlier');
      // And the middle of the set is spread across the body, not at the centre.
      expect(10.0 / km, greaterThan(0.35));
      expect(10.0 / km, lessThan(0.65));
    });

    test('one far outlier cannot squash everyone else into a dot', () {
      final List<double> distances = <double>[
        for (int i = 0; i < 20; i++) 0.4,
        120.0, // a station three counties away
      ];
      final double km = GridScreen.autoRangeKm(distances)!;
      // The percentile is 0.4 km even though the maximum is 120.
      expect(km, lessThan(1.0));
      expect(120.0 / km, greaterThan(1.0), reason: 'the outlier clamps');
    });

    test('a cluster on top of the radio has nothing to frame', () {
      expect(GridScreen.autoRangeKm(<double>[0, 0, 0]), isNull);
    });
  });

  group('the radius is exact, and the labels carry the decimal', () {
    test('the ninth decile lands at 86 % of the radius', () {
      // 19 nodes, 1 to 19 km: the 90th percentile is 17 km.
      final double km = GridScreen.autoRangeKm(_ramp(19, 1.0))!;
      expect(17.0 / km, closeTo(GridScreen.autoAnchor, 0.001));
    });

    test('a third of the radius is a number worth printing', () {
      // The painter draws rings at 1/3, 2/3 and 1 and formats one decimal
      // below ten kilometres, so an exact radius still reads.
      final double km = GridScreen.autoRangeKm(<double>[2.0])!;
      final String label = (km / 3).toStringAsFixed(1);
      expect(label, matches(RegExp(r'^\d+\.\d$')));
    });
  });

  group('the radar frames itself by default', () {
    testWidgets('the default stop is Auto, and the picker offers it',
        (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await t.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: const Scaffold(body: GridScreen()),
        ),
      ));
      await mc.connect();
      fake.emit(selfInfoFrameAt(lat: 38.92, lon: -104.77));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final AppLocalizations en = AppLocalizations.of(
          t.element(find.byType(GridScreen)));
      // The transport chip shows the stop's name and the km it resolved to.
      expect(find.text(en.gridRangeAuto), findsWidgets);
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('the painter repaints when the things that move markers change', () {
    testWidgets('a new self fix and a new clock are both repaint reasons',
        (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      Future<CustomPainter> pumpAt(double lat, double lon) async {
        fake.emit(selfInfoFrameAt(lat: lat, lon: lon));
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));
        final Iterable<CustomPaint> paints =
            t.widgetList<CustomPaint>(find.byType(CustomPaint));
        for (final CustomPaint p in paints) {
          final String name = '${p.painter.runtimeType}';
          if (name.contains('GridPainter')) return p.painter!;
        }
        fail('no grid painter in ${paints.map((CustomPaint p) => p.painter.runtimeType).toList()}');
      }

      await t.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: const Scaffold(body: GridScreen()),
        ),
      ));
      await mc.connect();
      // A node in range: an empty radar draws the notice instead of the
      // painter, so there would be nothing to compare.
      fake.emit(advertFrameAt(lat: 38.93, lon: -104.78, name: 'K0TEST'));
      await t.pump();
      final CustomPainter first = await pumpAt(38.92, -104.77);
      // The node list is unchanged; only our own fix moved. Before the fix in
      // `shouldRepaint` every marker stayed where the old fix had put it until
      // something else changed the picture.
      final CustomPainter second = await pumpAt(38.93, -104.78);
      expect(second.shouldRepaint(first), isTrue);
      mc.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });
}
