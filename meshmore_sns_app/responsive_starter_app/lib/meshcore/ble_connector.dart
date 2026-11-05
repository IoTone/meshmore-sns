// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:meshcore/meshcore.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_meshcore_transport.dart';
import 'paired_device_history.dart';
import 'paired_device_store.dart';

/// The MeshCore service's RX and TX characteristics, located on an unencrypted
/// link but not yet subscribed.
class _Link {
  const _Link(this.rx, this.tx);
  final BluetoothCharacteristic rx;
  final BluetoothCharacteristic tx;
}

/// Thrown when scan/connect cannot complete.
class BleConnectException implements Exception {
  BleConnectException(this.message);
  final String message;
  @override
  String toString() => 'BleConnectException: $message';
}

/// The link came up but negotiated an ATT MTU too small to carry one whole
/// protocol frame.
///
/// The number is the whole diagnosis: short frames still cross, the firmware's
/// largest ones do not, and every symptom downstream looks like a lost packet.
/// It is a separate type from [BleConnectException] because it is not a bond or
/// identity failure and must not trigger a bond repair.
class BleMtuTooSmall implements Exception {
  BleMtuTooSmall(this.mtu);

  /// The value the link actually negotiated.
  final int mtu;

  @override
  String toString() =>
      'BleMtuTooSmall: MTU $mtu < ${MeshcoreBle.requiredMtu} required';
}

/// Scans for a MeshCore companion device, connects, locates the
/// RX/TX characteristics, and returns a ready [BleMeshcoreTransport].
///
/// Device-side (flutter_blue_plus) — exercised on real hardware in M6;
/// `flutter analyze`-clean here.
abstract final class BleConnector {
  static final Guid _service = Guid(MeshcoreBle.serviceUuid);
  static final Guid _rxUuid = Guid(MeshcoreBle.rxCharacteristicUuid);
  static final Guid _txUuid = Guid(MeshcoreBle.txCharacteristicUuid);

  /// The firmware names every radio `MeshCore-<node name>`
  /// (`BLE_NAME_PREFIX`, `examples/companion_radio/MyMesh.h`). A bond the
  /// phone took from its own Bluetooth menu carries that name, which is the
  /// only thing that marks it as a radio rather than any other bonded gadget.
  static const String _namePrefix = 'MeshCore-';

  /// Whether a bond repair has already been attempted in this run.
  ///
  /// One attempt is the budget. A radio that cannot keep a bond fails the same
  /// way every time, so a second repair is just another PIN prompt for the user
  /// and no information for us.
  static bool _repairedThisRun = false;

  /// Set when the one repair this run was given has itself failed.
  ///
  /// Without it, every reconnect attempt after a failed repair is another
  /// pairing dialog — up to eight, one per retry, each waiting the full 60 s
  /// for a PIN. That is what the radio's own log showed on 2026-10-31:
  /// `connected → pairing passkey request → pairing complete status=1 →
  /// disconnected reason=22`, repeating. A radio that cannot keep a bond is
  /// not fixed by asking the user to type a PIN again, so the attempts stop and
  /// the message says what to do.
  ///
  /// Cleared by any successful open, so a radio that recovers is not punished
  /// for having failed once.
  static bool _repairFailed = false;

  /// Consecutive failed opens since the last success.
  ///
  /// The repair is a last resort, not a reflex. Re-pairing on this stack can
  /// leave a second bond record on the radio, and the radio's lookup returns the
  /// first record that resolves the phone — so a needless repair makes the next
  /// connection more likely to fail, not less. One failure is not evidence of a
  /// bond the phone cannot use: it can be an ordinary link loss, a radio that is
  /// re-advertising, or a supervision timeout. Two in a row, with the radio still
  /// in range, is.
  static int _consecutiveFailures = 0;

  static const String _notKeepingPairing =
      'The radio is not keeping its pairing: it paired, then could not encrypt '
      'on the next connection. Power-cycle the radio, then reopen the app and '
      'pair again. If that repeats, the radio is losing its stored bond.';

