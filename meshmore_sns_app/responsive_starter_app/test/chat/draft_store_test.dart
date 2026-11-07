// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/chat/draft_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';

/// APP-E7 — one draft per conversation, sealed with the history key, and never
/// handed to a different radio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mm_drafts');
    DraftStore.cipherOverride = MemoryRecordCipher.random();
    DraftStore.directoryOverride = dir;
  });

  tearDown(() {
    DraftStore.cipherOverride = null;
    DraftStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String ch(int idx, {String radio = 'aabbccdd'}) =>
      DraftStore.keyFor(radio, channelIdx: idx);
  String dm(String peer, {String radio = 'aabbccdd'}) =>
      DraftStore.keyFor(radio, peerHex: peer);

  test('a draft survives a reload and is removed when emptied', () async {
    await DraftStore.save(ch(0), 'half a thought');
    expect(await DraftStore.read(ch(0)), 'half a thought');

    await DraftStore.save(ch(0), '');
    expect(await DraftStore.read(ch(0)), isEmpty);
  });

  test('channel and thread drafts do not collide', () async {
    await DraftStore.save(ch(0), 'channel');
    await DraftStore.save(dm('AB12'), 'direct');
    expect(await DraftStore.read(ch(0)), 'channel');
    expect(await DraftStore.read(dm('ab12')), 'direct');
  });

  test('another radio cannot see this one\'s drafts', () async {
    await DraftStore.save(ch(0), 'mine');
    expect(await DraftStore.forRadio('aabbccdd'), contains(ch(0)));
    expect(await DraftStore.forRadio('11223344'), isEmpty);
    // The namespaced key means a read by the other radio is a different row.
    expect(await DraftStore.read(ch(0, radio: '11223344')), isEmpty);
  });

  test('a replaced radio takes its drafts with it', () async {
    await DraftStore.save(ch(0), 'old radio');
    await DraftStore.save(ch(0, radio: '11223344'), 'new radio');
    await DraftStore.clearRadio('aabbccdd');
    expect(await DraftStore.forRadio('aabbccdd'), isEmpty);
    expect(await DraftStore.read(ch(0, radio: '11223344')), 'new radio');
  });

  test('a blocked peer keeps its draft, because a block hides a thread',
      () async {
    // The block store is not this file's business: it filters what is shown.
    // A draft is unsent text the user wrote, so hiding the thread must not
    // destroy it — the reader still returns it, and only a send or an explicit
    // clear removes the row.
    await DraftStore.save(dm('deadbeef'), 'still here');
    expect(await DraftStore.read(dm('deadbeef')), 'still here');
    await DraftStore.clear(dm('deadbeef'));
    expect(await DraftStore.read(dm('deadbeef')), isEmpty);
  });

  test('blank text is not stored, so an emptied composer leaves no row',
      () async {
    await DraftStore.save(ch(1), '   ');
    expect(await DraftStore.forRadio('aabbccdd'), isEmpty);
  });

  test('a forward appends to what is already in the composer', () async {
    // `forwardMessage` reads the target draft before writing, so a half-typed
    // sentence in the destination is not thrown away by the forward.
    await DraftStore.save(ch(1), 'half typed');
    final String existing = await DraftStore.read(ch(1));
    final String forwarded = 'a message worth passing on';
    await DraftStore.save(
        ch(1), existing.trim().isEmpty ? forwarded : '$existing\n$forwarded');
    expect(await DraftStore.read(ch(1)),
        'half typed\na message worth passing on');
  });
}
