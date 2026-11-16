// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_layer.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

final DateTime _now = DateTime(2026, 11, 5, 12);

Place _place({
  String id = 'abcd1234',
  double lat = 51.5,
  double lon = -0.12,
  PlaceTtl ttl = PlaceTtl.d2,
  Uint8List? reporterKey,
}) =>
    Place(
      id: id,
      reporterKey: reporterKey,
      reporterName: 'Ana',
      type: PlaceType.water,
      typeToken: 'water',
      label: 'Water at the ford',
      latE6: (lat * 1e6).round(),
      lonE6: (lon * 1e6).round(),
      decimals: 6,
      provenance: PlaceProvenance.received,
      ttl: ttl,
      sentAt: _now,
      expiresAt: _now.add(ttl.life),
      lastSeen: _now,
    );

Widget _host(
  PlaceStore store, {
  double zoom = 16,
  DateTime? at,
  ThemeController? theme,
  void Function(Place)? onOpen,
  void Function(LatLng)? onCluster,
}) {
  final ThemeController tc = theme ?? ThemeController();
  return ChangeNotifierProvider<ThemeController>.value(
    value: tc,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(51.5, -0.12),
              initialZoom: zoom,
            ),
            children: <Widget>[
              PlaceLayer(
                store: store,
                now: at == null ? () => _now : () => at,
                onOpen: onOpen ?? (Place _) {},
                onClusterTap: onCluster ?? (LatLng _) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  late PlaceStore store;

  setUp(() => store = PlaceStore(clock: () => _now));
  tearDown(() => store.dispose());

  testWidgets('draws a live pin in every one of the seven skins',
      (WidgetTester t) async {
    store.upsert(_place());
    for (final MmThemePreset preset in MmThemePreset.values) {
      final ThemeController tc = ThemeController();
      await tc.setPreset(preset);
      await t.pumpWidget(_host(store, theme: tc));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('place-pin-abcd1234')),
          findsOneWidget,
          reason: 'preset ${preset.name} must draw the pin');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an expired place is not drawn, but its history row stays',
      (WidgetTester t) async {
    store.upsert(_place(ttl: PlaceTtl.m15));
    await t.pumpWidget(_host(store, at: _now.add(const Duration(minutes: 16))));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('place-pin-abcd1234')),
        findsNothing);
    expect(store.history(), hasLength(1));
  });

  testWidgets('an unread pin is coloured by type, a read one is neutral',
      (WidgetTester t) async {
    // Pinned to SEELE: the assertion below names that skin's link and muted
    // tokens, so the host must render the skin the assertion is about rather
    // than whichever preset happens to be the default.
    final ThemeController tc = ThemeController();
    await tc.setPreset(MmThemePreset.seele);
    store.upsert(_place());
    await t.pumpWidget(_host(store, theme: tc));
    await t.pump();
    Icon icon = t.widget<Icon>(find.descendant(
      of: find.byKey(const ValueKey<String>('place-pin-abcd1234')),
      matching: find.byType(Icon),
    ));
    expect(icon.color, mmSkinFor(MmThemePreset.seele).color.link);

    store.markSeen('abcd1234');
    await t.pumpWidget(_host(store, theme: tc));
    await t.pump();
    icon = t.widget<Icon>(find.descendant(
      of: find.byKey(const ValueKey<String>('place-pin-abcd1234')),
      matching: find.byType(Icon),
    ));
    expect(icon.color, mmSkinFor(MmThemePreset.seele).color.fgMuted);
  });

  testWidgets('tapping a pin opens it and marks it seen', (WidgetTester t) async {
    store.upsert(_place());
    Place? opened;
    await t.pumpWidget(_host(store, onOpen: (Place p) => opened = p));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('place-pin-abcd1234')));
    await t.pump();
    expect(opened?.id, 'abcd1234');
    expect(store.isSeen('abcd1234'), isTrue);
  });

  testWidgets('below the cluster zoom two nearby places are one marker',
      (WidgetTester t) async {
    store
      ..upsert(_place(id: 'aaaa0001'))
      ..upsert(_place(id: 'bbbb0002', lat: 51.54, lon: -0.11));
    LatLng? cluster;
    await t.pumpWidget(_host(store, zoom: 10, onCluster: (LatLng c) => cluster = c));
    await t.pump();
    final Finder clusterMarker = find.byWidgetPredicate((Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('place-cluster-'));
    expect(clusterMarker, findsOneWidget);
    expect(find.byWidgetPredicate((Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('place-pin-')), findsNothing);

    await t.tap(clusterMarker);
    await t.pump();
    expect(cluster, isNotNull);
  });

  testWidgets('an unkeyed place carries the ring and says so to a reader',
      (WidgetTester t) async {
    // A report derived from a channel name has no key behind it: the detail
    // sheet said so, the map pin did not, so a name-derived pin sat on the
    // same canvas looking exactly like a key-bound one.
    store.upsert(_place(id: 'name0001'));
    await t.pumpWidget(_host(store));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('place-unkeyed-name0001')),
        findsOneWidget);
    final SemanticsNode node = t.getSemantics(
        find.byKey(const ValueKey<String>('place-pin-name0001')));
    expect(node.label, contains('channel name'));

    // A keyed report is drawn without it.
    store.upsert(_place(id: 'key00002', reporterKey: Uint8List(32)));
    await t.pumpWidget(_host(store));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('place-unkeyed-name0001')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('place-unkeyed-key00002')),
        findsNothing);
  });
}
