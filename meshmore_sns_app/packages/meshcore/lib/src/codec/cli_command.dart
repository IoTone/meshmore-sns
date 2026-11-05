// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'constants.dart';

/// A local CLI command the app is allowed to ask a radio to run.
///
/// `CMD_RUN_CLI_COMMAND` (0x42) is not a settings API: it is the radio's
/// whole shell. It can reconfigure the radio, read saved secrets, and with
/// `remote` it acts on another node over the air. The app therefore never
/// sends user text through it. Every command is a typed object here, the
/// set is closed, and the only way to the wire is [bytes] — adding a
/// command is a code change with a test, not a string a caller can build.
///
/// The wire form is `42` followed by the CLI text with an optional final
/// NUL; the reply is one or more `RESP_CODE_CLI_REPLY` (0x1D) frames and
/// then an `OK` (`docs/companion_protocol.md:302-310`, protocol v14+).
sealed class RadioCliCommand {
  const RadioCliCommand();

  /// The exact text the radio's parser receives. Fixed per command: it is
  /// never assembled from caller input.
  String get cliText;

  /// `42 [tag|] <cliText>`, optionally prefixed with a two-character
  /// correlation tag and `|` so a reply can be attributed
  /// (`docs/companion_protocol.md:309-311`).
  Uint8List bytes({String? correlation}) {
    final String text = correlation == null ? cliText : '$correlation|$cliText';
    return Uint8List.fromList(<int>[
      MeshcoreCommand.runCliCommand.code,
      ...utf8.encode(text),
    ]);
  }

  /// True for the two-character correlation prefix the reply echoes back.
  static bool isCorrelationTag(String tag) =>
      tag.length == 2 &&
      tag.codeUnits.every((int c) => c >= 0x20 && c < 0x7F) &&
      !tag.contains('|');
}

/// `get buzzer` / `set buzzer on|off` — the companion's own audible alert
/// output (`docs/cli_commands.md:2716-2722`). A mute rule the app offers
/// for "buzz for #emergency" must never be able to unmute silently, so the
/// state is carried explicitly rather than as a toggle.
final class BuzzerCommand extends RadioCliCommand {
  const BuzzerCommand(this.enabled);
  const BuzzerCommand.read() : enabled = null;
  final bool? enabled;

  @override
  String get cliText => switch (enabled) {
        null => 'get buzzer',
        true => 'set buzzer on',
        false => 'set buzzer off',
      };
}

/// `get vibration` / `set vibration on|off` — the same output on boards
/// with a motor (`docs/cli_commands.md:2716-2722`).
final class VibrationCommand extends RadioCliCommand {
  const VibrationCommand(this.enabled);
  const VibrationCommand.read() : enabled = null;
  final bool? enabled;

  @override
  String get cliText => switch (enabled) {
        null => 'get vibration',
        true => 'set vibration on',
        false => 'set vibration off',
      };
}

/// Why a request never became a [RadioCliCommand].
enum RadioCliRefusal {
  /// The text carried shell syntax (`;`, `|`, a newline, a backtick) or was
  /// empty. A local CLI is a shell; nothing that can chain two commands is
  /// allowed to reach it, because the second one would be unvetted.
  rawTextRejected,

  /// `remote` reconfigures another node over the air. A contact could then
  /// change this radio's settings through a DM, so it is refused at the
  /// type level rather than by a permission check at a call site.
  remoteRejected,

  /// A command this app does not model.
  unsupportedCommand,

  /// A modelled command with an argument outside its closed set.
  malformedArgument,
}

/// The outcome of asking for a CLI command by text. Callers hold a
/// [RadioCliAccepted] and get the typed command; there is no path from a
/// refused string to bytes.
sealed class RadioCliResolution {
  const RadioCliResolution();
}

final class RadioCliAccepted extends RadioCliResolution {
  const RadioCliAccepted(this.command);
  final RadioCliCommand command;
}

final class RadioCliRefused extends RadioCliResolution {
  const RadioCliRefused(this.reason);
  final RadioCliRefusal reason;
}

/// The whitelist. It is deliberately a total function over the text: every
/// input resolves to an accepted typed command or a named refusal.
RadioCliResolution resolveRadioCliCommand(String raw) {
  final String text = raw.trim();
  if (text.isEmpty || RegExp(r'[;|`\n\r]').hasMatch(text)) {
    return const RadioCliRefused(RadioCliRefusal.rawTextRejected);
  }
  if (text == 'remote' || text.startsWith('remote ')) {
    return const RadioCliRefused(RadioCliRefusal.remoteRejected);
  }
  final List<String> words = text.split(RegExp(r'\s+'));
  final String head = words.first;
  if (head == 'get' || head == 'set') {
    if (words.length < 2) {
      return const RadioCliRefused(RadioCliRefusal.malformedArgument);
    }
    final String subject = words[1];
    final String? rest = words.length > 2 ? words.sublist(2).join(' ') : null;
    switch (subject) {
      case 'buzzer':
        if (head == 'get') {
          return rest == null
              ? const RadioCliAccepted(BuzzerCommand.read())
              : const RadioCliRefused(RadioCliRefusal.malformedArgument);
        }
        return _setOrRefuse(rest, BuzzerCommand.new);
      case 'vibration':
        if (head == 'get') {
          return rest == null
              ? const RadioCliAccepted(VibrationCommand.read())
              : const RadioCliRefused(RadioCliRefusal.malformedArgument);
        }
        return _setOrRefuse(rest, VibrationCommand.new);
      default:
        return const RadioCliRefused(RadioCliRefusal.unsupportedCommand);
    }
  }
  return const RadioCliRefused(RadioCliRefusal.unsupportedCommand);
}

RadioCliResolution _setOrRefuse(
  String? argument,
  RadioCliCommand Function(bool) build,
) =>
    switch (argument) {
      'on' => RadioCliAccepted(build(true)),
      'off' => RadioCliAccepted(build(false)),
      _ => const RadioCliRefused(RadioCliRefusal.malformedArgument),
    };
