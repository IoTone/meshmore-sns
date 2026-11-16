// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import '../screens/diagnostics_redaction.dart';

/// R10 — "report a problem" opens the tracker with what we already know.
///
/// There is no crash reporter and no analytics (scope of record §8), so the
/// only way a defect reaches someone who can fix it is the user carrying it
/// there. That makes the pre-filled issue the substitute for telemetry, and it
/// has to be worth sending: the app version, the radio and its firmware, the
/// link's negotiated MTU, and — only when the user has just copied one — a
/// diagnostics capture that has been through [DiagnosticsRedaction].
///
/// Nothing here sends anything. The text is built locally, the user reads it in
/// the issue form, and they decide.
class IssueReport {
  const IssueReport({
    required this.appVersion,
    required this.platform,
    this.radioName,
    this.radioFirmware,
    this.radioModel,
    this.mtu,
    this.diagnostics,
  });

  /// The repository's issue form. One URL, so a fork that hosts its own build
  /// changes this constant rather than hunting through screens.
  static const String trackerBase =
      'https://github.com/IoTone/meshmore-sns/issues/new';

  final String appVersion;

  /// `Android 14 (API 34)` — the OS matters for a BLE defect and costs one
  /// line to carry.
  final String platform;

  final String? radioName;
  final String? radioFirmware;
  final String? radioModel;

  /// The link's negotiated ATT MTU, when a radio is connected: below 179 the
  /// largest frames cannot cross, and that is invisible in a screenshot.
  final int? mtu;

  /// A diagnostics capture, if the user pasted one. Redacted here rather than
  /// trusted from the caller: this is the last place it can leak.
  final String? diagnostics;

  Uri toUri() => Uri.parse('$trackerBase'
      '?title=${Uri.encodeQueryComponent(_title())}'
      '&body=${Uri.encodeQueryComponent(toBody())}');

  String _title() {
    final String radio = radioName == null ? 'no radio' : 'radio: $radioName';
    return 'MeshMore $appVersion — $radio';
  }

  String toBody() {
    // The body is a tracker document, not app copy: issues are read and
    // searched in English, and a defect report the maintainer has to translate
    // is a defect report half the readers cannot find. The screen around it is
    // translated as usual.
    final StringBuffer b = StringBuffer()
      ..writeln('**What happened**')
      ..writeln()
      ..writeln('<!-- one or two lines: what you did, what you expected, what '
          'happened -->')
      ..writeln()
      ..writeln('**Where**')
      ..writeln()
      ..writeln('- App: $appVersion')
      ..writeln('- Platform: $platform');
    if (radioName != null) b.writeln('- Radio: $radioName');
    if (radioModel != null) b.writeln('- Radio model: $radioModel');
    if (radioFirmware != null) b.writeln('- Radio firmware: $radioFirmware');
    if (mtu != null) b.writeln('- Link MTU: $mtu');
    if (diagnostics != null && diagnostics!.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('**Diagnostics** (redacted on the phone; nothing was sent '
            'automatically)')
        ..writeln()
        ..writeln('```')
        ..writeln(const DiagnosticsRedaction().json(diagnostics!))
        ..writeln('```');
    }
    b
      ..writeln()
      ..writeln('_Filed from the app: no crash reporter and no analytics are '
          'built into MeshMore, so this text is the whole report._');
    return b.toString();
  }
}
