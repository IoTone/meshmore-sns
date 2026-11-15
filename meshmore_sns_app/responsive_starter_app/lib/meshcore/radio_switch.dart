// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'meshcore_controller.dart';

/// What a request to change radios did.
enum RadioSwitchOutcome {
  /// The link was torn down and the new radio is being connected.
  switched,

  /// The radio asked for is the one already paired, so nothing was touched.
  sameRadio,

  /// A message is still waiting for an answer, so the switch was refused.
  refusedUnsettled,
}

/// D8.9 — one session, and changing it is explicit.
///
/// The app has always had one radio session and no way to say "the other one".
/// `connectToPickedDevice` could do it, but only from the pairing flow, which
/// is the flow a reader uses when nothing is paired; a reader with two radios
/// had to unpair to reach the second.
///
/// The rule the register states is the one implemented here: a switch is
/// **refused while a send is unanswered**, rather than marking that send
/// unknown. The reason is the firmware's own ACK table — an answer belongs to
/// the link it arrived on, and a message whose answer is still owed would be
/// left with no way to settle, so the row would sit at "sending" until its
/// timeout and then claim a failure the app cannot prove. Refusing is the
/// honest half: the reader is told to wait, and nothing is lost.
///
/// The switch itself is `connectToPickedDevice`, which already serialises the
/// teardown and the new connect and writes the pairing, so this adds the rule
/// and the words, not a second connection path.
Future<RadioSwitchOutcome> switchRadio(
  MeshcoreController mc, {
  required String remoteId,
  required String name,
}) async {
  if (remoteId == mc.pairedRemoteId) return RadioSwitchOutcome.sameRadio;
  if (mc.unsettledOutgoingCount > 0) return RadioSwitchOutcome.refusedUnsettled;
  await mc.connectToPickedDevice(remoteId: remoteId, name: name);
  return RadioSwitchOutcome.switched;
}
