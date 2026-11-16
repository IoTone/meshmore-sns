// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/media/aeic_installer.dart';
import 'package:meshmore_sns_app/media/aeic_codec_service.dart'
    show kAeicWireAvailable;
import 'package:meshmore_sns_app/media/media_mode.dart';

AeicModelFile _file(String name, List<int> body, {String? sha}) => AeicModelFile(
      name: name,
      bytes: body.length,
      sha256: sha ?? sha256.convert(body).toString(),
      role: 'test',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('photo mode', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('the default holds the pixels, and asks before sending them', () async {
      expect(await MediaModePrefs.photoMode(), MediaMode.onRequest);
    });

    test('a stored mode comes back by id, not by index', () async {
      await MediaModePrefs.setPhotoMode(MediaMode.preview);
      expect(await MediaModePrefs.photoMode(), MediaMode.preview);
    });

    test('an id this build does not know falls back rather than crashing',
        () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'mm.media.photoMode': 'quantum'});
      expect(await MediaModePrefs.photoMode(), MediaMode.onRequest);
    });

    test('every mode states a cost and a quality', () {
      for (final MediaMode m in MediaMode.values) {
        expect(m.bytes, isNotEmpty);
        expect(m.quality, isNotEmpty);
        expect(m.id, isNotEmpty);
      }
    });

    test('the neural mode is selectable once the build carries the codec', () {
      // The settings row still gates on the *bundle*: a mode whose models are
      // not installed would refuse every picture.
      expect(kAeicEncodeAvailable, isTrue);
      expect(kAeicWireAvailable, isTrue);
    });
  });

  group('the codec bundle', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('aeic-test');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    AeicInstaller make(List<AeicModelFile> files, http.Client Function() c) =>
        AeicInstaller(root: () async => dir, files: files, clientFactory: c);

    test('an empty directory reports absent', () async {
      final AeicModelFile f = _file('a.bin', <int>[1, 2, 3]);
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async => http.Response('', 500)));
      await i.refresh();
      expect(i.state, AeicState.absent);
    });

    test('the published bundle is the four graphs and the table', () {
      // Three ONNX graphs, the decoder weights split into their own file, and
      // the rANS table: five files, 957 MiB.
      expect(kAeicModelFiles.length, 5);
      expect(kAeicBundleBytes, 1004548432);
      // The digests are hex SHA-256, which is what the download is checked
      // against: a short string here would never verify.
      for (final AeicModelFile f in kAeicModelFiles) {
        expect(f.sha256.length, 64, reason: f.name);
        expect(f.bytes, greaterThan(0), reason: f.name);
      }
    });

    test('a download is verified and kept', () async {
      final List<int> body = List<int>.generate(64, (int i) => i);
      final AeicModelFile f = _file('a.bin', body);
      int requests = 0;
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async {
        requests++;
        return http.Response.bytes(body, 200);
      }));
      await i.install();
      expect(i.state, AeicState.ready);
      expect(requests, 1);
      expect(await File('${dir.path}/a.bin').length(), body.length);
    });

    test('a partial file resumes with a Range request', () async {
      final List<int> body = List<int>.generate(64, (int i) => i);
      final AeicModelFile f = _file('a.bin', body);
      await File('${dir.path}/a.bin')
          .writeAsBytes(body.sublist(0, 20), flush: true);
      final List<String?> ranges = <String?>[];
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async {
        ranges.add(r.headers['Range']);
        return http.Response.bytes(body.sublist(20), 206);
      }));
      await i.install();
      expect(ranges.single, 'bytes=20-');
      expect(i.state, AeicState.ready);
      expect(await File('${dir.path}/a.bin').readAsBytes(), body);
    });

    test('a server that ignores Range rewrites the file from zero', () async {
      final List<int> body = List<int>.generate(64, (int i) => i);
      final AeicModelFile f = _file('a.bin', body);
      await File('${dir.path}/a.bin').writeAsBytes(<int>[9, 9, 9], flush: true);
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async => http.Response.bytes(body, 200)));
      await i.install();
      expect(i.state, AeicState.ready);
      expect(await File('${dir.path}/a.bin').readAsBytes(), body);
    });

    test('a body that does not match its digest is fetched again once', () async {
      final List<int> body = List<int>.generate(64, (int i) => i);
      final AeicModelFile f = _file('a.bin', body);
      int attempts = 0;
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async {
        attempts++;
        // The first answer is the wrong bytes with the right length.
        return http.Response.bytes(
            attempts == 1 ? List<int>.filled(64, 7) : body, 200);
      }));
      await i.install();
      expect(attempts, 2, reason: 'one repair attempt');
      expect(i.state, AeicState.ready);
    });

    test('two bad answers fail with the file named', () async {
      final List<int> body = List<int>.generate(64, (int i) => i);
      final AeicModelFile f = _file('a.bin', body);
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async =>
              http.Response.bytes(List<int>.filled(64, 7), 200)));
      await i.install();
      expect(i.state, AeicState.failed);
      expect(i.error, contains('a.bin'));
    });

    test('remove takes the bytes back', () async {
      final List<int> body = <int>[1, 2, 3, 4];
      final AeicModelFile f = _file('a.bin', body);
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async => http.Response.bytes(body, 200)));
      await i.install();
      expect(i.state, AeicState.ready);
      await i.remove();
      expect(i.state, AeicState.absent);
      expect(await dir.exists(), isFalse);
    });

    test('an already verified file is not downloaded again', () async {
      final List<int> body = <int>[5, 6, 7, 8];
      final AeicModelFile f = _file('a.bin', body);
      await File('${dir.path}/a.bin').writeAsBytes(body, flush: true);
      int requests = 0;
      final AeicInstaller i = make(<AeicModelFile>[f], () => MockClient(
          (http.Request r) async {
        requests++;
        return http.Response.bytes(body, 200);
      }));
      await i.install();
      expect(requests, 0);
      expect(i.state, AeicState.ready);
    });
  });
}