  /// Request the runtime BLE permissions. The permission model is
  /// platform-specific:
  ///
  /// - **iOS:** a single Core Bluetooth permission
  ///   (`Permission.bluetooth`). The Android-only scan/connect
  ///   permissions route to permission_handler's
  ///   `UnknownPermissionStrategy` on iOS and always report
  ///   `permanentlyDenied` without prompting, so requesting them
  ///   makes BLE look denied on a fresh install.
  /// - **Android 12+:** granular scan + connect gate BLE; location is
  ///   only needed pre-Android-12.
  static Future<bool> ensurePermissions() async {
    if (!kIsWeb && Platform.isIOS) {
      final PermissionStatus bt = await Permission.bluetooth.request();
      // Location is optional on iOS — only used for the GPS one-shot
      // fallback — so it doesn't gate the BLE link.
      await Permission.locationWhenInUse.request();
      return bt.isGranted;
    }
    final Map<Permission, PermissionStatus> r = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final bool scan = r[Permission.bluetoothScan]?.isGranted ?? false;
    final bool conn = r[Permission.bluetoothConnect]?.isGranted ?? false;
    return scan && conn;
  }

  /// Whether the runtime BLE permissions are already held, without prompting.
  static Future<bool> hasPermissions() async {
    if (!kIsWeb && Platform.isIOS) {
      return (await Permission.bluetooth.status).isGranted;
    }
    return (await Permission.bluetoothScan.status).isGranted &&
        (await Permission.bluetoothConnect.status).isGranted;
  }

  static bool _sameUuid(Guid a, Guid b) =>
      a.str.toLowerCase() == b.str.toLowerCase();

  /// Scan → connect → discover → return a transport.
  static Future<BleMeshcoreTransport> scanAndConnect({
    Duration scanTimeout = const Duration(seconds: 15),
    bool writeWithoutResponse = false,
  }) async {
    if (!await ensurePermissions()) {
      throw BleConnectException('BLE permissions denied');
    }

    // Wait for the adapter to be on.
    final BluetoothAdapterState adapter = await FlutterBluePlus.adapterState
        .firstWhere((BluetoothAdapterState s) =>
            s == BluetoothAdapterState.on ||
            s == BluetoothAdapterState.unavailable)
        .timeout(const Duration(seconds: 5),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter != BluetoothAdapterState.on) {
      throw BleConnectException('Bluetooth adapter not on ($adapter)');
    }

    await FlutterBluePlus.startScan(
      withServices: <Guid>[_service],
      timeout: scanTimeout,
    );
    // **Wait for a radio's name, not just its address.** The firmware puts the
    // name in the scan response, which arrives a sweep after the advertisement
    // that carries the service UUID, so the first snapshot frequently has the
    // device and not the name. Stopping there would either miss the radio or, a
    // moment earlier, have fallen back to a stranger that cloned the UUID.
    final Map<String, ScanResult> seen = <String, ScanResult>{};
    final Completer<void> named = Completer<void>();
    final StreamSubscription<List<ScanResult>> sub =
        FlutterBluePlus.scanResults.listen((List<ScanResult> snapshot) {
      for (final ScanResult r in snapshot) {
        seen[r.device.remoteId.str] = r;
      }
      if (!named.isCompleted && snapshot.any(_namesItselfRadio)) {
        named.complete();
      }
    });
    await named.future.timeout(scanTimeout, onTimeout: () {});
    await sub.cancel();
    await FlutterBluePlus.stopScan();
    if (seen.isEmpty) {
      throw BleConnectException('No MeshCore device found');
    }

    final BluetoothDevice device =
        await _pickHit(seen.values.map((ScanResult r) => r.device));
    return _open(device, writeWithoutResponse);
  }

  /// Whether this device says in its advertisement that it is a radio.
  static bool _namesItselfRadio(ScanResult r) =>
      r.device.platformName.startsWith(_namePrefix) ||
      r.advertisementData.advName.startsWith(_namePrefix);

