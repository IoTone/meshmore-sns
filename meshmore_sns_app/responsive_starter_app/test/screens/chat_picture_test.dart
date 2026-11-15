// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/media_fetch_service.dart';
import 'package:meshmore_sns_app/media/media_offer.dart';
import 'package:meshmore_sns_app/media/media_prefs.dart';
import 'package:meshmore_sns_app/media/mp1.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/ui/mp1_preview.dart';

import '../meshcore/fake_transport.dart';
import 'chat_screen_test.dart' show FakeTtsSpeaker;

/// A picture in a message row.
///
/// A preview arrives as one channel datagram rather than as text, so the row is
/// where it has to appear: the thread used to show an empty line where somebody
/// sent a picture, and the picture itself lived in a strip above the composer,
/// away from the moment it arrived.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const int kTransferId = 7;

  /// A real MP1 datagram: encoded from a picture, so the row decodes what the
  /// wire carries rather than a stub.
  Uint8List preview({int upgradeChunks = 5}) {
    final Uint8List rgba = Uint8List(64 * 64 * 4);
    for (int i = 0; i < 64 * 64; i++) {
      rgba[i * 4] = (i * 7) & 0xFF;
      rgba[i * 4 + 1] = (i * 3) & 0xFF;
      rgba[i * 4 + 2] = 0x40;
      rgba[i * 4 + 3] = 0xFF;
    }
    final Uint8List? bytes = encodeMp1Preview(
      MediaPhoto(width: 64, height: 64, rgba: rgba),
      transferId: kTransferId,
      upgradeChunks: upgradeChunks,
    );
    expect(bytes, isNotNull, reason: 'a 24x24 quad fits one datagram');
    return bytes!;
  }

  /// The controller from the last [pump] in a case, so a case that pumps more
  /// than once can drop the screen it replaced. A controller left alive keeps
  /// its refresh timer and the binding reports it after the case.
  MeshcoreController? live;
  TtsController? liveTts;
  MediaFetchService? liveFetch;

  void drop() {
    live?.dispose();
    liveTts?.dispose();
    liveFetch?.dispose();
    live = null;
    liveTts = null;
    liveFetch = null;
  }

  Future<(FakeMeshcoreTransport, MeshcoreController)> pump(
    WidgetTester t,
    MmThemePreset preset, {
    double textScale = 1.0,
    Size size = const Size(900, 1600),
  }) async {
    drop();
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: FakeTtsSpeaker());
    final MediaFetchService fetch =
        MediaFetchService(mc: mc, offers: MediaOfferStore());
    liveFetch = fetch;
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>.value(value: tts),
        ChangeNotifierProvider<MediaFetchService>.value(value: fetch),
      ],
      child: Builder(
        builder: (BuildContext c) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            theme: c.read<ThemeController>().theme,
            locale: const Locale('en'),
            supportedLocales: LocaleController.supported,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ChatScreen()),
          ),
        ),
      ),
    ));
    live = mc;
    liveTts = tts;
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    return (fake, mc);
  }

  void addPreview(MeshcoreController mc, {int upgradeChunks = 5}) {
    mc.recordPicturePreview(
      channelIdx: 0,
      payload: preview(upgradeChunks: upgradeChunks),
      transferId: kTransferId,
      at: DateTime.now(),
    );
  }

  MeshcoreController controllerOf(WidgetTester t) => live!;

  testWidgets('a preview draws in log, bubble and block rows',
      (WidgetTester t) async {
    for (final MmThemePreset preset in <MmThemePreset>[
      MmThemePreset.seele, // terminal log
      MmThemePreset.hyperlocal, // bubble
      MmThemePreset.drPop, // colour block
    ]) {
      await pump(t, preset);
      addPreview(controllerOf(t));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('message-picture-7')), findsOne,
          reason: 'no thumbnail in ${preset.name}');
      expect(find.byType(Mp1PreviewImage), findsOne,
          reason: 'the row painted something other than the palette grid');
    }
    drop();
  });

  testWidgets('a row that carries only a picture has no empty text line',
      (WidgetTester t) async {
    await pump(t, MmThemePreset.seele);
    addPreview(controllerOf(t));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('message-picture-7')), findsOne);
    // The old shape printed an empty string where the picture is: a blank line
    // above a thumbnail reads as a rendering fault.
    for (final Text text in t.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(''),
          reason: 'an empty text widget was drawn');
    }
    drop();
  });

  testWidgets('the picture is grey until App settings says colour',
      (WidgetTester t) async {
    await pump(t, MmThemePreset.seele);
    addPreview(controllerOf(t));
    await t.pumpAndSettle();
    expect(t.widget<Mp1PreviewImage>(find.byType(Mp1PreviewImage)).color,
        isFalse,
        reason: 'photos are grey by default and a preview is a photo');

    await MediaPrefs.setColorPhotos(true);
    // A fresh row, because the preference is read when the row is built.
    await pump(t, MmThemePreset.seele);
    addPreview(controllerOf(t));
    await t.pumpAndSettle();
    expect(
        t.widget<Mp1PreviewImage>(find.byType(Mp1PreviewImage)).color, isTrue);
    drop();
  });

  testWidgets('an unfetched picture says what it would cost and asks for nothing',
      (WidgetTester t) async {
    final (FakeMeshcoreTransport fake, MeshcoreController _) =
        await pump(t, MmThemePreset.seele);
    // The link's own handshake traffic is not what this case is about: the
    // question is whether drawing the row adds anything to it.
    final int before = fake.sent.length;
    addPreview(controllerOf(t));
    await t.pumpAndSettle();
    expect(find.text('Load · 5 packets'), findsOne,
        reason: 'the reader is told the cost before spending it');
    // The ask is the strip above the composer. A row that broadcast on paint
    // would spend the channel's airtime on every scroll.
    expect(fake.sent.length, before,
        reason: 'drawing a picture must not transmit anything');
    drop();
  });

  testWidgets('a fetched picture replaces the preview and nothing is lost',
      (WidgetTester t) async {
    await pump(t, MmThemePreset.hyperlocal);
    addPreview(controllerOf(t));
    await t.pumpAndSettle();
    expect(find.byType(Mp1PreviewImage), findsOne,
        reason: 'the preview is what arrives first');
    expect(find.text('Load · 5 packets'), findsOne);

    // The pixels arrive: the row shows the picture and stops offering a load.
    liveFetch!.seedLoadedPicture(
      kTransferId,
      MediaPhoto(width: 32, height: 32, rgba: Uint8List(32 * 32 * 4)),
    );
    await t.pumpAndSettle();
    expect(find.byType(RgbaThumbnail), findsOne);
    expect(find.byType(Mp1PreviewImage), findsNothing);
    expect(find.text('Load · 5 packets'), findsNothing);
    // The preview is still on the row, so a picture evicted from the loaded
    // map leaves the thread with the thumbnail it arrived as.
    expect(controllerOf(t).messagesFor(0).single.mp1, isNotNull);
    drop();
  });

  test('a preview survives a JSON round trip', () {
    final ChatMessage m = ChatMessage(
      channelIdx: 0,
      text: '',
      outgoing: false,
      mp1: preview(),
    );
    final ChatMessage back = ChatMessage.fromJson(m.toJson());
    expect(back.mp1, isNotNull);
    expect(back.mp1Image, isNotNull);
    expect(back.mp1Image!.width, m.mp1Image!.width);
    expect(back.mp1Image!.indices, m.mp1Image!.indices);
    // A row whose bytes will not decode loses the picture, not the history.
    final ChatMessage broken =
        ChatMessage.fromJson(<String, Object?>{'m': 'not base64 at all!'});
    expect(broken.mp1, isNull);
  });

  testWidgets('every preset holds 320 dp at 200 % text with a picture',
      (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      await pump(t, preset,
          textScale: 2.0, size: const Size(320, 900));
      addPreview(controllerOf(t));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: '${preset.name} overflowed with a picture in the row');
      // The thumbnail grows with the body text but never past a billboard.
      final Mp1PreviewImage art =
          t.widget<Mp1PreviewImage>(find.byType(Mp1PreviewImage));
      expect(art.size, lessThanOrEqualTo(96));
      expect(mmSkinFor(preset).type.sizeBody * 4, closeTo(art.size, 96));
    }
    drop();
  });
}
