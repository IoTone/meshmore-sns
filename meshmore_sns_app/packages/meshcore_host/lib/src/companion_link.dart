// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

/// The slice of the L1 link that [SerialMeshSender] depends on.
///
/// This exists so the sender can be tested with a fake link. It is not an
/// abstraction for its own sake: [MeshcoreConnection] is concrete and holds
/// timers, which makes it a poor test double for frame-level behaviour.
abstract interface class CompanionLink {
  MeshcoreConnectionState get state;
  Stream<MeshcoreConnectionState> get states;
  Stream<MeshcoreInbound> get inbound;
  SelfInfo? get selfInfo;
  Future<void> sendCommand(Uint8List frame);
}

/// [CompanionLink] over the real [MeshcoreConnection]. Delegation only.
class MeshcoreConnectionLink implements CompanionLink {
  MeshcoreConnectionLink(this._connection);
  final MeshcoreConnection _connection;

  @override
  MeshcoreConnectionState get state => _connection.state;

  @override
  Stream<MeshcoreConnectionState> get states => _connection.states;

  @override
  Stream<MeshcoreInbound> get inbound => _connection.inbound;

  @override
  SelfInfo? get selfInfo => _connection.selfInfo;

  @override
  Future<void> sendCommand(Uint8List frame) => _connection.sendCommand(frame);
}