  /// Which scan hit to connect to: a radio the phone is already bonded to, else
  /// one that names itself `MeshCore-`, else the first hit.
  ///
  /// The scan filter is the Nordic UART service UUID, which unrelated gadgets
  /// clone — the bond table on the test phone held an entry for "E2 Pro 1113"
  /// because this connected to `hits.first` and called `createBond` on whatever
  /// had matched. `_finish` discovers services before subscribing, so a stranger
  /// fails there, but not before the user has been shown a pairing dialog for a
  /// device that was never a radio.
  ///
  /// The firmware always advertises `MeshCore-<node name>`
  /// (`sprintf(dev_name, "%s%s", prefix, name)`, `SerialBLEInterface.cpp`), so
  /// the name is what separates a radio from everything else answering the same
  /// UUID.
  static Future<BluetoothDevice> _pickHit(
      Iterable<BluetoothDevice> candidates) async {
    final List<BluetoothDevice> list = candidates.toList();

    bool namesItselfRadio(BluetoothDevice d) =>
        d.platformName.startsWith(_namePrefix) ||
        d.advName.startsWith(_namePrefix);
    // Named radios first, but an unnamed hit is still a candidate: a radio whose
    // scan response was missed must not be reported as absent. It cannot do any
    // harm to try one, because [_locate] proves the MeshCore service before
    // anything bonds.
    final List<BluetoothDevice> radios = list.where(namesItselfRadio).toList();
    final List<BluetoothDevice> pool = radios.isEmpty ? list : radios;

    // Presence is proven by the scan, so preferring a bonded radio never waits
    // on a bond for a device that is not here.
    final Set<String> bonded = <String>{
      for (final BluetoothDevice d in await bondedMeshcoreDevices())
        d.remoteId.str,
    };
    for (final BluetoothDevice d in pool) {
      if (bonded.contains(d.remoteId.str)) return d;
    }
    return pool.first;
  }

  /// Connect directly to a previously-paired device by its BLE remote
  /// id (no scan). Used by [autoConnect] for fast startup reconnect.
  static Future<BleMeshcoreTransport> connectToRemoteId(
    String remoteId, {
    Duration timeout = const Duration(seconds: 12),
    bool writeWithoutResponse = false,
  }) async {
    if (!await ensurePermissions()) {
      throw BleConnectException('BLE permissions denied');
    }
    final BluetoothDevice device = BluetoothDevice.fromId(remoteId);
    return _open(device, writeWithoutResponse, timeout: timeout);
  }

  /// R41 — start a BLE scan and stream the full list of MeshCore
  /// devices currently visible. The UI uses this to populate a
  /// "Choose device" picker; rather than [scanAndConnect]'s
  /// `hits.first` shortcut, the user explicitly taps the device they
  /// want. Caller is responsible for calling [stopScan] when the
  /// picker closes (or letting the [timeout] elapse).
  ///
  /// Each event from the stream is the **complete current set** of
  /// hits seen so far in this scan; new devices appearing later
  /// produce an updated list including the prior entries. RSSI in
  /// each [ScanResult] updates between snapshots.
  static Stream<List<ScanResult>> scanForDevices({
    Duration timeout = const Duration(seconds: 12),
  }) async* {
    if (!await ensurePermissions()) {
      throw BleConnectException('BLE permissions denied');
    }
    final BluetoothAdapterState adapter = await FlutterBluePlus.adapterState
        .firstWhere((BluetoothAdapterState s) =>
            s == BluetoothAdapterState.on ||
            s == BluetoothAdapterState.unavailable)
        .timeout(const Duration(seconds: 5),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter != BluetoothAdapterState.on) {
      throw BleConnectException('Bluetooth adapter not on ($adapter)');
    }
    await FlutterBluePlus.startScan(
      withServices: <Guid>[_service],
      timeout: timeout,
    );
    yield* FlutterBluePlus.scanResults;
  }

