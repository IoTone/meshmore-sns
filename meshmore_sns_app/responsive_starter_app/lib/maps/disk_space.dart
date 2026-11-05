// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';

/// How much room the platform will actually give us before a download.
///
/// A partition stat is the wrong number: Android reserves space, may clear
/// caches on request, and counts the app's own cache as reclaimable. The
/// platform's answer already accounts for all of that, so the preflight asks
/// it rather than subtracting from a free-space figure. Null means "this host
/// cannot say" (a test, a desktop), and every caller treats null as "do not
/// refuse" rather than as zero.
abstract class DiskSpace {
  const DiskSpace();

  /// Bytes the platform can make available to this app, or null if unknown.
  Future<int?> allocatableBytes();
}

/// The real thing on Android: `StorageManager.getAllocatableBytes`.
class PlatformDiskSpace extends DiskSpace {
  const PlatformDiskSpace();

  static const MethodChannel _channel = MethodChannel('meshmore/storage');

  @override
  Future<int?> allocatableBytes() async {
    try {
      return await _channel.invokeMethod<int>('allocatableBytes');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// A host that cannot answer. Used by tests and by any non-Android run.
class UnknownDiskSpace extends DiskSpace {
  const UnknownDiskSpace();

  @override
  Future<int?> allocatableBytes() async => null;
}

/// Kept back on top of a download so the app still has somewhere to write.
///
/// A pack that fills the device to the last byte breaks the message store,
/// the tile cache and Android's own update staging, so the preflight asks for
/// the download plus this floor. It is deliberately generous: a phone that is
/// already full should refuse the pack, not fail the next message.
const int kDownloadReserveBytes = 200 * 1000 * 1000;

/// True when [available] can take [bytes] plus [kDownloadReserveBytes].
///
/// An unknown answer is never a refusal.
bool hasRoomFor(int? available, int bytes) =>
    available == null || available >= bytes + kDownloadReserveBytes;
