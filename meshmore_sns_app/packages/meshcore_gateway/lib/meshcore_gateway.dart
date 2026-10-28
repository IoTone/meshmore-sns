// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// The MeshMore gateway: the L2 wire contract, the loopback listener, the
/// pairing store, the airtime governor, and a minimal client.
///
/// Pure Dart, no Flutter. The app supplies a `MeshSender` over its BLE link
/// and a `PairingPersistence` backed by platform secure storage. The design
/// authority is `meshmore-sns-architecture.md` §5.5.
library;

export 'src/constants.dart';
export 'src/debug_client.dart';
export 'src/frame.dart';
export 'src/gateway.dart';
export 'src/governor.dart';
export 'src/mesh_sender.dart';
export 'src/messages.dart';
export 'src/pairing_store.dart';
export 'src/server.dart';
export 'src/session.dart';
