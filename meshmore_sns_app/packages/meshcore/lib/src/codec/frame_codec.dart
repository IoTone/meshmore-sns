// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import '../model/admin.dart';
import '../model/advert.dart';
import '../model/channel_info.dart';
import '../model/channel_message.dart';
import '../model/contact.dart';
import '../model/contact_message.dart';
import '../model/device_config.dart';
import '../model/diagnostics.dart';
import '../model/rf_log.dart';
import '../model/self_info.dart';
import 'byte_cursor.dart';
import 'channel_data.dart';
import 'constants.dart';
import 'decode_error.dart';
import 'inbound.dart';
import 'text_budget.dart';

/// Encodes app→device command frames and decodes device→app frames.
///
/// Frame = `[opcode][payload]`, one frame per BLE write/notification,
/// little-endian. All layouts are pinned (see [kMeshcoreFirmwarePinTag]).
///
/// [decode] is **total**: it returns a [DecodeFailure] for malformed or
/// truncated input and an [UnsupportedFrame] for opcodes not handled in
/// this milestone. It never throws.
abstract final class MeshcoreFrameCodec {
  // ---------------------------------------------------------------------
  // Encoders (App → Device)
  // ---------------------------------------------------------------------

  /// `CMD_APP_START` (0x01): `01 [7 reserved] [app name UTF-8]`.
  ///
  /// Firmware requires `len >= 8` and ignores bytes 1..7. The app name
  /// is the trailing bytes (no NUL terminator; frame-length delimited).
  static Uint8List appStart({required String appName}) {
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.appStart.code)
      ..zeros(7)
      ..utf8String(appName);
    return b.build();
  }

  /// `CMD_GET_CONTACTS` (0x04). Optionally filters to contacts modified
  /// at/after [since] (uint32 unix seconds) for incremental sync.
  static Uint8List getContacts({int? since}) {
    final FrameBuilder b = FrameBuilder()..u8(MeshcoreCommand.getContacts.code);
    if (since != null) b.u32(since);
    return b.build();
  }

  /// `CMD_GET_DEVICE_TIME` (0x05).
  static Uint8List getDeviceTime() =>
      (FrameBuilder()..u8(MeshcoreCommand.getDeviceTime.code)).build();

  /// `CMD_SET_DEVICE_TIME` (0x06): `06 [unix uint32 LE]`.
  static Uint8List setDeviceTime(int unixSeconds) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setDeviceTime.code)
          ..u32(unixSeconds))
        .build();
  }

  /// `CMD_SYNC_NEXT_MESSAGE` (0x0A).
  static Uint8List syncNextMessage() =>
      (FrameBuilder()..u8(MeshcoreCommand.syncNextMessage.code)).build();

  /// `CMD_SEND_CHANNEL_TXT_MSG` (0x03):
  /// `03 [txt_type] [channel_idx] [timestamp u32 LE] [text UTF-8]`.
  ///
  /// The app sends plaintext + channel index; the device performs the
  /// over-the-air channel encryption.
  static Uint8List sendChannelTextMessage({
    required int channelIdx,
    required int timestamp,
    required String text,
    int txtType = kTxtTypePlain,
  }) {
    final int bytes = ChannelTextLimits.bytesOf(text);
    if (bytes > ChannelTextLimits.maxTextBytes) {
      throw ChannelTextException(
        ChannelTextRefusal.textTooLong,
        actual: bytes,
        maximum: ChannelTextLimits.maxTextBytes,
      );
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendChannelMessage.code)
          ..u8(txtType)
          ..u8(channelIdx)
          ..u32(timestamp)
          ..utf8String(text))
        .build();
  }

  /// `CMD_SEND_CHANNEL_DATA` (0x3E): `3E [channel_idx] [path_len] [path]
  /// [data_type u16 LE] [blob]`.
  ///
  /// The channel's datagram carrier: the radio wraps [blob] in a group
  /// datagram of its own (type and length are written by the firmware), so
  /// the phone supplies no cipher and no length. This is the frame every
  /// media and place payload travels in.
  ///
  /// [pathLen] is the packed path byte ([PathLen]): hops in the low six
  /// bits, hash size − 1 in the top two. [kPathLenFlood] means flood, and
  /// then [path] must be empty because the firmware reads no path bytes.
  ///
  /// Two budgets bind, and the smaller one wins: the datagram's
  /// [ChannelDataLimits.maxBlob] and what this send's path leaves of the
  /// 176-byte frame. Both are refused here rather than at the radio, which
  /// answers an over-long blob with `ERR_CODE_TABLE_FULL` — the same code
  /// it uses for a full packet table.
  static Uint8List sendChannelData({
    required int channelIdx,
    required int dataType,
    required List<int> blob,
    int pathLen = kPathLenFlood,
    List<int> path = const <int>[],
  }) {
    if (channelIdx < 0 || channelIdx > 0xFF) {
      throw ChannelDataException(
        ChannelDataRefusal.channelOutOfRange,
        field: 'channelIdx',
        actual: channelIdx,
        maximum: 0xFF,
      );
    }
    if (dataType < 0 || dataType > 0xFFFF) {
      throw ChannelDataException(
        ChannelDataRefusal.dataTypeOutOfRange,
        field: 'dataType',
        actual: dataType,
        maximum: 0xFFFF,
      );
    }
    if (dataType == kChannelDataTypeReserved) {
      throw const ChannelDataException(
        ChannelDataRefusal.reservedType,
        field: 'dataType',
        actual: kChannelDataTypeReserved,
        maximum: 0xFFFF,
      );
    }
    if (pathLen == kPathLenFlood) {
      if (path.isNotEmpty) {
        throw ChannelDataException(
          ChannelDataRefusal.pathLengthMismatch,
          field: 'path',
          actual: path.length,
          maximum: 0,
        );
      }
    } else {
      final PathLen packed = PathLen(pathLen);
      if (!packed.isValid) {
        throw ChannelDataException(
          ChannelDataRefusal.invalidPathLen,
          field: 'pathLen',
          actual: pathLen,
          maximum: kMaxPathSize,
        );
      }
      if (path.length != packed.byteLength) {
        throw ChannelDataException(
          ChannelDataRefusal.pathLengthMismatch,
          field: 'path',
          actual: path.length,
          maximum: packed.byteLength,
        );
      }
    }
    final int frameMax = ChannelDataLimits.blobMaxForPath(path.length);
    if (blob.length > ChannelDataLimits.maxBlob) {
      throw ChannelDataException(
        ChannelDataRefusal.blobTooLongForDatagram,
        field: 'blob',
        actual: blob.length,
        maximum: ChannelDataLimits.maxBlob,
      );
    }
    if (blob.length > frameMax) {
      throw ChannelDataException(
        ChannelDataRefusal.blobTooLongForFrame,
        field: 'blob',
        actual: blob.length,
        maximum: frameMax,
      );
    }
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.sendChannelDatagram.code)
      ..u8(channelIdx)
      ..u8(pathLen);
    if (path.isNotEmpty) b.raw(path);
    b
      ..u16(dataType)
      ..raw(blob);
    return b.build();
  }

  /// `CMD_SEND_TXT_MSG` (0x02):
  /// `02 [txt_type] [attempt] [timestamp u32 LE] [pubkey_prefix 6]
  /// [text UTF-8]`.
  ///
  /// The recipient is addressed by the first 6 bytes of its public key.
  static Uint8List sendTextMessage({
    required List<int> pubKeyPrefix,
    required int timestamp,
    required String text,
    int txtType = kTxtTypePlain,
    int attempt = 0,
  }) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendTextMessage.code)
          ..u8(txtType)
          ..u8(attempt)
          ..u32(timestamp)
          ..fixed(pubKeyPrefix, kPubKeyPrefixSize)
          ..utf8String(text))
        .build();
  }

  /// `CMD_SEND_SELF_ADVERT` (0x07): `07 [1=flood | 0=zero-hop]`.
  static Uint8List sendSelfAdvert({bool flood = true}) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendSelfAdvert.code)
          ..u8(flood ? 1 : 0))
        .build();
  }

  /// `CMD_SET_ADVERT_NAME` (0x08): `08 [name UTF-8, <= 31 bytes]`.
  static Uint8List setAdvertName(String name) {
    final List<int> n = utf8.encode(name);
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setAdvertName.code)
          ..raw(n.length > kMaxAdvertName
              ? n.sublist(0, kMaxAdvertName)
              : n))
        .build();
  }

  /// `CMD_REMOVE_CONTACT` (0x0F): remove a contact by 32-byte public key.
  static Uint8List removeContact(Uint8List publicKey) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.removeContact.code)
          ..fixed(publicKey, kPubKeySize))
        .build();
  }

  /// `CMD_ADD_UPDATE_CONTACT` (0x09): the 148-byte contact body
  /// (same layout as `RESP_CODE_CONTACT`).
  static Uint8List addUpdateContact(Contact c) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.addUpdateContact.code)
          ..fixed(c.publicKey, kPubKeySize)
          ..u8(c.type)
          ..u8(c.flags)
          ..u8(c.outPathLen)
          ..fixed(c.outPath, kMaxPathSize)
          ..fixed(utf8.encode(c.name), kContactNameSize)
          ..u32(c.lastAdvertTimestamp)
          ..i32(c.latitudeMicros)
          ..i32(c.longitudeMicros)
          ..u32(c.lastMod))
        .build();
  }

  // ---------------------------------------------------------------------
  // Device / radio configuration (R7)
  // ---------------------------------------------------------------------

  /// `CMD_SET_RADIO_PARAMS` (0x0B):
  /// `0B [freq u32 LE ×1000] [bw u32 LE ×1000] [sf] [cr] [repeat?]`.
  static Uint8List setRadioParams(RadioParams p) {
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.setRadioParams.code)
      ..u32((p.frequencyMhz * kRadioScale).round())
      ..u32((p.bandwidthKhz * kRadioScale).round())
      ..u8(p.spreadingFactor)
      ..u8(p.codingRate);
    if (p.repeat != null) b.u8(p.repeat!);
    return b.build();
  }

  /// `CMD_SET_PATH_HASH_MODE` (0x3D): `3D 00 mode`, mode 0..2.
  ///
  /// The firmware rejects mode >= 3 with `ERR_CODE_ILLEGAL_ARG`
  /// (`MyMesh.cpp:1466-1473`), so an out-of-range value is refused here
  /// rather than sent to be rejected on the air.
  ///
  /// [hashSize] is the size in **bytes** (1, 2 or 3) because that is how
  /// MeshCore's own preset API expresses it (`path_hash_size`); the wire
  /// field is `hashSize - 1`.
  static Uint8List setPathHashMode(int hashSize) {
    if (hashSize < 1 || hashSize > 3) {
      throw ArgumentError.value(
          hashSize, 'hashSize', 'MeshCore supports 1, 2 or 3-byte path hashes');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setPathHashMode.code)
          ..u8(0)
          ..u8(hashSize - 1))
        .build();
  }

  /// `CMD_SET_FLOOD_SCOPE_KEY` (0x36): `36 00 [key 16B]`, or `36 00` alone
  /// to clear the override (`MyMesh.cpp:1936-1941`).
  static Uint8List setFloodScopeKey(List<int>? key) {
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.setFloodScopeKey.code)
      ..u8(0);
    if (key != null && key.isNotEmpty) {
      if (key.length != 16) {
        throw ArgumentError.value(
            key.length, 'key', 'flood scope key must be exactly 16 bytes');
      }
      b.raw(key);
    }
    return b.build();
  }

  /// `36 01` — send floods **unscoped** (firmware ver 12+, `MyMesh.cpp:1942`).
  static Uint8List sendUnscopedFlood() {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setFloodScopeKey.code)
          ..u8(1))
        .build();
  }

  /// `CMD_SET_DEFAULT_FLOOD_SCOPE` (0x3F).
  ///
  /// An empty frame clears the stored default (`MyMesh.cpp:1959-1963`).
  /// Otherwise the firmware needs the full 31-byte name field plus a
  /// 16-byte key, and rejects a name whose length is 0 or >= 31.
  static Uint8List setDefaultFloodScope(String? name, List<int>? key) {
    final FrameBuilder b =
        FrameBuilder()..u8(MeshcoreCommand.setDefaultFloodScope.code);
    if (name == null || name.isEmpty) return b.build();
    if (name.length >= 31) {
      throw ArgumentError.value(
          name.length, 'name', 'flood scope name must be 1..30 UTF-16 chars');
    }
    if (key == null || key.length != 16) {
      throw ArgumentError.value(
          key?.length, 'key', 'flood scope key must be exactly 16 bytes');
    }
    b
      ..fixed(utf8.encode(name), 31)
      ..raw(key);
    return b.build();
  }

  /// `CMD_GET_DEFAULT_FLOOD_SCOPE` (0x40).
  static Uint8List getDefaultFloodScope() {
    return (FrameBuilder()..u8(MeshcoreCommand.getDefaultFloodScope.code))
        .build();
  }

  /// `CMD_GET_ALLOWED_REPEAT_FREQ` (0x3C).
  static Uint8List getAllowedRepeatFreq() {
    return (FrameBuilder()..u8(MeshcoreCommand.getAllowedRepeatFreq.code))
        .build();
  }

  /// Decode the reply to [getDefaultFloodScope].
  ///
  /// Returns null when the frame is the bare response code (scope unset).
  static ({String name, Uint8List key})? decodeDefaultFloodScope(
      Uint8List frame) {
    if (frame.isEmpty || frame[0] != MeshcoreResponse.defaultFloodScope.code) {
      return null;
    }
    if (frame.length < 1 + 31 + 16) return null;
    final ByteCursor c = ByteCursor(frame)..u8('floodScope.code');
    final Uint8List rawName = c.bytes(31, 'floodScope.name');
    final int nul = rawName.indexOf(0);
    final List<int> nameBytes =
        nul == -1 ? rawName.toList() : rawName.sublist(0, nul);
    final String name = String.fromCharCodes(nameBytes);
    final Uint8List key = c.bytes(16, 'floodScope.key');
    return (name: name, key: key);
  }

  /// Decode the reply to [getAllowedRepeatFreq] into (lower, upper) ranges in
  /// kHz. The firmware packs as many 8-byte pairs as fit in one frame
  /// (`MyMesh.cpp:1994-2002`).
  static List<({int lowerKhz, int upperKhz})> decodeAllowedRepeatFreq(
      Uint8List frame) {
    final List<({int lowerKhz, int upperKhz})> out =
        <({int lowerKhz, int upperKhz})>[];
    if (frame.isEmpty || frame[0] != MeshcoreResponse.allowedRepeatFreq.code) {
      return out;
    }
    final ByteCursor c = ByteCursor(frame)..u8('allowedRepeat.code');
    while (c.remaining >= 8) {
      final int lo = c.u32('allowedRepeat.lower');
      final int hi = c.u32('allowedRepeat.upper');
      out.add((lowerKhz: lo, upperKhz: hi));
    }
    return out;
  }

  /// `CMD_SET_RADIO_TX_POWER` (0x0C): `0C [power int8 dBm]`.
  static Uint8List setRadioTxPower(int dbm) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setRadioTxPower.code)
          ..u8(dbm & 0xFF))
        .build();
  }

  /// `CMD_SET_ADVERT_LATLON` (0x0E):
  /// `0E [lat i32 LE ×1e6] [lon i32 LE ×1e6] [alt i32 LE optional]`.
  static Uint8List setAdvertLatLon({
    required int latitudeMicros,
    required int longitudeMicros,
    int? altitudeMicros,
  }) {
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.setAdvertLatLon.code)
      ..i32(latitudeMicros)
      ..i32(longitudeMicros);
    if (altitudeMicros != null) b.i32(altitudeMicros);
    return b.build();
  }

  /// `CMD_SET_OTHER_PARAMS` (0x26):
  /// `26 [manual_add] [telemetry_packed] [loc_policy?] [multi_acks?]`.
  static Uint8List setOtherParams({
    required int manualAddContacts,
    required int telemetryModePacked,
    int? advertLocPolicy,
    int? multiAcks,
  }) {
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.setOtherParams.code)
      ..u8(manualAddContacts)
      ..u8(telemetryModePacked);
    if (advertLocPolicy != null) {
      b.u8(advertLocPolicy);
      if (multiAcks != null) b.u8(multiAcks);
    }
    return b.build();
  }

  /// `CMD_GET_CUSTOM_VARS` (0x28): request the device's custom
  /// string-keyed settings (`gps`, `gps_interval`, etc.). Reply is
  /// `RESP_CODE_CUSTOM_VARS` (0x15) decoded into [CustomVarsFrame].
  static Uint8List getCustomVars() =>
      (FrameBuilder()..u8(MeshcoreCommand.getCustomVars.code)).build();

  /// `CMD_SET_CUSTOM_VAR` (0x29): write a single string-keyed setting.
  /// Body: `[opcode][name]:[value]` (ASCII, no NUL — frame length
  /// defines end). The firmware splits on the first `:` so values
  /// containing `:` would be truncated; values containing `,` are
  /// fine since they aren't a separator on the request path.
  static Uint8List setCustomVar({
    required String name,
    required String value,
  }) {
    assert(!name.contains(':'),
        'custom var name must not contain ":" (frame separator)');
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setCustomVar.code)
          ..utf8String('$name:$value'))
        .build();
  }

  /// `CMD_SEND_TELEMETRY_REQ` (0x27).
  ///
  /// - No [peerPubKey]: requests *self* telemetry; the device replies
  ///   immediately (no OTA) with [MeshcoreResponse.telemetryResponse]
  ///   (0x8B) carrying its own CayenneLPP payload.
  /// - With [peerPubKey] (32 bytes): asks the device to query the peer
  ///   over the air. Same 0x8B push arrives later (seconds) if the
  ///   peer responds. Caller is responsible for batching/back-off.
  ///
  /// The 3 bytes between opcode and pubkey are reserved (zero in
  /// `companion-v1.15.0`). Sending zeros is safe today; if firmware
  /// later uses them for a permission mask, callers will set them.
  static Uint8List sendTelemetryReq({List<int>? peerPubKey}) {
    assert(peerPubKey == null || peerPubKey.length == kPubKeySize,
        'peerPubKey must be exactly $kPubKeySize bytes');
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.sendTelemetryReq.code)
      ..zeros(3);
    if (peerPubKey != null) b.fixed(peerPubKey, kPubKeySize);
    return b.build();
  }

  /// `CMD_SET_TUNING_PARAMS` (0x15):
  /// `15 [rx_delay_base u32 LE ×1000] [airtime_factor u32 LE ×1000]`.
  static Uint8List setTuningParams({
    required double rxDelayBaseSeconds,
    required double airtimeFactor,
  }) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setTuningParams.code)
          ..u32((rxDelayBaseSeconds * kRadioScale).round())
          ..u32((airtimeFactor * kRadioScale).round()))
        .build();
  }

  /// `CMD_DEVICE_QUERY` (0x16): `16 [app_target_ver]`.
  ///
  /// The default is [kAppTargetProtocolVersion] (3) because that is the
  /// version whose receive frames carry per-message SNR; see the constant
  /// for the firmware branches it selects.
  static Uint8List deviceQuery({int appTargetVer = kAppTargetProtocolVersion}) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.deviceQuery.code)
          ..u8(appTargetVer))
        .build();
  }

  /// `CMD_GET_BATT_AND_STORAGE` (0x14): `14`.
  static Uint8List getBatteryStorage() =>
      (FrameBuilder()..u8(MeshcoreCommand.getBatteryStorage.code)).build();

  /// `CMD_GET_CHANNEL` (0x1F): `1F [channel_idx]`.
  static Uint8List getChannel(int channelIdx) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.getChannel.code)
          ..u8(channelIdx))
        .build();
  }

  /// `CMD_SET_CHANNEL` (0x20):
  /// `20 [channel_idx] [name 32B NUL-padded] [secret 16B]` (50 bytes).
  ///
  /// [psk] is the 16-byte AES-128 channel key as carried by the
  /// companion link (truncated/zero-padded to [kChannelPskSize]).
  static Uint8List setChannel({
    required int channelIdx,
    required String name,
    required List<int> psk,
  }) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setChannel.code)
          ..u8(channelIdx)
          ..fixed(utf8.encode(name), kChannelNameSize)
          ..fixed(psk, kChannelPskSize))
        .build();
  }

  // --- R60 Tools ---------------------------------------------------------

  /// `CMD_GET_STATS` (0x38): `38 [sub_type]` — one of [kStatsTypeCore],
  /// [kStatsTypeRadio], [kStatsTypePackets].
  static Uint8List getStats(int subType) {
    return (FrameBuilder()
          ..u8(MeshcoreCommand.getStats.code)
          ..u8(subType))
        .build();
  }

  /// `CMD_SEND_STATUS_REQ` (0x1B): `1B [pub_key 32]`.
  static Uint8List sendStatusReq(List<int> pubKey) {
    assert(pubKey.length == kPubKeySize);
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendStatusReq.code)
          ..fixed(pubKey, kPubKeySize))
        .build();
  }

  /// `CMD_RESET_PATH` (0x0D): `0D [pub_key 32]`.
  static Uint8List resetPath(List<int> pubKey) {
    assert(pubKey.length == kPubKeySize);
    return (FrameBuilder()
          ..u8(MeshcoreCommand.resetPath.code)
          ..fixed(pubKey, kPubKeySize))
        .build();
  }

  /// `CMD_SEND_TRACE_PATH` (0x24):
  /// `24 [tag u32] [auth u32] [flags] [path hashes…]`.
  ///
  /// The low two bits of `flags` give the hash size (0 = 1 byte, 1 = 2,
  /// 2 = 4, 3 = 8); [path] must be a whole number of hashes. Firmware
  /// rejects an empty path (`len > 10`), so callers must pass at least
  /// one hop.
  static Uint8List sendTracePath({
    required int tag,
    required List<int> path,
    int authCode = 0,
    int hashSizeCode = 0,
  }) {
    assert(path.isNotEmpty, 'a trace needs at least one hop');
    assert(path.length % (1 << hashSizeCode) == 0);
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendTracePath.code)
          ..u32(tag)
          ..u32(authCode)
          ..u8(hashSizeCode & 0x03)
          ..raw(path))
        .build();
  }

  /// `CMD_SEND_CONTROL_DATA` (0x37) carrying a `NODE_DISCOVER_REQ`:
  /// `37 [0x80 | prefix_only] [type filter bitmask] [tag u32] [since u32]?`.
  /// Sent zero-hop; repeaters matching [typeFilter] answer with a
  /// [ControlDataFrame] after a random delay.
  static Uint8List sendDiscoverReq({
    required int tag,
    int typeFilter = 1 << kAdvTypeRepeater,
    bool prefixOnly = false,
    int? since,
  }) {
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.sendControlData.code)
      ..u8(kCtlTypeNodeDiscoverReq | (prefixOnly ? 1 : 0))
      ..u8(typeFilter)
      ..u32(tag);
    if (since != null) b.u32(since);
    return b.build();
  }

  // ---------------------------------------------------------------------
  // Contact lifecycle, identity and admin (companion-v1.17.1, d929643).
  //
  // Every encoder refuses an argument the firmware would silently
  // truncate, ignore or reject, with an [ArgumentError], rather than
  // spending airtime (or, for the destructive ones, an irreversible
  // action) to find out.
  // ---------------------------------------------------------------------

  static void _requireKey(List<int> key, String name) {
    if (key.length != kPubKeySize) {
      throw ArgumentError.value(
          key.length, name, 'must be exactly $kPubKeySize bytes');
    }
  }

  static Uint8List _keyed(MeshcoreCommand cmd, List<int> pubKey) {
    _requireKey(pubKey, 'pubKey');
    return (FrameBuilder()
          ..u8(cmd.code)
          ..raw(pubKey))
        .build();
  }

  /// `CMD_SHARE_CONTACT` (0x10): `10 [pub_key 32]` (`MyMesh.cpp:1319`).
  ///
  /// The firmware has no length guard here, so a short frame would read
  /// stale bytes as the key; exactly 32 bytes are required.
  static Uint8List shareContact(List<int> pubKey) =>
      _keyed(MeshcoreCommand.shareContact, pubKey);

  /// `CMD_EXPORT_CONTACT` (0x11): `11` exports **self**, `11 [pub_key 32]`
  /// exports that contact (`MyMesh.cpp:1339-1367`). Any frame shorter than
  /// 33 bytes means self, so a partial key is refused.
  static Uint8List exportContact({List<int>? pubKey}) {
    if (pubKey == null) {
      return Uint8List.fromList(<int>[MeshcoreCommand.exportContact.code]);
    }
    return _keyed(MeshcoreCommand.exportContact, pubKey);
  }

  /// `CMD_IMPORT_CONTACT` (0x12): `12 [advert packet]` (`MyMesh.cpp:1369`).
  ///
  /// The firmware requires `len > 98` including the opcode and, when the
  /// guard fails, falls through to `ERR_CODE_UNSUPPORTED_CMD`. Whether the
  /// packet is a valid advert is only known to the firmware, which answers
  /// `ERR_CODE_ILLEGAL_ARG`.
  static Uint8List importContact(List<int> advertPacket) {
    if (advertPacket.length < kImportContactMin ||
        advertPacket.length > kImportContactMax) {
      throw ArgumentError.value(advertPacket.length, 'advertPacket',
          'must be $kImportContactMin..$kImportContactMax bytes');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.importContact.code)
          ..raw(advertPacket))
        .build();
  }

  /// `CMD_REBOOT` (0x13): `13 "reboot"`. There is no reply; the link drops
  /// (`MyMesh.cpp:1474-1479`).
  static Uint8List reboot() => (FrameBuilder()
        ..u8(MeshcoreCommand.reboot.code)
        ..utf8String('reboot'))
      .build();

  /// `CMD_FACTORY_RESET` (0x33): `33 "reset"` (`MyMesh.cpp:1923`).
  ///
  /// **Irreversible**: formats the filesystem (identity, contacts,
  /// channels, prefs). The firmware disables the link before replying, so
  /// the OK frame may never arrive. [confirmed] must be `true`.
  static Uint8List factoryReset({required bool confirmed}) {
    if (!confirmed) {
      throw ArgumentError.value(
          confirmed, 'confirmed', 'factory reset needs explicit confirmation');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.factoryReset.code)
          ..utf8String('reset'))
        .build();
  }

  /// `CMD_EXPORT_PRIVATE_KEY` (0x17): `17`. The reply is
  /// `RESP_CODE_PRIVATE_KEY` or `RESP_CODE_DISABLED`; there is no
  /// authentication beyond the BLE link itself (`MyMesh.cpp:1490-1498`).
  static Uint8List exportPrivateKey() =>
      Uint8List.fromList(<int>[MeshcoreCommand.exportPrivateKey.code]);

  /// `CMD_IMPORT_PRIVATE_KEY` (0x18): `18 [key 64]` (`MyMesh.cpp:1499`).
  ///
  /// **Replaces the node's identity**: the public key changes, every
  /// stored shared secret is invalidated and peers see a new node.
  /// [confirmed] must be `true`.
  static Uint8List importPrivateKey(List<int> privateKey,
      {required bool confirmed}) {
    if (!confirmed) {
      throw ArgumentError.value(confirmed, 'confirmed',
          'replacing the identity needs explicit confirmation');
    }
    if (privateKey.length != kPrivKeySize) {
      throw ArgumentError.value(
          privateKey.length, 'privateKey', 'must be exactly $kPrivKeySize bytes');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.importPrivateKey.code)
          ..raw(privateKey))
        .build();
  }

  /// `CMD_SEND_LOGIN` (0x1A): `1A [pub_key 32] [password]`
  /// (`MyMesh.cpp:1535`).
  ///
  /// The firmware treats the frame end as a NUL and then silently cuts the
  /// password to 15 bytes (`BaseChatMesh.cpp:581,585`). A longer password,
  /// or one with an embedded NUL, is refused here so it cannot be
  /// truncated into a different password. The reply is
  /// `RESP_CODE_SENT`; the verdict arrives as 0x85 or 0x86.
  static Uint8List sendLogin(List<int> pubKey, String password) {
    _requireKey(pubKey, 'pubKey');
    final List<int> pw = utf8.encode(password);
    if (pw.length > kLoginPasswordMax) {
      throw ArgumentError.value(pw.length, 'password',
          'at most $kLoginPasswordMax bytes (firmware truncates silently)');
    }
    if (pw.contains(0)) {
      throw ArgumentError.value(password, 'password', 'must not contain NUL');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendLogin.code)
          ..raw(pubKey)
          ..raw(pw))
        .build();
  }

  /// `CMD_HAS_CONNECTION` (0x1C): OK = a keep-alive session exists,
  /// ERR(not_found) = none (`MyMesh.cpp:1699`).
  static Uint8List hasConnection(List<int> pubKey) =>
      _keyed(MeshcoreCommand.hasConnection, pubKey);

  /// `CMD_LOGOUT` (0x1D): always answers OK, even for an unknown key
  /// (`MyMesh.cpp:1706`).
  static Uint8List logout(List<int> pubKey) =>
      _keyed(MeshcoreCommand.logout, pubKey);

  /// `CMD_GET_CONTACT_BY_KEY` (0x1E): reply is `RESP_CODE_CONTACT` or
  /// ERR(not_found). No length guard in firmware (`MyMesh.cpp:1331`).
  static Uint8List getContactByKey(List<int> pubKey) =>
      _keyed(MeshcoreCommand.getContactByKey, pubKey);

  /// `CMD_SIGN_START` (0x21): reply is `RESP_CODE_SIGN_START`. Discards any
  /// signing buffer in progress (`MyMesh.cpp:1739`).
  static Uint8List signStart() =>
      Uint8List.fromList(<int>[MeshcoreCommand.signStart.code]);

  /// `CMD_SIGN_DATA` (0x22): one chunk of 1..175 bytes (`MyMesh.cpp:1751`).
  static Uint8List signData(List<int> chunk) {
    if (chunk.isEmpty || chunk.length > kSignChunkMax) {
      throw ArgumentError.value(
          chunk.length, 'chunk', 'must be 1..$kSignChunkMax bytes');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.signData.code)
          ..raw(chunk))
        .build();
  }

  /// Split [data] into `CMD_SIGN_DATA` frames. Refuses data over the
  /// device's 8 KiB buffer ([kMaxSignDataLen]) or empty data.
  static List<Uint8List> signDataFrames(List<int> data) {
    if (data.isEmpty || data.length > kMaxSignDataLen) {
      throw ArgumentError.value(
          data.length, 'data', 'must be 1..$kMaxSignDataLen bytes');
    }
    final List<Uint8List> out = <Uint8List>[];
    for (int i = 0; i < data.length; i += kSignChunkMax) {
      final int end =
          i + kSignChunkMax < data.length ? i + kSignChunkMax : data.length;
      out.add(signData(data.sublist(i, end)));
    }
    return out;
  }

  /// `CMD_SIGN_FINISH` (0x23): reply is `RESP_CODE_SIGNATURE` or
  /// ERR(bad_state) when no signing is in progress (`MyMesh.cpp:1759`).
  static Uint8List signFinish() =>
      Uint8List.fromList(<int>[MeshcoreCommand.signFinish.code]);

  /// `CMD_SET_DEVICE_PIN` (0x25): `25 [pin u32 LE]`. 0 clears the PIN,
  /// otherwise exactly six digits, 100000..999999 (`MyMesh.cpp:1797-1812`).
  static Uint8List setDevicePin(int pin) {
    if (pin != 0 && (pin < 100000 || pin > 999999)) {
      throw ArgumentError.value(
          pin, 'pin', 'must be 0 (none) or a 6-digit number');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.setDevicePin.code)
          ..u32(pin))
        .build();
  }

  /// `CMD_GET_ADVERT_PATH` (0x2A): `2A 00 [pub_key 32]`. The firmware
  /// matches only the first 7 bytes (`MyMesh.cpp:1851-1862`).
  static Uint8List getAdvertPath(List<int> pubKey) {
    _requireKey(pubKey, 'pubKey');
    return (FrameBuilder()
          ..u8(MeshcoreCommand.getAdvertPath.code)
          ..u8(0)
          ..raw(pubKey))
        .build();
  }

  /// `CMD_GET_TUNING_PARAMS` (0x2B): reply `RESP_CODE_TUNING_PARAMS`.
  static Uint8List getTuningParams() =>
      Uint8List.fromList(<int>[MeshcoreCommand.getTuningParams.code]);

  /// `CMD_SEND_PATH_DISCOVERY_REQ` (0x34): `34 00 [pub_key 32]`
  /// (`MyMesh.cpp:1609`). Always floods. Reply `RESP_CODE_SENT` (tag),
  /// result arrives later as `PUSH_CODE_PATH_DISCOVERY_RESPONSE`.
  static Uint8List sendPathDiscoveryReq(List<int> pubKey) {
    _requireKey(pubKey, 'pubKey');
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendPathDiscoveryReq.code)
          ..u8(0)
          ..raw(pubKey))
        .build();
  }

  /// `CMD_SEND_ANON_REQ` (0x39): `39 [pub_key 32] [data]`
  /// (`MyMesh.cpp:1557`).
  ///
  /// [data] is 1..[kAnonReqDataMax] bytes: more than that makes
  /// `Mesh::createAnonDatagram` fail (`Mesh.cpp:514`) and the firmware
  /// answers ERR(table_full). **Side effect**: an unknown key is added as
  /// a transient contact (`MyMesh.cpp:1561-1570`).
  static Uint8List sendAnonReq(List<int> pubKey, List<int> data) {
    _requireKey(pubKey, 'pubKey');
    if (data.isEmpty || data.length > kAnonReqDataMax) {
      throw ArgumentError.value(
          data.length, 'data', 'must be 1..$kAnonReqDataMax bytes');
    }
    return (FrameBuilder()
          ..u8(MeshcoreCommand.sendAnonReq.code)
          ..raw(pubKey)
          ..raw(data))
        .build();
  }

  /// `CMD_SET_AUTOADD_CONFIG` (0x3A): `3A [flags] [max_hops]`
  /// (`MyMesh.cpp:1981-1987`). [maxHops] is optional on the wire; when
  /// omitted the stored value is left alone. The firmware clamps it to 64
  /// silently, so a larger value is refused.
  static Uint8List setAutoAddConfig(int flags, {int? maxHops}) {
    if (flags < 0 || flags > 0xFF) {
      throw ArgumentError.value(flags, 'flags', 'must fit in one byte');
    }
    if (maxHops != null && (maxHops < 0 || maxHops > kAutoAddMaxHops)) {
      throw ArgumentError.value(
          maxHops, 'maxHops', 'must be 0..$kAutoAddMaxHops');
    }
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.setAutoAddConfig.code)
      ..u8(flags);
    if (maxHops != null) b.u8(maxHops);
    return b.build();
  }

  /// `CMD_GET_AUTOADD_CONFIG` (0x3B): reply `RESP_CODE_AUTOADD_CONFIG`.
  static Uint8List getAutoAddConfig() =>
      Uint8List.fromList(<int>[MeshcoreCommand.getAutoAddConfig.code]);

  // ---------------------------------------------------------------------
  // Decoder (Device → App) — total, never throws.
  // ---------------------------------------------------------------------

  static MeshcoreInbound decode(Uint8List frame) {
    if (frame.isEmpty) {
      return const DecodeFailure(
        MeshcoreDecodeError(DecodeErrorKind.empty, 'empty frame'),
      );
    }
    final int op = frame[0];
    final ByteCursor c = ByteCursor(frame);
    final MeshcoreInbound out;
    try {
      c.u8('opcode'); // consume opcode
      out = _decodeBody(c, op, frame);
    } on FrameTruncated catch (e) {
      return DecodeFailure(
        MeshcoreDecodeError(DecodeErrorKind.truncated, e.toString(),
            opcode: op),
      );
    }
    // Every layout below describes one whole frame, so a parsed frame must
    // end exactly at the frame's end. A leftover is either a second frame
    // in the same buffer (a transport-boundary error) or a length the
    // recorded layout does not explain; both are reported, never dropped.
    if (out is UnsupportedFrame || out is DecodeFailure) return out;
    if (c.remaining != 0) {
      return DecodeFailure(MeshcoreDecodeError(
        DecodeErrorKind.trailingBytes,
        '${c.remaining} byte(s) left after a complete ${out.runtimeType}',
        opcode: op,
      ));
    }
    return out;
  }

  /// Decodes one frame body. The opcode byte has already been consumed.
  static MeshcoreInbound _decodeBody(
      ByteCursor c, int op, Uint8List frame) {
    switch (op) {
        case 0x00: // RESP_CODE_OK
          final int? v = c.remaining >= 4 ? c.u32('ok.value') : null;
          return OkFrame(v);

        case 0x01: // RESP_CODE_ERR
          final int? code = c.remaining >= 1 ? c.u8('err.code') : null;
          return ErrorFrame(code);

        case 0x02: // RESP_CODE_CONTACTS_START
          return ContactsStartFrame(c.u32('contactsStart.count'));

        case 0x03: // RESP_CODE_CONTACT
          return ContactFrame(_decodeContact(c));

        case 0x04: // RESP_CODE_END_OF_CONTACTS
          return EndOfContactsFrame(c.u32('endOfContacts.lastMod'));

        case 0x05: // RESP_CODE_SELF_INFO
          return SelfInfoFrame(_decodeSelfInfo(c));

        case 0x06: // RESP_CODE_SENT
          return MsgSentFrame(MsgSent(
            isFlood: c.u8('msgSent.floodFlag') != 0,
            expectedAck: c.u32('msgSent.expectedAck'),
            estTimeoutMs: c.u32('msgSent.estTimeoutMs'),
          ));

        case 0x07: // RESP_CODE_CONTACT_MSG_RECV (legacy)
          return ContactMessageFrame(_decodeContactMsg(c, v3: false));

        case 0x08: // RESP_CODE_CHANNEL_MSG_RECV (legacy)
          return ChannelMessageFrame(_decodeChannelMsg(c, v3: false));

        case 0x09: // RESP_CODE_CURR_TIME
          return CurrentTimeFrame(c.u32('currentTime.unix'));

        case 0x0C: // RESP_CODE_BATT_AND_STORAGE
          return BatteryStorageFrame(BatteryStorage(
            batteryMillivolts: c.u16('battery.mv'),
            storageUsedKb: c.u32('battery.usedKb'),
            storageTotalKb: c.u32('battery.totalKb'),
          ));

        case 0x0D: // RESP_CODE_DEVICE_INFO
          // The fields after the 20-byte version string are version-gated:
          // `repeat_enabled` arrived at companion protocol 9 and
          // `path_hash_mode` at 10, so the frame is 80, 81 or 82 bytes and
          // nothing in it says which except its own length. Reading the two
          // unconditionally made every radio older than version 9 fail the
          // whole decode with a truncation error, which cost the app the
          // device's name, build date, contact capacity and channel count.
          // The length decides, and the version has to agree before the tail
          // is treated as a reading rather than a default.
          final int diVer = c.u8('deviceInfo.fwVer');
          final int diContacts = c.u8('deviceInfo.maxContactsHalf') * 2;
          final int diChannels = c.u8('deviceInfo.maxGroupChannels');
          final int diPin = c.u32('deviceInfo.blePin');
          final String diBuild =
              c.fixedCString(kDeviceBuildDateSize, 'deviceInfo.build');
          final String diMfr = c.fixedCString(
              kDeviceManufacturerSize, 'deviceInfo.manufacturer');
          final String diFw = c.fixedCString(
              kDeviceFirmwareVersionSize, 'deviceInfo.fwVersion');
          final bool hasRepeat = diVer >= 9 && c.remaining >= 1;
          final int repeat = hasRepeat ? c.u8('deviceInfo.clientRepeat') : 0;
          final bool hasPathHash = diVer >= 10 && c.remaining >= 1;
          final int pathHash =
              hasPathHash ? c.u8('deviceInfo.pathHashMode') : 0;
          // A tail this build does not model is a field added to the struct,
          // not a second frame.
          c.skipRemaining('device info struct grows in place');
          return DeviceInfoFrame(DeviceInfo(
            firmwareVerCode: diVer,
            maxContacts: diContacts,
            maxGroupChannels: diChannels,
            blePin: diPin,
            firmwareBuildDate: diBuild,
            manufacturer: diMfr,
            firmwareVersion: diFw,
            clientRepeat: repeat,
            pathHashMode: pathHash,
            hasClientRepeat: hasRepeat,
            hasPathHashMode: hasPathHash,
          ));

        case 0x0A: // RESP_CODE_NO_MORE_MESSAGES
          return const NoMoreMessagesFrame();

        case 0x15: // RESP_CODE_CUSTOM_VARS
          return CustomVarsFrame(_decodeCustomVars(c));

        case 0x10: // RESP_CODE_CONTACT_MSG_RECV_V3
          return ContactMessageFrame(_decodeContactMsg(c, v3: true));

        case 0x11: // RESP_CODE_CHANNEL_MSG_RECV_V3
          return ChannelMessageFrame(_decodeChannelMsg(c, v3: true));

        case 0x12: // RESP_CODE_CHANNEL_INFO
          // The reply carries 16 bytes of secret for an ordinary request
          // and 32 when the request asked for the full secret with a third
          // byte of 32 (`MyMesh.cpp:1715-1721` mainline writes 16, the
          // two-width path is the documented extension). Only the frame
          // length says which, so read whatever follows the name and
          // reject a width the firmware does not send.
          final int infoIdx = c.u8('channelInfo.idx');
          final String infoName =
              c.fixedCString(kChannelNameSize, 'channelInfo.name');
          final Uint8List infoPsk = Uint8List.fromList(
              c.bytes(c.remaining, 'channelInfo.psk'));
          if (infoPsk.length != kChannelPskSize &&
              infoPsk.length != kChannelPskSizeFull) {
            return DecodeFailure(MeshcoreDecodeError(
              DecodeErrorKind.truncated,
              'CHANNEL_INFO secret is ${infoPsk.length} bytes; the radio '
              'sends $kChannelPskSize or $kChannelPskSizeFull',
              opcode: 0x12,
            ));
          }
          return ChannelInfoFrame(ChannelInfo(
            channelIdx: infoIdx,
            name: infoName,
            psk: infoPsk,
          ));

        case 0x82: // PUSH_CODE_ACK
          // Delivery ACK for a direct message: a 4-byte CRC tag
          // matching the MsgSent.expectedAck we recorded on send.
          // Some firmware appends round-trip info; we only need the
          // leading tag. Guard for a short/empty payload.
          final int ack =
              c.remaining >= 4 ? c.u32('ack.crc') : 0;
          final int? rtt = c.remaining >= 4 ? c.u32('ack.rtt') : null;
          return AckFrame(ack, roundTripMs: rtt);

        case 0x83: // PUSH_CODE_MSGS_WAITING
          final int? n = c.remaining >= 1 ? c.u8('msgsWaiting.count') : null;
          return MessagesWaitingFrame(n);

        case 0x80: // PUSH_CODE_ADVERTISEMENT
          return AdvertFrame(_decodeAdvert(c));

        case 0x88: // PUSH_CODE_LOG_RX_DATA
          final double snr = c.i8('rfLog.snr') / 4.0;
          final int rssi = c.i8('rfLog.rssi');
          final Uint8List raw =
              c.atEnd ? Uint8List(0) : c.bytes(c.remaining, 'rfLog.raw');
          return RfLogFrame(RfLog(snrDb: snr, rssi: rssi, raw: raw));

        case 0x8B: // PUSH_CODE_TELEMETRY_RESPONSE
          c.u8('telemetry.reserved');
          final Uint8List pub6 =
              c.bytes(kPubKeyPrefixSize, 'telemetry.pubKey6');
          final Uint8List lpp = c.atEnd
              ? Uint8List(0)
              : c.bytes(c.remaining, 'telemetry.lpp');
          return TelemetryResponseFrame(
              pubKeyPrefix: pub6, lppPayload: lpp);

        case 0x18: // RESP_CODE_STATS
          return _decodeStats(c, frame);

        case 0x87: // PUSH_CODE_STATUS_RESPONSE
          c.u8('status.reserved');
          final Uint8List pub6 = c.bytes(kPubKeyPrefixSize, 'status.pubKey6');
          final RepeaterStatus? rs = _decodeRepeaterStatus(c);
          // The firmware forwards the repeater's on-air status payload
          // verbatim (`MyMesh.cpp:718-724` copies `data[4..len]`), so its
          // length belongs to the repeater, not to this layout. Anything
          // after the fields we model is that payload's tail.
          c.skipRemaining('repeater status payload is forwarded verbatim');
          return StatusResponseFrame(
              pubKeyPrefix: pub6, status: rs);

        case 0x89: // PUSH_CODE_TRACE_DATA
          return TraceDataFrame(_decodeTrace(c));

        case 0x8E: // PUSH_CODE_CONTROL_DATA
          final double snr = c.i8('control.snr') / 4.0;
          final int rssi = c.i8('control.rssi');
          final int pathLen = c.u8('control.pathLen');
          // The firmware copies the payload straight after path_len —
          // no path bytes, whatever path_len says.
          final Uint8List payload = c.atEnd
              ? Uint8List(0)
              : c.bytes(c.remaining, 'control.payload');
          return ControlDataFrame(
            snrDb: snr,
            rssi: rssi,
            pathLen: pathLen,
            payload: payload,
            discover: _decodeDiscover(payload, snr, rssi),
          );

        case 0x0B: // RESP_CODE_EXPORT_CONTACT
          return ExportedContactFrame(c.atEnd
              ? Uint8List(0)
              : Uint8List.fromList(c.bytes(c.remaining, 'export.packet')));

        case 0x0E: // RESP_CODE_PRIVATE_KEY
          return PrivateKeyFrame(c.bytes(kPrivKeySize, 'privateKey.key'));

        case 0x0F: // RESP_CODE_DISABLED
          return const DisabledFrame();

        case 0x13: // RESP_CODE_SIGN_START
          c.u8('signStart.reserved');
          return SignStartFrame(c.u32('signStart.maxLen'));

        case 0x14: // RESP_CODE_SIGNATURE
          return SignatureFrame(c.bytes(kSignatureSize, 'signature'));

        case 0x16: // RESP_CODE_ADVERT_PATH
          final int at = c.u32('advertPath.ts');
          final PathLen apl = PathLen(c.u8('advertPath.pathLen'));
          return AdvertPathFrame(AdvertPath(
            receivedAt: at,
            pathLen: apl,
            path: _readPath(c, apl, 'advertPath.path'),
          ));

        case 0x17: // RESP_CODE_TUNING_PARAMS
          return TuningParamsFrame(TuningParams(
            rxDelayBaseSeconds: c.u32('tuning.rx') / kRadioScale,
            airtimeFactor: c.u32('tuning.af') / kRadioScale,
          ));

        case 0x19: // RESP_CODE_AUTOADD_CONFIG
          return AutoAddConfigFrame(AutoAddConfig(
            flags: c.u8('autoAdd.flags'),
            maxHops: c.u8('autoAdd.maxHops'),
          ));

        case 0x85: // PUSH_CODE_LOGIN_SUCCESS
          final int perm = c.u8('login.permissions');
          final Uint8List lp = c.bytes(kPubKeyPrefixSize, 'login.pubKey6');
          int? ts, acl, lvl;
          // The new-format frame appends 4+1+1 bytes; the legacy one stops.
          if (c.remaining >= 6) {
            ts = c.u32('login.serverTs');
            acl = c.u8('login.acl');
            lvl = c.u8('login.fwLevel');
          }
          // This frame has already grown once in place — the same writer
          // added the timestamp, ACL and firmware level to the legacy
          // 8-byte form (`MyMesh.cpp:684-702`) — so a tail shorter than a
          // whole extension is a future field, not a second frame. It is
          // consumed without being guessed at.
          c.skipRemaining('login reply has grown in place before');
          return LoginResultFrame(LoginResult(
            success: true,
            permissions: perm,
            pubKeyPrefix: lp,
            serverTimestamp: ts,
            aclPermissions: acl,
            firmwareLevel: lvl,
          ));

        case 0x86: // PUSH_CODE_LOGIN_FAIL
          c.u8('login.reserved');
          return LoginResultFrame(LoginResult(
            success: false,
            permissions: 0,
            pubKeyPrefix: c.bytes(kPubKeyPrefixSize, 'login.pubKey6'),
          ));

        case 0x8D: // PUSH_CODE_PATH_DISCOVERY_RESPONSE
          c.u8('discovery.reserved');
          final Uint8List dp = c.bytes(kPubKeyPrefixSize, 'discovery.pubKey6');
          final PathLen outL = PathLen(c.u8('discovery.outPathLen'));
          final Uint8List outP = _readPath(c, outL, 'discovery.outPath');
          final PathLen inL = PathLen(c.u8('discovery.inPathLen'));
          final Uint8List inP = _readPath(c, inL, 'discovery.inPath');
          return PathDiscoveryFrame(PathDiscoveryResult(
            pubKeyPrefix: dp,
            outPathLen: outL,
            outPath: outP,
            inPathLen: inL,
            inPath: inP,
          ));

        case 0x8F: // PUSH_CODE_CONTACT_DELETED
          return ContactDeletedFrame(c.bytes(kPubKeySize, 'deleted.pubKey'));

        case 0x81: // PUSH_CODE_PATH_UPDATED
          return PathUpdatedFrame(c.bytes(kPubKeySize, 'pathUpdated.pubKey'));

        case 0x84: // PUSH_CODE_RAW_DATA
          final int rawSnr = c.u8('raw.snr');
          final int rawRssi = c.u8('raw.rssi');
          // 0xFF on a single-profile radio; 0xA0/0xA1 when a second
          // profile is on (`onRawDataRecv`, `MyMesh.cpp:2830-2840`).
          final RxVia rawVia = RxVia.fromWireByte(c.u8('raw.via'));
          return RawDataFrame(
            snrDb: (rawSnr < 128 ? rawSnr : rawSnr - 256) / 4.0,
            rssi: rawRssi < 128 ? rawRssi : rawRssi - 256,
            payload: Uint8List.fromList(c.bytes(c.remaining, 'raw.payload')),
            via: rawVia,
          );

        case 0x8A: // PUSH_CODE_NEW_ADVERT
          return NewAdvertFrame(_decodeContact(c));

        case 0x1B: // RESP_CODE_CHANNEL_DATA_RECV
          final int cdSnr = c.u8('chdata.snr');
          // The firmware leaves this byte reserved on a single-profile
          // radio (writes 0) and reports the receiving profile in it while
          // a second profile is on: 0xA0 primary, 0xA1 radio2
          // (`onChannelDataRecv`, `MyMesh.cpp:2423`).
          final RxVia cdVia = RxVia.fromWireByte(c.u8('chdata.via'));
          c.u8('chdata.reserved2');
          final int cdIdx = c.u8('chdata.channel');
          final int cdPath = c.u8('chdata.pathLen');
          final int cdType = c.u16('chdata.dataType');
          final int cdLen = c.u8('chdata.len');
          final Uint8List cdData =
              Uint8List.fromList(c.bytes(cdLen, 'chdata.data'));
          return ChannelDataFrame(
            snrDb: (cdSnr < 128 ? cdSnr : cdSnr - 256) / 4.0,
            channelIndex: cdIdx,
            pathLen: cdPath,
            dataType: cdType,
            data: cdData,
            via: cdVia,
          );

        case 0x1D: // RESP_CODE_CLI_REPLY
          return CliReplyFrame(c.utf8ToEnd('cliReply.text'));

        case 0x90: // PUSH_CODE_CONTACTS_FULL
          return const ContactsFullFrame();

        case 0x91: // PUSH_CODE_ONE_KEY_DM_REJECTED
          return OneKeyRejectedFrame(
            Uint8List.fromList(
                c.bytes(kPubKeySize, 'oneKeyRejected.pubKey')),
          );

        default:
          return UnsupportedFrame(op, Uint8List.fromList(frame));
    }
  }

  /// Read the path bytes a `path_len` byte announces. An invalid length
  /// (over `MAX_PATH_SIZE`) yields an empty path because that is exactly
  /// what the firmware writes (`Packet.cpp:24-27`); the caller can see it
  /// through [PathLen.isValid].
  static Uint8List _readPath(ByteCursor c, PathLen len, String ctx) {
    if (!len.isValid || len.byteLength == 0) return Uint8List(0);
    return Uint8List.fromList(c.bytes(len.byteLength, ctx));
  }

  static MeshcoreInbound _decodeStats(ByteCursor c, Uint8List frame) {
    final int sub = c.u8('stats.subType');
    final StatsFrame decoded;
    switch (sub) {
      case kStatsTypeCore:
        decoded = StatsFrame(
          core: CoreStats(
            batteryMilliVolts: c.u16('stats.core.batt'),
            uptimeSecs: c.u32('stats.core.uptime'),
            errFlags: c.u16('stats.core.errFlags'),
            queueLen: c.u8('stats.core.queue'),
          ),
        );
      case kStatsTypeRadio:
        decoded = StatsFrame(
          radio: RadioStats(
            noiseFloorDbm: c.i16('stats.radio.noise'),
            lastRssi: c.i8('stats.radio.rssi'),
            lastSnrDb: c.i8('stats.radio.snr') / 4.0,
            txAirSecs: c.u32('stats.radio.txAir'),
            rxAirSecs: c.u32('stats.radio.rxAir'),
          ),
        );
      case kStatsTypePackets:
        decoded = StatsFrame(
          packets: PacketStats(
            received: c.u32('stats.pkts.recv'),
            sent: c.u32('stats.pkts.sent'),
            sentFlood: c.u32('stats.pkts.sentFlood'),
            sentDirect: c.u32('stats.pkts.sentDirect'),
            receivedFlood: c.u32('stats.pkts.recvFlood'),
            receivedDirect: c.u32('stats.pkts.recvDirect'),
            receiveErrors:
                c.remaining >= 4 ? c.u32('stats.pkts.recvErrors') : null,
          ),
        );
      default:
        // A sub-type newer than us: keep the bytes, don't guess.
        return UnsupportedFrame(0x18, Uint8List.fromList(frame));
    }
    // These structs have grown in place before — the packet counters gained
    // `recvErrors` inside the same frame — so a tail this build does not
    // model is a field added to the struct, not a second frame. Consuming it
    // keeps one appended counter from costing the whole reading.
    c.skipRemaining('stats struct grows in place');
    return decoded;
  }

  /// The `RepeaterStats` struct. The first 24 bytes are required; each
  /// later field is read only when the firmware sent it.
  static RepeaterStatus? _decodeRepeaterStatus(ByteCursor c) {
    if (c.remaining < 24) return null;
    final int batt = c.u16('rs.batt');
    final int queue = c.u16('rs.queue');
    final int noise = c.i16('rs.noise');
    final int rssi = c.i16('rs.rssi');
    final int recv = c.u32('rs.recv');
    final int sent = c.u32('rs.sent');
    final int air = c.u32('rs.air');
    final int up = c.u32('rs.uptime');
    int? u32OrNull(String ctx) => c.remaining >= 4 ? c.u32(ctx) : null;
    int? u16OrNull(String ctx) => c.remaining >= 2 ? c.u16(ctx) : null;
    final int? sentFlood = u32OrNull('rs.sentFlood');
    final int? sentDirect = u32OrNull('rs.sentDirect');
    final int? recvFlood = u32OrNull('rs.recvFlood');
    final int? recvDirect = u32OrNull('rs.recvDirect');
    final int? errEvents = u16OrNull('rs.errEvents');
    final int? snr4 = c.remaining >= 2 ? c.i16('rs.snr') : null;
    final int? directDups = u16OrNull('rs.directDups');
    final int? floodDups = u16OrNull('rs.floodDups');
    final int? rxAir = u32OrNull('rs.rxAir');
    final int? recvErrors = u32OrNull('rs.recvErrors');
    return RepeaterStatus(
      batteryMilliVolts: batt,
      txQueueLen: queue,
      noiseFloorDbm: noise,
      lastRssi: rssi,
      packetsReceived: recv,
      packetsSent: sent,
      airTimeSecs: air,
      uptimeSecs: up,
      sentFlood: sentFlood,
      sentDirect: sentDirect,
      receivedFlood: recvFlood,
      receivedDirect: recvDirect,
      errEvents: errEvents,
      lastSnrDb: snr4 == null ? null : snr4 / 4.0,
      directDups: directDups,
      floodDups: floodDups,
      rxAirTimeSecs: rxAir,
      receiveErrors: recvErrors,
    );
  }

  /// `[reserved][path_len][flags][tag u32][auth u32][hashes path_len]
  /// [snr i8 × hops][final snr i8]`, hops = path_len >> (flags & 3).
  static TraceResult _decodeTrace(ByteCursor c) {
    c.u8('trace.reserved');
    final int pathLen = c.u8('trace.pathLen');
    final int flags = c.u8('trace.flags');
    final int tag = c.u32('trace.tag');
    final int auth = c.u32('trace.auth');
    final Uint8List hashes = c.bytes(pathLen, 'trace.hashes');
    final int hops = pathLen >> (flags & 0x03);
    final List<double> snrs = <double>[
      for (int i = 0; i < hops; i++) c.i8('trace.snr[$i]') / 4.0,
    ];
    final double last = c.i8('trace.finalSnr') / 4.0;
    return TraceResult(
      tag: tag,
      authCode: auth,
      flags: flags,
      pathHashes: hashes,
      hopSnrsDb: List<double>.unmodifiable(snrs),
      finalSnrDb: last,
    );
  }

  /// `[0x90 | node_type][their snr ×4][tag u32][pub_key 32 or 8]`, or
  /// null when [payload] is some other control packet.
  static DiscoverResponse? _decodeDiscover(
      Uint8List payload, double ourSnr, int ourRssi) {
    if (payload.length < 6 + 8 ||
        (payload[0] & 0xF0) != kCtlTypeNodeDiscoverResp) {
      return null;
    }
    final ByteCursor p = ByteCursor(payload);
    final int type = p.u8('discover.type') & 0x0F;
    final double theirs = p.i8('discover.snr') / 4.0;
    final int tag = p.u32('discover.tag');
    final int keyLen = p.remaining >= kPubKeySize ? kPubKeySize : 8;
    return DiscoverResponse(
      nodeType: type,
      tag: tag,
      publicKey: p.bytes(keyLen, 'discover.key'),
      theirSnrDb: theirs,
      ourSnrDb: ourSnr,
      ourRssi: ourRssi,
    );
  }

  /// `RESP_CODE_CUSTOM_VARS` payload: comma-separated `name:value`
  /// pairs (ASCII, no NUL — frame length is the terminator). Empty
  /// payload → empty map. Malformed entries (no `:` separator) are
  /// silently dropped to match the firmware's permissive parser.
  static Map<String, String> _decodeCustomVars(ByteCursor c) {
    if (c.atEnd) return const <String, String>{};
    final String payload = c.utf8ToEnd('customVars.payload');
    final Map<String, String> out = <String, String>{};
    for (final String entry in payload.split(',')) {
      final int sep = entry.indexOf(':');
      if (sep <= 0) continue;
      out[entry.substring(0, sep)] = entry.substring(sep + 1);
    }
    return out;
  }

  static SelfInfo _decodeSelfInfo(ByteCursor c) {
    final int advType = c.u8('selfInfo.advType');
    final int txPower = c.u8('selfInfo.txPower');
    final int maxTxPower = c.u8('selfInfo.maxTxPower');
    final Uint8List pubKey = c.bytes(kPubKeySize, 'selfInfo.pubKey');
    final double lat = c.i32('selfInfo.lat') / 1e6;
    final double lon = c.i32('selfInfo.lon') / 1e6;
    final int multiAcks = c.u8('selfInfo.multiAcks');
    final int locPolicy = c.u8('selfInfo.advertLocPolicy');
    final int telemetry = c.u8('selfInfo.telemetryMode');
    final bool manualAdd = c.u8('selfInfo.manualAddContacts') != 0;
    final double freq = c.u32('selfInfo.frequency') / 1000.0;
    final double bw = c.u32('selfInfo.bandwidth') / 1000.0;
    final int sf = c.u8('selfInfo.sf');
    final int cr = c.u8('selfInfo.cr');
    final String name = c.atEnd ? '' : c.utf8ToEnd('selfInfo.name');
    return SelfInfo(
      advType: advType,
      txPowerDbm: txPower,
      maxTxPowerDbm: maxTxPower,
      publicKey: pubKey,
      latitude: lat,
      longitude: lon,
      multiAcks: multiAcks,
      advertLocPolicy: locPolicy,
      telemetryModeRaw: telemetry,
      manualAddContacts: manualAdd,
      frequencyMhz: freq,
      bandwidthKhz: bw,
      spreadingFactor: sf,
      codingRate: cr,
      name: name,
    );
  }

  /// Decodes 0x08 (legacy) and 0x11 (V3) channel messages. The opcode
  /// byte has already been consumed.
  static ChannelMessage _decodeChannelMsg(ByteCursor c, {required bool v3}) {
    double? snr;
    if (v3) {
      snr = c.i8('channelMsg.snr') / 4.0;
      c.u8('channelMsg.reserved1');
      c.u8('channelMsg.reserved2');
    }
    final int channelIdx = c.u8('channelMsg.channelIdx');
    final int pathLen = c.u8('channelMsg.pathLen');
    final int txtType = c.u8('channelMsg.txtType');
    final int ts = c.u32('channelMsg.timestamp');
    final String text = c.atEnd ? '' : c.utf8ToEnd('channelMsg.text');
    return ChannelMessage(
      channelIdx: channelIdx,
      pathLen: pathLen,
      txtType: txtType,
      timestamp: ts,
      text: text,
      isV3: v3,
      snrDb: snr,
    );
  }

  /// Decodes 0x07 (legacy) and 0x10 (V3) contact messages. The opcode
  /// byte has already been consumed.
  static ContactMessage _decodeContactMsg(ByteCursor c, {required bool v3}) {
    double? snr;
    if (v3) {
      snr = c.i8('contactMsg.snr') / 4.0;
      c.u8('contactMsg.reserved1');
      c.u8('contactMsg.reserved2');
    }
    final Uint8List prefix = c.bytes(kPubKeyPrefixSize, 'contactMsg.prefix');
    final int pathLen = c.u8('contactMsg.pathLen');
    final int txtType = c.u8('contactMsg.txtType');
    final int ts = c.u32('contactMsg.timestamp');
    Uint8List? sig;
    if (txtType == kTxtTypeSignedPlain) {
      sig = c.bytes(kSignaturePrefixSize, 'contactMsg.sigPrefix');
    }
    final String text = c.atEnd ? '' : c.utf8ToEnd('contactMsg.text');
    return ContactMessage(
      pubKeyPrefix: prefix,
      pathLen: pathLen,
      txtType: txtType,
      timestamp: ts,
      text: text,
      isV3: v3,
      snrDb: snr,
      signaturePrefix: sig,
    );
  }

  /// Decodes `PUSH_CODE_ADVERTISEMENT` (0x80). The opcode byte has
  /// already been consumed by [c]; the remaining bytes are the advert
  /// payload, shared verbatim with the OTA `PAYLOAD_TYPE_ADVERT` body
  /// ([Advert.parse]).
  static Advert _decodeAdvert(ByteCursor c) {
    final Uint8List payload =
        c.atEnd ? Uint8List(0) : c.bytes(c.remaining, 'advert.payload');
    return Advert.parse(payload);
  }

  static Contact _decodeContact(ByteCursor c) {
    final Uint8List pubKey = c.bytes(kPubKeySize, 'contact.pubKey');
    final int type = c.u8('contact.type');
    final int flags = c.u8('contact.flags');
    final int pathLen = c.u8('contact.outPathLen');
    final Uint8List path = c.bytes(kMaxPathSize, 'contact.outPath');
    final String name = c.fixedCString(kContactNameSize, 'contact.name');
    final int advertTs = c.u32('contact.lastAdvertTimestamp');
    final int latMicros = c.i32('contact.lat');
    final int lonMicros = c.i32('contact.lon');
    final int lastMod = c.u32('contact.lastMod');
    return Contact(
      publicKey: pubKey,
      type: type,
      flags: flags,
      outPathLen: pathLen,
      outPath: path,
      name: name,
      lastAdvertTimestamp: advertTs,
      latitudeMicros: latMicros,
      longitudeMicros: lonMicros,
      lastMod: lastMod,
    );
  }
}