  /// Stop an in-flight scan, if any. Idempotent — safe to call when
  /// no scan is running.
  static Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {/* already stopped or unsupported */}
  }

  /// Radios the operating system already holds a bond for, in the order the
  /// OS lists them. Android-only: iOS has no bond list to read.
  ///
  /// This is the half of the pairing state the app cannot see for itself.
  /// Pairing from the phone's own Bluetooth menu writes a bond and nothing
  /// else, so without this the app reports "no device paired" for a radio the
  /// phone is bonded to, and pairing it a second time from inside the app is
  /// the only way forward.
  ///
  /// Never requests permission: this is called on the startup path, and a
  /// permission dialog must be the answer to something the user did. Without
  /// permission the list is simply empty, which is the pre-existing behaviour.
  static Future<List<BluetoothDevice>> bondedMeshcoreDevices() async {
    if (kIsWeb || !Platform.isAndroid) return const <BluetoothDevice>[];
    if (!await hasPermissions()) return const <BluetoothDevice>[];
    try {
      final List<BluetoothDevice> bonded = await FlutterBluePlus.bondedDevices;
      return bonded
          .where((BluetoothDevice d) => d.platformName.startsWith(_namePrefix))
          .toList();
    } catch (_) {
      return const <BluetoothDevice>[];
    }
  }

  /// Whether a failed open is worth repairing the bond over, asked before
  /// whether the radio is still in range.
  ///
  /// `hadBond` is the bond that existed *before* this attempt, and
  /// `identityFailure` means [_locate] decided the device carries no MeshCore
  /// service — something no amount of re-pairing changes.
  ///
  /// `alreadyRepaired` is what keeps this from becoming a loop. A radio that
  /// cannot hold a bond fails the same way every time, so repairing again only
  /// asks the user for another PIN. One attempt per app run is the whole
  /// budget: after that the honest report is that the radio is at fault.
  ///
  /// `consecutiveFailures` is what keeps it from firing on a single bad
  /// reconnect. Two is the threshold: the first failure is ambiguous, and a
  /// repair that turns out to be unnecessary is not free — see [_repairFailed].
  ///
  /// Deliberately absent: whether the link survived. It does not, in the case
  /// this exists for, because an unusable bond kills the link while the radio
  /// stack is still trying to encrypt it.
  @visibleForTesting
  static bool shouldRepairBond({
    required bool hadBond,
    required bool identityFailure,
    bool alreadyRepaired = false,
    int consecutiveFailures = 2,
  }) =>
      hadBond &&
      !identityFailure &&
      !alreadyRepaired &&
      consecutiveFailures >= 2;

  /// Which bonded radio to adopt when the app has no pairing of its own: the
  /// most recent one it has used before, else whichever the OS lists first.
  ///
  /// The phone can hold more than one radio's bond at a time (an old radio
  /// replaced by a new one both stay bonded). Preferring the history makes the
  /// adopted bond the one the user last actually used instead of an arbitrary
  /// entry from a set the OS does not order.
  @visibleForTesting
  static String? adoptBondId({
    required List<String> bondedIds,
    required List<String> historyIds,
  }) {
    for (final String id in historyIds) {
      if (bondedIds.contains(id)) return id;
    }
    return bondedIds.isEmpty ? null : bondedIds.first;
  }

  /// The radio to adopt as this app's pairing when it has none of its own.
  /// Null when the phone holds no MeshCore bond either.
  static Future<PairedDevice?> adoptableBond({
    List<String> historyIds = const <String>[],
  }) async {
    final List<BluetoothDevice> bonded = await bondedMeshcoreDevices();
    final String? id = adoptBondId(
      bondedIds: bonded.map((BluetoothDevice d) => d.remoteId.str).toList(),
      historyIds: historyIds,
    );
    for (final BluetoothDevice d in bonded) {
      if (d.remoteId.str == id) {
        return PairedDevice(d.remoteId.str, d.platformName);
      }
    }
    return null;
  }

  /// Startup path: reconnect to the saved paired device if there is
  /// one; otherwise fall back to a scan. Always the default transport
  /// factory so the M7 reconnect policy keeps working too.
  static Future<BleMeshcoreTransport> autoConnect({
    bool writeWithoutResponse = false,
  }) async {
    final PairedDevice? paired = await PairedDeviceStore.read();
    if (paired != null) {
      try {
        return await connectToRemoteId(paired.remoteId,
            writeWithoutResponse: writeWithoutResponse);
      } catch (_) {
        // Saved device unreachable — fall back to scanning.
      }
    }
    // A bond made in the phone's Bluetooth menu is the same bond this app
    // would have made, so the scan prefers it over any other radio in range.
    // Connecting to a bonded-but-absent radio first would only wait out a
    // connect timeout per stale bond, which is what a replaced radio leaves
    // behind.
    return scanAndConnect(writeWithoutResponse: writeWithoutResponse);
  }

  /// Android requires an encrypted (bonded) link before the MeshCore
  /// RX/TX characteristics can be used. Bond explicitly so the OS
  /// passkey dialog appears — and is waited on — before the handshake
  /// clock ever starts, instead of being triggered implicitly by
  /// [BluetoothCharacteristic.setNotifyValue] and racing the 8s
  /// handshake timeout. Screen radios (e.g. Wio Tracker L1 Pro) show
  /// a random PIN on their display; screenless ones (e.g. T1000-E)
  /// use 123456. Returns whether a bond already existed beforehand.
  static Future<bool> _ensureBonded(BluetoothDevice device) async {
    if (kIsWeb || !Platform.isAndroid) return false; // iOS: OS-managed.
    // Ask the same question [_bondExists] asks, and for the same reason: a
    // device built from a remote id has no cached bond state until a connection
    // starts, so its first emission is not evidence of anything. The list is
    // the authority. Two answers to one question meant a bonded radio could be
    // sent through a fresh pairing ceremony.
    if (await _bondExists(device)) return true;
    try {
      // 60s: enough time to read the PIN off the radio screen and
      // type it into the system dialog.
      await device.createBond(timeout: 60);
    } catch (_) {
      throw BleConnectException(
          'Pairing failed — enter the PIN shown on the radio screen '
          '(screenless radios use 123456), then retry');
    }
    return false;
  }

  /// The name to remember for a radio we just connected to.
  ///
  /// A direct reconnect ([connectToRemoteId], used on every app start) has
  /// no scan result behind it, so `platformName` and `advName` are both
  /// empty and the only name left is the MAC. Saving that overwrote the real
  /// one ("MeshCore-ABCDEF") with "AA:BB:CC:..." in the pairing and in the
  /// recently-paired list. When nothing better is known for THIS radio, keep
  /// the name already stored for it.
  @visibleForTesting
  static String pairedNameFor({
    required String platformName,
    required String advName,
    required String remoteId,
    PairedDevice? stored,
  }) {
    if (platformName.isNotEmpty) return platformName;
    if (advName.isNotEmpty) return advName;
    if (stored != null &&
        stored.remoteId == remoteId &&
        stored.name.isNotEmpty) {
      return stored.name;
    }
    return remoteId;
  }

  /// Connect, then open the radio, repairing a bond the radio cannot use.
  ///
  /// **The whole open is the repair's scope, not just service discovery.** A
  /// bond the radio cannot use kills the link while `device.connect()` is still
  /// running — the plugin requests the MTU as part of connecting, and that
  /// exchange never completes — so the failure arrives from `connect()` and an
  /// earlier version, which guarded only the discovery step, never saw it. On
  /// the test phone the sequence was: connect, `status: SUCCESS`, `requestMtu`,
  /// five seconds, `LINK_SUPERVISION_TIMEOUT`, forever.
  static Future<BleMeshcoreTransport> _open(
    BluetoothDevice device,
    bool writeWithoutResponse, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    // Refuse before anything else once the repair has been spent and failed:
    // connecting would kill the link on the radio's own key check and then ask
    // for a PIN nobody can make stick.
    if (_repairFailed) throw BleConnectException(_notKeepingPairing);
    // Read before connecting: the bond that has to be judged is the one that
    // existed before this attempt, and reading makes no bond and asks nothing.
    final bool hadBond = await _bondExists(device);
    try {
      await device.connect(timeout: timeout);
      final transport = await _establish(device, writeWithoutResponse);
      _repairFailed = false;
      _consecutiveFailures = 0;
      return transport;
    } catch (e) {
      await _safeDisconnect(device);
      _consecutiveFailures++;
      if (!shouldRepairBond(
          hadBond: hadBond,
          identityFailure: e is BleConnectException,
          alreadyRepaired: _repairedThisRun,
          consecutiveFailures: _consecutiveFailures)) {
        rethrow;
      }
      // **A bond Android reports is not a bond the radio can use.** Android
      // starts encryption itself the moment a bonded radio connects. When the
      // two sides do not agree on that bond, SMP never leaves idle, the
      // encryption request is cancelled about five seconds later, and the link
      // dies on the supervision timeout. Measured on the test phone:
      // `smp_cancel_start_encryption_attempt`, then `GATT_CONN_TIMEOUT`.
      //
      // Both sides still report `BOND_STATE_BONDED` through all of it, so the
      // app cannot tell a usable bond from an unusable one before trying. Note
      // that `ble_enc_key_size` in `dumpsys bluetooth_manager` is *not* the
      // answer: it mirrors the live link and reads 0 whenever the link is
      // unencrypted or down, which is the normal disconnected state.
      //
      // A link that dropped is not on its own evidence of a bad bond, so the
      // decision is "is the radio still here", not "did the link survive".
      if (!await _stillNearby(device.remoteId.str)) rethrow;
      // The repair is spent even if it fails, so a radio that cannot keep a
      // bond produces one PIN prompt and then a diagnosis, not a prompt per
      // reconnect attempt.
      _repairedThisRun = true;
      try {
        return await _repairBond(device, writeWithoutResponse);
      } catch (_) {
        _repairFailed = true;
        throw BleConnectException(_notKeepingPairing);
      }
    }
  }

  /// Discover services/characteristics, enable notifications, persist
  /// the device as paired, and wrap it as a transport.
  static Future<BleMeshcoreTransport> _establish(
      BluetoothDevice device, bool writeWithoutResponse) async {
    // **Look before bonding.** Service discovery needs no encryption, so the
    // radio's identity can be established before anything asks the user for a
    // key. Bonding first meant whatever had matched the scan was given a
    // pairing dialog — the test phone's bond table held an "E2 Pro 1113"
    // entry for exactly that reason, a device which is not a radio at all.
    final _Link link = await _locate(device);
    await _ensureBonded(device);
    return await _subscribe(device, link, writeWithoutResponse);
  }

  /// Forget a bond the radio cannot use and make a fresh one, then open.
  static Future<BleMeshcoreTransport> _repairBond(
      BluetoothDevice device, bool writeWithoutResponse) async {
    try {
      // Removing the bond tears the link down on Android, so the reconnect
      // has to come before `createBond` (which requires a live connection).
      await device.removeBond();
      await device.connect(timeout: const Duration(seconds: 12));
      final _Link link = await _locate(device);
      await _ensureBonded(device);
      return await _subscribe(device, link, writeWithoutResponse);
    } on BleConnectException {
      // The fresh pairing failed the way a pairing fails (no PIN entered), and
      // that message already tells the user what to do.
      await _safeDisconnect(device);
      rethrow;
    } catch (_) {
      await _safeDisconnect(device);
      throw BleConnectException(
          'Stale pairing — the radio no longer holds this bond. Forget it in '
          'Android Bluetooth settings, power-cycle the radio, then pair again');
    }
  }

  /// Whether Android already holds a bond, read without making one.
  ///
  /// Reading is not pairing: it asks the user nothing, so it can run before
  /// [_locate] has proved the device is a radio.
  ///
  /// The bonded list is asked, not `device.bondState`. A device object built
  /// from a remote id — which is what auto-reconnect uses — has no cached bond
  /// state until a connection starts, so its first emission is not "bonded" and
  /// a `bondState` read silently answered "no bond" for a radio the phone was
  /// bonded to.
  static Future<bool> _bondExists(BluetoothDevice device) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final List<BluetoothDevice> bonded = await FlutterBluePlus.bondedDevices;
      return bonded.any((BluetoothDevice d) => d.remoteId == device.remoteId);
    } catch (_) {
      return false;
    }
  }

  /// Whether `remoteId` answers a scan right now.
  ///
  /// This exists only to tell "the bond is wrong" from "the radio left", and
  /// absence is ambiguous (out of range, flat, asleep), so a miss means the bond
  /// is left alone. Three seconds is the scan window that still catches an
  /// advertising radio, and a false negative only costs a retry.
  ///
  /// A failed open is normally reached with the app's own scan still running, so
  /// starting a second one throws and would answer "not here" for a radio that
  /// is right there. The accumulated results are read first, and a scan is only
  /// started when none is running — and owned, so it is stopped again.
  static Future<bool> _stillNearby(String remoteId) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    bool seenIn(List<ScanResult> snapshot) =>
        snapshot.any((ScanResult r) => r.device.remoteId.str == remoteId);

    if (seenIn(FlutterBluePlus.lastScanResults)) return true;

    final Completer<bool> found = Completer<bool>();
    StreamSubscription<List<ScanResult>>? sub;
    final bool ownScan = !FlutterBluePlus.isScanningNow;
    try {
      sub = FlutterBluePlus.scanResults.listen((List<ScanResult> snapshot) {
        if (!found.isCompleted && seenIn(snapshot)) found.complete(true);
      });
      if (ownScan) {
        // The answer arrives on the results stream, so the scan itself is not
        // awaited: waiting out its own timeout would turn a hit at 200 ms into a
        // three-second pause.
        unawaited(FlutterBluePlus.startScan(
          withRemoteIds: <String>[remoteId],
          timeout: const Duration(seconds: 3),
        ));
      }
      return await found.future
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      await sub?.cancel();
      if (ownScan) {
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {/* already stopped */}
      }
    }
  }

  /// The MeshCore service's two characteristics, found but not yet usable.
  ///
  /// Discovery is unencrypted, so this runs before any pairing: a device that
  /// does not carry this service is not a radio, and must never be offered a
  /// pairing dialog.
  static Future<_Link> _locate(BluetoothDevice device) async {
    final List<BluetoothService> services = await device.discoverServices();
    final BluetoothService svc = services.firstWhere(
      (BluetoothService s) => _sameUuid(s.uuid, _service),
      orElse: () => throw BleConnectException('MeshCore service not present'),
    );
    final BluetoothCharacteristic rx = svc.characteristics.firstWhere(
      (BluetoothCharacteristic c) => _sameUuid(c.uuid, _rxUuid),
      orElse: () => throw BleConnectException('RX characteristic missing'),
    );
    final BluetoothCharacteristic tx = svc.characteristics.firstWhere(
      (BluetoothCharacteristic c) => _sameUuid(c.uuid, _txUuid),
      orElse: () => throw BleConnectException('TX characteristic missing'),
    );
    return _Link(rx, tx);
  }

  /// Subscribe on the encrypted link, and record the radio as paired.
  static Future<BleMeshcoreTransport> _subscribe(BluetoothDevice device,
      _Link link, bool writeWithoutResponse) async {
    final BluetoothCharacteristic rx = link.rx;
    final BluetoothCharacteristic tx = link.tx;
    // R111 — the negotiated MTU is read before anything else on this link.
    // `mtuNow` reports the platform's value (23 until the OS reports one), so
    // a link that never negotiated is treated as the minimum, which is what
    // it is. Android is the platform this app targets; elsewhere the number
    // is reported but not enforced, because those stacks negotiate per write.
    final int mtu = device.mtuNow;
    if (!kIsWeb && Platform.isAndroid && mtu < MeshcoreBle.requiredMtu) {
      await _safeDisconnect(device);
      throw BleMtuTooSmall(mtu);
    }
    await tx.setNotifyValue(true);
    final String name = pairedNameFor(
      platformName: device.platformName,
      advName: device.advName,
      remoteId: device.remoteId.str,
      stored: await PairedDeviceStore.read(),
    );
    await PairedDeviceStore.save(device.remoteId.str, name);
    // R41+1 — every successful pair also lands in the rolling
    // history (capped at 5, most-recent-first). Same wire layer
    // so a manual scan-pick and an auto-reconnect both promote
    // the entry uniformly.
    await PairedDeviceHistoryStore.touch(device.remoteId.str, name);
    return BleMeshcoreTransport(
      device: device,
      rx: rx,
      tx: tx,
      writeWithoutResponse: writeWithoutResponse,
      mtu: mtu,
    );
  }

  /// Disconnect without letting the teardown itself become the error.
  static Future<void> _safeDisconnect(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } catch (_) {/* already gone */}
  }

  /// Drop the OS bond for a radio, if there is one.
  ///
  /// "Forget the radio" has to mean the same thing on both routes: the app's
  /// saved pairing is cleared by the caller, and this clears Android's record,
  /// otherwise the next start adopts the bond straight back.
  static Future<void> forgetBond(String? remoteId) async {
    if (remoteId == null || kIsWeb || !Platform.isAndroid) return;
    try {
      await BluetoothDevice.fromId(remoteId).removeBond();
    } catch (_) {
      // Not bonded, already removed, or the stack refused — either way there
      // is nothing the caller can do with the failure.
    }
  }
}
