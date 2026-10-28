// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// The MeshMore host-side process.
///
/// Composition only: [SerialFrameTransport] (L1 transport) +
/// [MeshcoreConnection] (L1 link) + [SerialMeshSender] (L1 -> MeshSender) +
/// `Gateway` (L2 server). It deliberately contains no MeshCore protocol
/// knowledge of its own.
library;

export 'src/companion_link.dart';
export 'src/serial_framing.dart';
export 'src/serial_port.dart';
export 'src/serial_mesh_sender.dart';
export 'src/serial_transport.dart';
