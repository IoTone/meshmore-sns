// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// Is this message addressed to me?
///
/// D8.13 decides the rule: the display name as a **whole word**, or `@name`.
/// Key-suffix matching (the last hex characters of the public key) is an
/// opt-in and off by default, because four hex characters are not an
/// identity: they collide, they appear inside unrelated words, and matching
/// them turned ordinary traffic into alerts.
///
/// [mentionsOnly] is applied by the caller; this function answers only the
/// mention question, so the OS notification and the audio cue can share one
/// answer.
bool isMentioned(
  String text,
  String? displayName, {
  String? keySuffix,
  bool matchKeySuffix = false,
}) {
  final String haystack = text.toLowerCase();
  final String name = (displayName ?? '').trim().toLowerCase();
  if (name.isNotEmpty) {
    if (_bounded(haystack, name)) return true;
    if (_bounded(haystack, '@$name')) return true;
  }
  if (matchKeySuffix) {
    final String hex = (keySuffix ?? '').trim().toLowerCase();
    if (hex.length >= 4 && _bounded(haystack, hex)) return true;
  }
  return false;
}

/// [needle] bounded on both sides by anything that is not a letter or digit,
/// so "Sam" matches "Sam: are you there" but neither "Same" nor "Samantha".
bool _bounded(String haystack, String needle) {
  int at = haystack.indexOf(needle);
  while (at >= 0) {
    final bool startOk = at == 0 || !_wordChar(haystack.codeUnitAt(at - 1));
    final int end = at + needle.length;
    final bool endOk =
        end >= haystack.length || !_wordChar(haystack.codeUnitAt(end));
    if (startOk && endOk) return true;
    at = haystack.indexOf(needle, at + 1);
  }
  return false;
}

bool _wordChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F; // underscore
