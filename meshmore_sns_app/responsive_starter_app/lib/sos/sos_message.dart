// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// The SOS, acknowledgement, safe and check-in grammar
/// (`meshmore-sos-spec.md` §5). All four are ordinary channel text or direct
/// messages that start with a bracketed tag: **no new payload type**, so every
/// receiver that can read text can read them, and the radio's own seen table
/// sees plain text.
///
/// The messages are bounded by two ceilings at once, which is why encoding is
/// a function that can refuse: the channel text ceiling is 160 bytes
/// **including** the `sender: ` prefix the firmware prepends, and the free
/// text is at most 96 bytes. The firmware truncates silently at its own
/// limit, and a truncated SOS loses the callsign or the coordinate, so this
/// codec refuses instead of truncating.
library;
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Bytes the firmware prepends to channel text before it travels.
const int senderPrefixBytes = 8; // "sender: "

/// Channel text ceiling, prefix included (`MAX_TEXT_LEN`, 160).
const int channelTextBytes = 160;

/// Free text ceiling on its own (`meshmore-sos-spec.md` §5).
const int freeTextBytes = 96;

/// Callsign ceiling.
const int callsignBytes = 32;

/// The body of a channel line, with the firmware's `"name: "` prefix removed.
///
/// Channel text arrives as `sender: body` — the firmware prepends the sender's
/// name — while a direct message's text *is* the body. Anything that looks for
/// a bracketed tag has to skip the prefix, and it must do so the same way
/// everywhere: two spellings of this rule is how a channel SOS was classified
/// as an ordinary message (safety audit SOS-1).
String withoutSenderPrefix(String text) {
  final int sep = text.indexOf(': ');
  if (sep <= 0 || sep > callsignBytes) return text;
  return text.substring(sep + 2).trim();
}

/// True when [text] carries an SOS tag, whatever the path it arrived by.
///
/// Used by the notification handler to pick the SOS class for a channel line,
/// which is the case the audit found broken: the tag starts after the prefix,
/// so a bare `startsWith('[SOS:')` never matched channel traffic.
bool isSosLine(String text) {
  final String body = withoutSenderPrefix(text);
  if (body.length < 5) return false;
  return body.substring(0, 5).toUpperCase() == '[SOS:';
}

/// What a message is, from its tag.
enum SosTag { sos, ack, safe, checkin }

/// A parsed request, reply or check-in.
sealed class SosMessage {
  const SosMessage({required this.id});

  /// Six lowercase hex characters: not a time bucket and not a secret, only
  /// enough to name one request among several (`[ACK:<id6>]`).
  final String id;

  /// The tag that starts the message.
  SosTag get tag;
}

/// `[SOS:<id6>] <lat>,<lon> <callsign> <free text>` or the `NOFIX` form.
final class SosRequestMessage extends SosMessage {
  const SosRequestMessage({
    required super.id,
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.text,
  });

  /// Null when the sender's last fix was older than an hour: an alarm without
  /// a position is still an alarm, and a three-hour-old coordinate sends help
  /// to the wrong place (`meshmore-sos-spec.md` §2).
  final double? lat;
  final double? lon;
  final String callsign;
  final String text;

  bool get hasFix => lat != null && lon != null;

  @override
  SosTag get tag => SosTag.sos;
}

/// `[ACK:<id6>] <callsign> <words>` — a responder answering one request.
final class SosAckMessage extends SosMessage {
  const SosAckMessage({
    required super.id,
    required this.callsign,
    required this.text,
  });

  final String callsign;
  final String text;

  @override
  SosTag get tag => SosTag.ack;
}

/// `[SAFE:<id6>] <callsign>` — the raiser calling it off.
final class SosSafeMessage extends SosMessage {
  const SosSafeMessage({required super.id, required this.callsign});

  final String callsign;

  @override
  SosTag get tag => SosTag.safe;
}

/// `[CHK:<id6>] <lat>,<lon> <callsign> until <local time>` or the `NOFIX` form.
final class CheckinMessage extends SosMessage {
  const CheckinMessage({
    required super.id,
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.until,
  });

  final double? lat;
  final double? lon;
  final String callsign;

  /// The deadline as the sender spelled it: local time, no timezone, because
  /// two radios in one valley share a clock and a zone suffix would only add
  /// bytes to a message that counts them.
  final DateTime until;

  bool get hasFix => lat != null && lon != null;

  @override
  SosTag get tag => SosTag.checkin;
}

/// Why a message could not be built or read. Every outcome is named so the
/// composer can say which one happened instead of failing generically.
enum SosMessageRefusal {
  tooLong,
  badId,
  badPosition,
  badCallsign,
  emptyText,
  missingUntil,
  unknownTag,
  malformed,
}

