// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';

/// The links a message body carries.
///
/// A message is text from a stranger, so a link in one is not the app's
/// recommendation: it is somebody else's address, and the reader is the one who
/// decides whether to follow it. That is why the tap asks first and why the
/// dialog names the whole URL rather than a host the app chose to show.
abstract final class ChatLinks {
  /// `http` and `https` only. A bare `www.` is not a scheme, and guessing one
  /// would turn ordinary words into addresses.
  static final RegExp _url =
      RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// Trailing characters that end a sentence rather than a URL.
  static const String _trailing = '.,;:!?]}\'"<>';

  /// Every link in [text], in order, with the span it occupies.
  static List<({int start, int end, String url})> find(String text) {
    final List<({int start, int end, String url})> out =
        <({int start, int end, String url})>[];
    for (final RegExpMatch m in _url.allMatches(text)) {
      final String raw = m.group(0)!;
      final String url = _trim(raw);
      if (url.length <= 'https://'.length) continue;
      out.add((start: m.start, end: m.start + url.length, url: url));
    }
    return out;
  }

  /// Drop the punctuation a sentence puts after a URL, keeping a `)` that
  /// closes one the URL opened: a Wikipedia address ends in a bracket that is
  /// part of it.
  static String _trim(String raw) {
    int end = raw.length;
    while (end > 0) {
      final String c = raw[end - 1];
      if (c == ')') {
        final String head = raw.substring(0, end);
        final int opens = '('.allMatches(head).length;
        final int closes = ')'.allMatches(head).length;
        if (closes > opens) {
          end--;
          continue;
        }
        break;
      }
      if (_trailing.contains(c)) {
        end--;
        continue;
      }
      break;
    }
    return raw.substring(0, end);
  }
}

/// A message body whose links can be tapped.
///
/// The body is otherwise plain text, so a message with no link renders exactly
/// as it did before: one `Text`, no spans, no recognisers.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.textKey,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// The key the rendered `Text` carries.
  ///
  /// The key belongs on the text, not on this wrapper: a caller that keys a
  /// message body is naming the text, and a test that reads it expects a
  /// `Text`. Putting it here made `find.byKey` return a widget that is not one.
  final Key? textKey;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  /// One per link in the current build. A `TextSpan` holds its recogniser, so
  /// the spans and the recognisers have to be replaced together and the old
  /// ones released, or every rebuild leaks a gesture arena entry.
  List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    for (final TapGestureRecognizer r in _recognizers) {
      r.dispose();
    }
    _recognizers = <TapGestureRecognizer>[];
  }

  Future<void> _confirmAndOpen(String url) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.chatLinkOpenTitle),
        content: Text(l.chatLinkOpenBody(url)),
        actions: <Widget>[
          MmAction(
              label: l.actionCancel, onPressed: () => Navigator.pop(ctx, false)),
          MmAction(
              label: l.chatLinkOpen, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final List<({int start, int end, String url})> links =
        ChatLinks.find(widget.text);
    if (links.isEmpty) {
      _release();
      return Text(widget.text,
          key: widget.textKey,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow);
    }
    _release();
    final MmSkin skin = context.skin;
    final List<InlineSpan> spans = <InlineSpan>[];
    int at = 0;
    for (final ({int start, int end, String url}) link in links) {
      if (link.start > at) {
        spans.add(TextSpan(text: widget.text.substring(at, link.start)));
      }
      final TapGestureRecognizer recognizer = TapGestureRecognizer()
        ..onTap = () => _confirmAndOpen(link.url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: widget.text.substring(link.start, link.end),
        style: TextStyle(
          color: skin.color.link,
          decoration: TextDecoration.underline,
          decorationColor: skin.color.link,
        ),
        recognizer: recognizer,
      ));
      at = link.end;
    }
    if (at < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(at)));
    }
    return Text.rich(
      key: widget.textKey,
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
