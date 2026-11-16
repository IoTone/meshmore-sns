// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'constants.dart';

/// What the app knows about one radio's support for a command.
///
/// A companion's protocol version is not a capability list. The version
/// byte the app announces in `CMD_DEVICE_QUERY` is a *shape* negotiation —
/// the firmware gates exactly two emitters on it, the V3 receive frames
/// that carry per-message SNR (`MyMesh.cpp:435-443`, `:548-556`) — and the
/// firmware's own command set grows by build flag, not by version. So a
/// capability is established by a probe or by an actual reply, and until
/// then it is [unknown], which is never treated as supported.
enum CapabilityState {
  /// Nothing has been learned. Sending is refused, because a refusal the
  /// app can explain beats a command the radio silently ignores.
  unknown,

  /// The radio answered this command.
  supported,

  /// The radio answered `ERR_CODE_UNSUPPORTED_CMD`, or a probe proved it
  /// absent.
  absent,
}

/// Why a command may not be sent.
enum CapabilityRefusal { unknown, unsupported }

/// The app's per-radio capability record. One instance per connected radio:
/// switching radios must not carry one radio's answers to another.
final class RadioCapabilities {
  final Map<int, CapabilityState> _states = <int, CapabilityState>{};

  CapabilityState stateOf(MeshcoreCommand command) =>
      _states[command.code] ?? CapabilityState.unknown;

  /// A reply arrived: the command exists and did what it was asked.
  void observeReply(MeshcoreCommand command) {
    _states[command.code] = CapabilityState.supported;
  }

  /// An `ERR` arrived. Only `ERR_CODE_UNSUPPORTED_CMD` says anything about
  /// the command set; any other error means the command exists and refused
  /// this particular request, so the state stands.
  void observeError(MeshcoreCommand command, int errorCode) {
    if (errorCode == MeshcoreErrorCode.unsupportedCmd.code) {
      _states[command.code] = CapabilityState.absent;
    }
  }

  /// A probe established absence without a send (for example a contact
  /// report saying the radio has no such feature).
  void markAbsent(MeshcoreCommand command) {
    _states[command.code] = CapabilityState.absent;
  }

  /// A probe established presence before any reply arrived.
  void markSupported(MeshcoreCommand command) {
    _states[command.code] = CapabilityState.supported;
  }

  /// Null when the command may be sent, otherwise why it may not.
  CapabilityRefusal? refusalFor(MeshcoreCommand command) =>
      switch (stateOf(command)) {
        CapabilityState.supported => null,
        CapabilityState.unknown => CapabilityRefusal.unknown,
        CapabilityState.absent => CapabilityRefusal.unsupported,
      };

  /// Forget everything: a different radio is now the active one.
  void reset() => _states.clear();
}
