// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/chat/linkified_text.dart';

/// A link in a message is somebody else's address, so the app has to find it
/// exactly and no more: a span that swallows the full stop after a URL opens a
/// page that does not exist, and a span that stops early opens the wrong one.
void main() {
  test('a message with no link has none', () {
    expect(ChatLinks.find('good evening mesh'), isEmpty);
    expect(ChatLinks.find('www.example.com is not a scheme'), isEmpty);
  });

  test('an https URL is found with its span', () {
    const String text = 'see https://example.com/a?b=1 for the map';
    final List<({int start, int end, String url})> links = ChatLinks.find(text);
    expect(links.length, 1);
    expect(links.single.url, 'https://example.com/a?b=1');
    expect(text.substring(links.single.start, links.single.end),
        'https://example.com/a?b=1');
  });

  test('a full stop after a URL is not part of it', () {
    final List<({int start, int end, String url})> links =
        ChatLinks.find('read https://example.com/page.');
    expect(links.single.url, 'https://example.com/page');
  });

  test('a bracket the URL opened is kept, one that closes the sentence is not', () {
    expect(
        ChatLinks.find('https://en.wikipedia.org/wiki/Mesh_(networking)').single.url,
        'https://en.wikipedia.org/wiki/Mesh_(networking)');
    expect(ChatLinks.find('(see https://example.com/x)').single.url,
        'https://example.com/x');
  });

  test('two links in one message are both found', () {
    final List<({int start, int end, String url})> links =
        ChatLinks.find('http://a.example and https://b.example/c');
    expect(links.map((({int start, int end, String url}) l) => l.url).toList(),
        <String>['http://a.example', 'https://b.example/c']);
  });
}