/// The six-hex request id: `sha256(nonce ‖ pubkey)[0..2]`
/// (`meshmore-sos-spec.md` §5).
///
/// **Not time-derived.** Two raises in one minute must not collide, and a
/// resume must be a new request rather than a replay, so the entropy comes
/// from the nonce and the identity from the radio's key.
String sosIdFor({required List<int> nonce, required List<int> pubkey}) {
  if (nonce.length != 16) {
    throw ArgumentError.value(nonce.length, 'nonce', 'must be 16 bytes');
  }
  if (pubkey.isEmpty) {
    throw ArgumentError('an SOS id needs the raiser\'s public key');
  }
  final Digest digest = sha256.convert(<int>[...nonce, ...pubkey]);
  return digest.toString().substring(0, 6);
}

/// `lat,lon` with at most six decimals, **truncated** rather than rounded so
/// the sender's own precision is what travels (`GeoUtils.h:123-131`).
String formatPosition(double lat, double lon) => '${_coord(lat)},${_coord(lon)}';

String _coord(double v) {
  final bool negative = v < 0;
  final double abs = v.abs();
  final int scaled = (abs * 1000000).floor(); // truncate, never round
  String digits = scaled.toString().padLeft(7, '0');
  final String whole = digits.substring(0, digits.length - 6);
  String frac = digits.substring(digits.length - 6);
  while (frac.isNotEmpty && frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  // The convention requires a decimal point, so a whole number keeps one
  // decimal digit rather than losing the point entirely.
  final String out = frac.isEmpty ? '$whole.0' : '$whole.$frac';
  return negative && scaled != 0 ? '-$out' : out;
}

/// The salt that makes every send in one alarm a different payload.
///
/// The radio's seen table hashes type plus payload and drops an identical
/// repeat, so twelve identical SOS frames would arrive once. The grammar has
/// no field for it, so the salt rides at the end of the free text, after a
/// `~`, which every receiver already treats as opaque words.
String sosSalt({required List<int> nonce, required int index}) {
  final Digest d = sha256.convert(<int>[...nonce, index & 0xff]);
  return d.toString().substring(0, 4);
}

/// Builds one SOS packet, or says why it cannot be sent.
///
/// [index] is the packet number inside the alarm; it only feeds the salt, so
/// two packets of one alarm never carry the same bytes.
({String? text, SosMessageRefusal? refusal}) encodeSos({
  required String id,
  required String callsign,
  required String words,
  required DateTime? fixAt,
  required DateTime now,
  double? lat,
  double? lon,
  required List<int> nonce,
  required int index,
}) {
  final SosMessageRefusal? common = _commonRefusal(id: id, callsign: callsign);
  if (common != null) return (text: null, refusal: common);

  final String salted = _saltWords(words, sosSalt(nonce: nonce, index: index));
  if (utf8.encode(salted).length > freeTextBytes) {
    return (text: null, refusal: SosMessageRefusal.tooLong);
  }

  final bool usableFix = _fixIsUsable(fixAt: fixAt, now: now) &&
      lat != null &&
      lon != null &&
      _positionInRange(lat, lon);
  final String body = usableFix
      ? '${formatPosition(lat, lon)} $callsign'
      : 'NOFIX $callsign';
  final String text = '[SOS:$id] $body $salted';
  return _fits(text)
      ? (text: text, refusal: null)
      : (text: null, refusal: SosMessageRefusal.tooLong);
}

/// Builds one check-in packet, or says why it cannot be sent.
({String? text, SosMessageRefusal? refusal}) encodeCheckin({
  required String id,
  required String callsign,
  required DateTime until,
  required DateTime now,
  required DateTime? fixAt,
  double? lat,
  double? lon,
}) {
  final SosMessageRefusal? common = _commonRefusal(id: id, callsign: callsign);
  if (common != null) return (text: null, refusal: common);

  final bool usableFix = _fixIsUsable(fixAt: fixAt, now: now) &&
      lat != null &&
      lon != null &&
      _positionInRange(lat, lon);
  final String where =
      usableFix ? formatPosition(lat, lon) : 'NOFIX';
  final String text =
      '[CHK:$id] $where $callsign until ${formatUntil(until)}';
  return _fits(text)
      ? (text: text, refusal: null)
      : (text: null, refusal: SosMessageRefusal.tooLong);
}

/// `[ACK:<id6>] <callsign> <words>`.
({String? text, SosMessageRefusal? refusal}) encodeAck({
  required String id,
  required String callsign,
  required String words,
}) {
  final SosMessageRefusal? common = _commonRefusal(id: id, callsign: callsign);
  if (common != null) return (text: null, refusal: common);
  final String text =
      words.trim().isEmpty ? '[ACK:$id] $callsign' : '[ACK:$id] $callsign ${words.trim()}';
  return _fits(text)
      ? (text: text, refusal: null)
      : (text: null, refusal: SosMessageRefusal.tooLong);
}

/// `[SAFE:<id6>] <callsign>`.
({String? text, SosMessageRefusal? refusal}) encodeSafe({
  required String id,
  required String callsign,
}) {
  final SosMessageRefusal? common = _commonRefusal(id: id, callsign: callsign);
  if (common != null) return (text: null, refusal: common);
  final String text = '[SAFE:$id] $callsign';
  return _fits(text)
      ? (text: text, refusal: null)
      : (text: null, refusal: SosMessageRefusal.tooLong);
}

/// Local wall-clock deadline, minute precision: `2026-11-05 18:40`.
String formatUntil(DateTime until) {
  final DateTime local = until.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Reads any of the four tags out of a message, or says why it cannot.
///
/// Returns null for a message that carries none of the tags: an ordinary chat
/// line is not a malformed SOS.
SosMessage? parseSos(String text) {
  final String t = text.trim();
  final RegExp tag = RegExp(r'^\[(SOS|ACK|SAFE|CHK):([0-9a-f]{6})\]');
  final RegExpMatch? m = tag.firstMatch(t);
  if (m == null) return null;
  final String tagName = m.group(1)!;
  final String id = m.group(2)!;
  final String rest = t.substring(m.end).trim();
  final List<String> parts =
      rest.isEmpty ? const <String>[] : rest.split(RegExp(r'\s+'));

  switch (tagName) {
    case 'SOS':
      if (parts.isEmpty) return null;
      final ({double? lat, double? lon, int next}) where = _readWhere(parts);
      if (where.next >= parts.length) return null;
      final List<String> tail = parts.sublist(where.next);
      return SosRequestMessage(
        id: id,
        lat: where.lat,
        lon: where.lon,
        callsign: tail.first,
        text: tail.length > 1 ? tail.sublist(1).join(' ') : '',
      );
    case 'ACK':
      if (parts.isEmpty) return null;
      return SosAckMessage(
        id: id,
        callsign: parts.first,
        text: parts.length > 1 ? parts.sublist(1).join(' ') : '',
      );
    case 'SAFE':
      if (parts.isEmpty) return null;
      return SosSafeMessage(id: id, callsign: parts.first);
    case 'CHK':
      if (parts.isEmpty) return null;
      final ({double? lat, double? lon, int next}) where = _readWhere(parts);
      if (where.next + 2 >= parts.length) return null;
      final String callsign = parts[where.next];
      // `until <date> <time>` — two tokens, because a space separates them.
      final int untilIndex = where.next + 1;
      if (parts[untilIndex].toLowerCase() != 'until') return null;
      final String stamp =
          '${parts[untilIndex + 1]} ${untilIndex + 2 < parts.length ? parts[untilIndex + 2] : ''}';
      final DateTime? until = DateTime.tryParse(stamp.trim());
      if (until == null) return null;
      return CheckinMessage(
        id: id,
        lat: where.lat,
        lon: where.lon,
        callsign: callsign,
        until: until,
      );
  }
  return null;
}

/// A position token or the literal `NOFIX`, and where the rest starts.
({double? lat, double? lon, int next}) _readWhere(List<String> parts) {
  final String head = parts.first;
  if (head.toUpperCase() == 'NOFIX') {
    return (lat: null, lon: null, next: 1);
  }
  final List<String> pair = head.split(',');
  if (pair.length != 2) return (lat: null, lon: null, next: 1);
  final double? lat = double.tryParse(pair[0]);
  final double? lon = double.tryParse(pair[1]);
  if (lat == null || lon == null || !_positionInRange(lat, lon)) {
    return (lat: null, lon: null, next: 1);
  }
  return (lat: lat, lon: lon, next: 1);
}

SosMessageRefusal? _commonRefusal({
  required String id,
  required String callsign,
}) {
  if (!isSosId(id)) return SosMessageRefusal.badId;
  if (callsign.trim().isEmpty ||
      utf8.encode(callsign).length > callsignBytes) {
    return SosMessageRefusal.badCallsign;
  }
  return null;
}

bool _positionInRange(double lat, double lon) =>
    lat.abs() <= 90 && lon.abs() <= 180;

/// APP-H2: a fix older than an hour is never sent as a position.
bool _fixIsUsable({required DateTime? fixAt, required DateTime now}) {
  if (fixAt == null) return false;
  final Duration age = now.difference(fixAt);
  if (age.isNegative) return false; // a clock that claims the future is not a fix
  return age <= const Duration(hours: 1);
}

String _saltWords(String words, String salt) {
  final String w = words.trim();
  return w.isEmpty ? '~$salt' : '$w ~$salt';
}

bool _fits(String text) =>
    utf8.encode(text).length + senderPrefixBytes <= channelTextBytes;


/// The bytes one text costs on the wire, prefix included: what the composer
/// counts (`D8.3`).
int channelTextCost(String text) => utf8.encode(text).length + senderPrefixBytes;

/// Whether a string is a well-formed six-hex request id.
bool isSosId(String id) => RegExp(r'^[0-9a-f]{6}$').hasMatch(id);
