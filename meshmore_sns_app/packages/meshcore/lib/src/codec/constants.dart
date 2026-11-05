// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
// Meshcore companion-radio protocol constants.
//
// SOURCE OF TRUTH — transcribed from the MeshCore firmware repository,
// pinned to:
//
//   tag    : companion-v1.15.0
//   commit : dee3e26ac081a5c668c69b66c16a6544a44ddc5b
//   file   : docs/companion_protocol.md
//   url    : https://github.com/meshcore-dev/MeshCore/blob/
//            dee3e26ac081a5c668c69b66c16a6544a44ddc5b/docs/companion_protocol.md
//
// This M0 file seeds the framing parameters, BLE UUIDs, and the core
// opcode set. The remaining opcodes/field layouts are transcribed
// per-milestone (M1–M4) against this SAME pinned commit. When the pin is
// bumped, update the header above and re-verify every value below.
//
// DO NOT change a numeric value here without re-reading the pinned doc.

/// Pinned firmware reference. Bump deliberately, never silently.
const String kMeshcoreFirmwarePinTag = 'companion-v1.15.0';
const String kMeshcoreFirmwarePinCommit =
    'dee3e26ac081a5c668c69b66c16a6544a44ddc5b';

/// The protocol version this client announces in `CMD_DEVICE_QUERY`.
///
/// The firmware stores the byte verbatim (`MyMesh.cpp:1029-1032`) and
/// branches on it in exactly two places, both `>= 3`: the contact and
/// channel receive frames that carry per-message SNR (V3, codes 0x10 and
/// 0x11, `MyMesh.cpp:435-443` and `:548-556`). Nothing else reads it, so
/// asking for 3 is safe on firmware that predates those frames — the
/// byte is stored and never consulted. Asking for 1 (the previous
/// default) made every modern companion answer with the legacy frames and
/// silently dropped SNR on every message.
const int kAppTargetProtocolVersion = 3;

/// BLE transport (Nordic-UART-style service used by the companion link).
///
/// Framing rule: each characteristic write / notification is exactly ONE
/// protocol frame. There is no length prefix; frame boundaries are the
/// BLE MTU boundaries. Multi-byte integers are little-endian; strings are
/// UTF-8. (CayenneLPP payloads, where present, are big-endian.)
abstract final class MeshcoreBle {
  static const String serviceUuid =
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// App → Device (the app WRITEs command frames here).
  static const String rxCharacteristicUuid =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Device → App (the app SUBSCRIBES for response/push notifications).
  static const String txCharacteristicUuid =
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
}

/// Common protocol field sizes (from firmware, pinned commit).
///
/// `PUB_KEY_SIZE`, `MAX_PATH_SIZE`, and the 32-byte contact name field
/// are read from `examples/companion_radio/MyMesh.cpp` and
/// `src/MeshCore.h` at the pinned commit.
const int kPubKeySize = 32; // PUB_KEY_SIZE
const int kPrivKeySize = 64; // PRV_KEY_SIZE
const int kSignatureSize = 64; // SIGNATURE_SIZE
const int kMaxPathSize = 64; // MAX_PATH_SIZE
const int kContactNameSize = 32;

/// Which radio profile a received packet arrived on.
///
/// The receive frames carry a byte that the mainline firmware leaves
/// reserved (writes 0) and that a two-profile radio fills in: `0xA0` the
/// primary radio, `0xA1` the second one, the frame's own "none" value
/// otherwise (0 for a channel datagram, 0xFF for raw data). The value is
/// only meaningful when a second profile is on; everything else reports
/// [unknown], which is also what the mainline firmware always sends.
enum RxVia {
  /// Not reported: single-profile radio, mainline firmware, or a packet
  /// that arrived over a non-radio ingress (e.g. a bridge).
  unknown,

  /// The primary radio profile.
  primary,

  /// The second radio profile.
  secondary;

  /// Maps the wire byte to a profile. Any value outside the two tags the
  /// firmware writes is [unknown], including the frame's "none" sentinel.
  static RxVia fromWireByte(int byte) => switch (byte) {
        kRxViaPrimaryTag => RxVia.primary,
        kRxViaSecondaryTag => RxVia.secondary,
        _ => RxVia.unknown,
      };
}

/// Wire tags for [RxVia], as written by a two-profile radio.
const int kRxViaPrimaryTag = 0xA0;
const int kRxViaSecondaryTag = 0xA1;

/// Channel + cipher sizes (from `src/MeshCore.h` / `src/Mesh.h`).
///
/// `mesh::GroupChannel { uint8_t hash[PATH_HASH_SIZE];
///   uint8_t secret[PUB_KEY_SIZE]; }` — so the channel secret BUFFER is
/// [kPubKeySize] (32) bytes. The AES-128 key is the first
/// [kCipherKeySize] (16) bytes; the HMAC is keyed over all 32. The
/// companion protocol (SET_CHANNEL / CHANNEL_INFO) only conveys the
/// first [kChannelPskSize] (16) bytes — the upper 16 bytes of a
/// channel's HMAC key are NOT carried on the companion link and must be
/// confirmed against a real device (M6 interop fixture).
const int kCipherKeySize = 16; // CIPHER_KEY_SIZE  (AES-128)
const int kCipherBlockSize = 16; // CIPHER_BLOCK_SIZE
const int kCipherMacSize = 2; // CIPHER_MAC_SIZE  (truncated HMAC)
const int kChannelSecretSize = kPubKeySize; // GroupChannel.secret = 32
/// Bytes carried by `SET_CHANNEL` and by the ordinary `CHANNEL_INFO`
/// reply (`MyMesh.cpp:1715-1721`).
const int kChannelPskSize = 16;

/// The same field's other width: a `CHANNEL_INFO` reply carries the full
/// 32-byte secret when the request asked for it with a third byte of 32
/// (`1F <index> 20`) — the reply length is the only signal, so a decoder
/// must accept both widths and read the rest of the frame.
const int kChannelPskSizeFull = kChannelSecretSize;
const int kChannelNameSize = 32;

/// Channel/contact text `txt_type` values (companion protocol).
const int kTxtTypePlain = 0;

/// `TXT_TYPE_SIGNED_PLAIN` — contact message carries a 4-byte signature
/// prefix before the text.
const int kTxtTypeSignedPlain = 2;

/// `path_len` sentinel meaning the message arrived via flood routing.
const int kPathLenFlood = 0xFF;

/// Contacts are referenced in messages by a 6-byte public-key prefix
/// (`memcpy(&out_frame[i], from.id.pub_key, 6)`).
const int kPubKeyPrefixSize = 6;

/// Signature prefix carried by signed contact messages (txt_type == 2).
const int kSignaturePrefixSize = 4;

/// `CMD_SET_ADVERT_NAME` max name length.
const int kMaxAdvertName = 31;

/// `RESP_CODE_DEVICE_INFO` (0x0D) fixed string-field sizes.
const int kDeviceBuildDateSize = 12;
const int kDeviceManufacturerSize = 40;
const int kDeviceFirmwareVersionSize = 20;

/// Radio/tuning scale factor: on-wire uint32 = value × 1000.
const int kRadioScale = 1000;

/// --- Advert (`AdvertDataHelpers.h`, pinned commit). ---
/// Advert node types (low nibble of the app_data flags byte).
const int kAdvTypeNone = 0;
const int kAdvTypeChat = 1;
const int kAdvTypeRepeater = 2;
const int kAdvTypeRoom = 3;
const int kAdvTypeSensor = 4;
const int kAdvTypeMask = 0x0F;

/// Advert app_data optional-field flag masks.
const int kAdvLatLonMask = 0x10;
const int kAdvFeat1Mask = 0x20;
const int kAdvFeat2Mask = 0x40;
const int kAdvNameMask = 0x80;

/// Advert packet envelope sizes (`src/Mesh.cpp`):
/// `pub_key(32) ‖ timestamp(4 LE) ‖ signature(64) ‖ app_data`.
/// The Ed25519-signed message is `pub_key ‖ timestamp ‖ app_data`.
const int kAdvertHeaderSize = kPubKeySize + 4 + kSignatureSize; // 100

/// --- Over-the-air packet format (`docs/packet_format.md`, pinned). ---
/// Header byte 0: bits0-1 route type, bits2-5 payload type, bits6-7 ver.
const int kPktRouteTypeMask = 0x03;
const int kPktPayloadTypeMask = 0x3C; // >> 2
const int kPktPayloadTypeShift = 2;
const int kPktVersionMask = 0xC0; // >> 6

const int kRouteTransportFlood = 0x00;
const int kRouteFlood = 0x01;
const int kRouteDirect = 0x02;
const int kRouteTransportDirect = 0x03;

/// Transport codes (4 bytes) precede the path for the TRANSPORT_* routes.
const int kTransportCodesSize = 4;

const int kPayloadTypeReq = 0x00;
const int kPayloadTypeResponse = 0x01;
const int kPayloadTypeTxtMsg = 0x02;
const int kPayloadTypeAck = 0x03;
const int kPayloadTypeAdvert = 0x04;
const int kPayloadTypeGrpTxt = 0x05;
const int kPayloadTypeGrpData = 0x06;
const int kPayloadTypeAnonReq = 0x07;
const int kPayloadTypePath = 0x08;
const int kPayloadTypeTrace = 0x09;

/// Path-length byte: bits0-5 hop count, bits6-7 hash-size code.
const int kPathHopMask = 0x3F;
const int kPathHashSizeShift = 6;

/// --- Well-known PUBLIC channel (`docs/qr_codes.md`, pinned commit). ---
/// `meshcore://channel/add?name=Public&secret=8b3387e9c5cdea6ac9e5edbaa115cd72`
/// The shared secret is 16 bytes throughout the ecosystem; the firmware
/// `GroupChannel.secret` tail (bytes 16..32) is not carried — see
/// [kChannelSecretSize].
const String kPublicChannelName = 'Public';
const List<int> kPublicChannelPsk = <int>[
  0x8b, 0x33, 0x87, 0xe9, 0xc5, 0xcd, 0xea, 0x6a, //
  0xc9, 0xe5, 0xed, 0xba, 0xa1, 0x15, 0xcd, 0x72,
];

/// Command opcodes (App → Device). First byte of an outbound frame.
///
/// Values are cross-checked against `examples/companion_radio/MyMesh.cpp`
/// at the pinned commit (the markdown doc omits several commands).
/// Additional commands (text message, self-advert, radio params, …) are
/// added in their milestones from the same pinned source.
extension type const MeshcoreCommand(int code) {
  /// Must be the first frame after connect. `CMD_APP_START`.
  static const MeshcoreCommand appStart = MeshcoreCommand(0x01);

  /// `CMD_SEND_TXT_MSG` — direct/contact text message.
  static const MeshcoreCommand sendTextMessage = MeshcoreCommand(0x02);

  static const MeshcoreCommand sendChannelMessage = MeshcoreCommand(0x03);

  /// `CMD_GET_CONTACTS` — source-only (not in companion_protocol.md).
  static const MeshcoreCommand getContacts = MeshcoreCommand(0x04);

  /// `CMD_SEND_SELF_ADVERT` — emit our advert (flood or zero-hop).
  static const MeshcoreCommand sendSelfAdvert = MeshcoreCommand(0x07);

  /// `CMD_SET_ADVERT_NAME` — set our advertised node name.
  static const MeshcoreCommand setAdvertName = MeshcoreCommand(0x08);

  /// `CMD_ADD_UPDATE_CONTACT` — add/replace a contact (148-byte body).
  static const MeshcoreCommand addUpdateContact = MeshcoreCommand(0x09);

  /// `CMD_REMOVE_CONTACT` — remove a contact by public key (frees a slot
  /// in the radio's contact table).
  static const MeshcoreCommand removeContact = MeshcoreCommand(0x0F);

  /// `CMD_GET_DEVICE_TIME` — source-only.
  static const MeshcoreCommand getDeviceTime = MeshcoreCommand(0x05);

  /// `CMD_SET_DEVICE_TIME` — source-only.
  static const MeshcoreCommand setDeviceTime = MeshcoreCommand(0x06);

  /// `CMD_SYNC_NEXT_MESSAGE` — pull the next queued inbound message.
  static const MeshcoreCommand syncNextMessage = MeshcoreCommand(0x0A);

  /// --- Device / radio configuration (R7), `MyMesh.cpp` pinned. ---
  /// `CMD_SET_RADIO_PARAMS` — freq/bw/SF/CR.
  static const MeshcoreCommand setRadioParams = MeshcoreCommand(0x0B);

  /// `CMD_SET_RADIO_TX_POWER` — TX power (int8 dBm).
  static const MeshcoreCommand setRadioTxPower = MeshcoreCommand(0x0C);

  /// `CMD_SET_ADVERT_LATLON` — advertised location.
  static const MeshcoreCommand setAdvertLatLon = MeshcoreCommand(0x0E);

  static const MeshcoreCommand getBatteryStorage = MeshcoreCommand(0x14);

  /// `CMD_SET_TUNING_PARAMS` — rx-delay base / airtime factor.
  static const MeshcoreCommand setTuningParams = MeshcoreCommand(0x15);

  static const MeshcoreCommand deviceQuery = MeshcoreCommand(0x16);
  static const MeshcoreCommand getChannel = MeshcoreCommand(0x1F);
  static const MeshcoreCommand setChannel = MeshcoreCommand(0x20);

  /// `CMD_SET_OTHER_PARAMS` — manual-add / telemetry / loc policy.
  static const MeshcoreCommand setOtherParams = MeshcoreCommand(0x26);

  // --- Network shaping. These are MeshCore's *own* mechanisms for making a
  // network separate from the public mesh; none of them is a custom layer.
  // All five exist at the pinned commit AND on 1.17.1 (the only commands
  // added between them were CMD_DEVICE_QUERY and CMD_SEND_RAW_PACKET), so
  // using them does not require a pin bump.

  /// `CMD_SET_FLOOD_SCOPE_KEY` (54) — override the flood transport key, or
  /// switch floods to unscoped (`[54][1]`, firmware ver 12+).
  static const MeshcoreCommand setFloodScopeKey = MeshcoreCommand(0x36);

  /// `CMD_GET_ALLOWED_REPEAT_FREQ` (60) — the frequencies this *companion*
  /// build may repeat on. Not the same thing as what a `simple_repeater`
  /// build may relay (that has no frequency gate at all).
  static const MeshcoreCommand getAllowedRepeatFreq = MeshcoreCommand(0x3C);

  /// `CMD_SET_PATH_HASH_MODE` (61) — `[61][0][mode]`, mode 0..2 meaning
  /// 1/2/3-byte path hashes. Every node on a network must agree, and it
  /// changes the raw-data payload budget (`174 − hops × size`).
  static const MeshcoreCommand setPathHashMode = MeshcoreCommand(0x3D);

  /// `CMD_SET_DEFAULT_FLOOD_SCOPE` (63) — empty frame clears it, otherwise
  /// `[63][name 31][key 16]`.
  static const MeshcoreCommand setDefaultFloodScope = MeshcoreCommand(0x3F);

  /// `CMD_GET_DEFAULT_FLOOD_SCOPE` (64) — reply is
  /// `RESP_CODE_DEFAULT_FLOOD_SCOPE` + 31-byte name + 16-byte key, or that
  /// code alone when unset.
  static const MeshcoreCommand getDefaultFloodScope = MeshcoreCommand(0x40);

  /// `CMD_SEND_TELEMETRY_REQ` (39 = 0x27). Frame is either
  /// `27 [0 0 0]` (self-telemetry, len == 4) or
  /// `27 [0 0 0] [pub_key 32B]` (peer-telemetry, len == 36).
  /// The 3 bytes after the opcode are reserved/padding in firmware
  /// `companion-v1.15.0` and may carry a permission mask in newer
  /// builds — sending zeros is safe today.
  /// Response is async via [MeshcoreResponse.telemetryResponse] (0x8B).
  static const MeshcoreCommand sendTelemetryReq = MeshcoreCommand(0x27);

  /// `CMD_GET_CUSTOM_VARS` — request the device's custom string-keyed
  /// settings map. Reply is `RESP_CODE_CUSTOM_VARS` (0x15) carrying a
  /// comma-separated `name:value,name:value,...` payload. Used to read
  /// `gps`, `gps_interval`, etc.
  static const MeshcoreCommand getCustomVars = MeshcoreCommand(0x28);

  /// `CMD_SET_CUSTOM_VAR` — write a single string-keyed setting.
  /// Body: `[name]:[value]` (ASCII, no NUL — frame length defines end).
  /// Reply: OK on success, ERR on bad arg.
  static const MeshcoreCommand setCustomVar = MeshcoreCommand(0x29);

  static const MeshcoreCommand sendChannelDatagram = MeshcoreCommand(0x3E);

  /// --- Binary / raw carriage: opaque records over the companion link.
  /// Transcribed from `examples/companion_radio/MyMesh.cpp` at the same
  /// pinned commit; layouts in `mesh_carry.dart`. ---

  /// `CMD_SEND_BINARY_REQ` (50 = 0x32): `32 [pub_key 32] [app data]`.
  /// The radio looks the peer up as a contact, encrypts the app data,
  /// and replies `RESP_CODE_SENT` (0x06) with a firmware-chosen tag and
  /// an estimated timeout, or `RESP_CODE_ERR` (0x01). The response
  /// arrives later as `PUSH_CODE_BINARY_RESPONSE` (0x8C).
  static const MeshcoreCommand sendBinaryReq = MeshcoreCommand(0x32);

  /// `CMD_SEND_RAW_DATA` (25 = 0x19): `19 [path_len] [path] [payload]`.
  /// Direct-route only: the firmware rejects a negative `path_len` with
  /// `ERR_CODE_UNSUPPORTED_CMD` and the comment "flood, not supported
  /// (yet)". No cipher and no padding are applied.
  static const MeshcoreCommand sendRawData = MeshcoreCommand(0x19);

  /// `CMD_SEND_RAW_PACKET` (65 = 0x41): `41 [priority] [packet]`.
  /// The whole serialised MeshCore packet is supplied by the caller, so
  /// no cipher and no padding are applied. Repeaters still will not
  /// forward a `PAYLOAD_TYPE_RAW_CUSTOM` flood.
  static const MeshcoreCommand sendRawPacket = MeshcoreCommand(0x41);

  /// --- R60 Tools. From `MyMesh.cpp` on meshcore-dev/MeshCore main
  /// (checked 2026-10-14), newer than the pin above; older firmware
  /// answers ERR_CODE_UNSUPPORTED_CMD. ---

  /// `CMD_RESET_PATH` (13): `0D [pub_key 32]` — forget the contact's
  /// route; the next send floods.
  static const MeshcoreCommand resetPath = MeshcoreCommand(0x0D);

  /// `CMD_SEND_STATUS_REQ` (27): `1B [pub_key 32]` → SENT, then
  /// `PUSH_CODE_STATUS_RESPONSE` (0x87).
  static const MeshcoreCommand sendStatusReq = MeshcoreCommand(0x1B);

  /// `CMD_SEND_TRACE_PATH` (36) → SENT (tag echoed), then
  /// `PUSH_CODE_TRACE_DATA` (0x89).
  static const MeshcoreCommand sendTracePath = MeshcoreCommand(0x24);

  /// `CMD_SEND_CONTROL_DATA` (55): the payload is the control packet
  /// itself, sent zero-hop. Replies OK.
  static const MeshcoreCommand sendControlData = MeshcoreCommand(0x37);

  /// `CMD_GET_STATS` (56): `38 [sub_type]` → `RESP_CODE_STATS` (0x18).
  static const MeshcoreCommand getStats = MeshcoreCommand(0x38);

  // --- Contact lifecycle, identity, admin. Firmware companion-v1.17.1
  // (d929643) `examples/companion_radio/MyMesh.cpp`; every opcode below
  // is also present at the pin with the same number. ---

  /// `CMD_SHARE_CONTACT` (16): `10 [pub_key 32]` → OK / ERR(not_found,
  /// table_full). Re-broadcasts the stored advert zero-hop. `MyMesh.cpp:1319`.
  static const MeshcoreCommand shareContact = MeshcoreCommand(0x10);

  /// `CMD_EXPORT_CONTACT` (17): `11` (self) or `11 [pub_key 32]` →
  /// `RESP_CODE_EXPORT_CONTACT` (0x0B). `MyMesh.cpp:1339`.
  static const MeshcoreCommand exportContact = MeshcoreCommand(0x11);

  /// `CMD_IMPORT_CONTACT` (18): `12 [advert packet]` → OK / ERR(illegal_arg).
  /// `MyMesh.cpp:1369`.
  static const MeshcoreCommand importContact = MeshcoreCommand(0x12);

  /// `CMD_REBOOT` (19): `13 "reboot"`. No reply: the device resets.
  /// `MyMesh.cpp:1474`.
  static const MeshcoreCommand reboot = MeshcoreCommand(0x13);

  /// `CMD_EXPORT_PRIVATE_KEY` (23): `17` → `RESP_CODE_PRIVATE_KEY` (0x0E)
  /// or `RESP_CODE_DISABLED` (0x0F). `MyMesh.cpp:1490`.
  static const MeshcoreCommand exportPrivateKey = MeshcoreCommand(0x17);

  /// `CMD_IMPORT_PRIVATE_KEY` (24): `18 [key 64]` → OK / ERR / DISABLED.
  /// Replaces the node's identity. `MyMesh.cpp:1499`.
  static const MeshcoreCommand importPrivateKey = MeshcoreCommand(0x18);

  /// `CMD_SEND_LOGIN` (26): `1A [pub_key 32] [password]` → SENT, then
  /// `PUSH_CODE_LOGIN_SUCCESS` (0x85) / `PUSH_CODE_LOGIN_FAIL` (0x86).
  /// `MyMesh.cpp:1535`.
  static const MeshcoreCommand sendLogin = MeshcoreCommand(0x1A);

  /// `CMD_HAS_CONNECTION` (28): `1C [pub_key 32]` → OK / ERR(not_found).
  /// `MyMesh.cpp:1699`.
  static const MeshcoreCommand hasConnection = MeshcoreCommand(0x1C);

  /// `CMD_LOGOUT` (29): `1D [pub_key 32]` → OK (always). `MyMesh.cpp:1706`.
  static const MeshcoreCommand logout = MeshcoreCommand(0x1D);

  /// `CMD_GET_CONTACT_BY_KEY` (30): `1E [pub_key 32]` → `RESP_CODE_CONTACT`
  /// (0x03) / ERR(not_found). `MyMesh.cpp:1331`.
  static const MeshcoreCommand getContactByKey = MeshcoreCommand(0x1E);

  /// `CMD_SIGN_START` (33): `21` → `RESP_CODE_SIGN_START` (0x13).
  /// `MyMesh.cpp:1739`.
  static const MeshcoreCommand signStart = MeshcoreCommand(0x21);

  /// `CMD_SIGN_DATA` (34): `22 [chunk 1..175]` → OK / ERR(bad_state,
  /// table_full). `MyMesh.cpp:1751`.
  static const MeshcoreCommand signData = MeshcoreCommand(0x22);

  /// `CMD_SIGN_FINISH` (35): `23` → `RESP_CODE_SIGNATURE` (0x14) /
  /// ERR(bad_state). `MyMesh.cpp:1759`.
  static const MeshcoreCommand signFinish = MeshcoreCommand(0x23);

  /// `CMD_SET_DEVICE_PIN` (37): `25 [pin u32 LE]` → OK / ERR(illegal_arg).
  /// `MyMesh.cpp:1797`.
  static const MeshcoreCommand setDevicePin = MeshcoreCommand(0x25);

  /// `CMD_GET_ADVERT_PATH` (42): `2A 00 [pub_key 32]` →
  /// `RESP_CODE_ADVERT_PATH` (0x16) / ERR(not_found). `MyMesh.cpp:1851`.
  static const MeshcoreCommand getAdvertPath = MeshcoreCommand(0x2A);

  /// `CMD_GET_TUNING_PARAMS` (43): `2B` → `RESP_CODE_TUNING_PARAMS` (0x17).
  /// `MyMesh.cpp:1443`.
  static const MeshcoreCommand getTuningParams = MeshcoreCommand(0x2B);

  /// `CMD_FACTORY_RESET` (51): `33 "reset"` → OK then reboot after 1 s.
  /// Formats the filesystem. `MyMesh.cpp:1923`.
  static const MeshcoreCommand factoryReset = MeshcoreCommand(0x33);

  /// `CMD_SEND_PATH_DISCOVERY_REQ` (52): `34 00 [pub_key 32]` → SENT, then
  /// `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D). `MyMesh.cpp:1609`.
  static const MeshcoreCommand sendPathDiscoveryReq = MeshcoreCommand(0x34);

  /// `CMD_SEND_ANON_REQ` (57): `39 [pub_key 32] [data 1..132]` → SENT, then
  /// `PUSH_CODE_BINARY_RESPONSE` (0x8C). `MyMesh.cpp:1557`.
  static const MeshcoreCommand sendAnonReq = MeshcoreCommand(0x39);

  /// `CMD_SET_AUTOADD_CONFIG` (58): `3A [flags] [max_hops]?` → OK.
  /// `MyMesh.cpp:1981`.
  static const MeshcoreCommand setAutoAddConfig = MeshcoreCommand(0x3A);

  /// `CMD_GET_AUTOADD_CONFIG` (59): `3B` → `RESP_CODE_AUTOADD_CONFIG`
  /// (0x19). `MyMesh.cpp:1988`.
  static const MeshcoreCommand getAutoAddConfig = MeshcoreCommand(0x3B);
}

/// Response / push opcodes (Device → App). First byte of an inbound frame.
///
/// Opcodes >= 0x80 are asynchronous push notifications (not direct
/// replies to a command).
extension type const MeshcoreResponse(int code) {
  static const MeshcoreResponse ok = MeshcoreResponse(0x00);
  static const MeshcoreResponse error = MeshcoreResponse(0x01);
  static const MeshcoreResponse contactStart = MeshcoreResponse(0x02);
  static const MeshcoreResponse contact = MeshcoreResponse(0x03);
  static const MeshcoreResponse contactEnd = MeshcoreResponse(0x04);
  static const MeshcoreResponse selfInfo = MeshcoreResponse(0x05);
  static const MeshcoreResponse msgSent = MeshcoreResponse(0x06);
  static const MeshcoreResponse contactMsgRecv = MeshcoreResponse(0x07);
  static const MeshcoreResponse channelMsgRecv = MeshcoreResponse(0x08);
  static const MeshcoreResponse currentTime = MeshcoreResponse(0x09);
  static const MeshcoreResponse noMoreMsgs = MeshcoreResponse(0x0A);
  static const MeshcoreResponse battery = MeshcoreResponse(0x0C);
  static const MeshcoreResponse deviceInfo = MeshcoreResponse(0x0D);
  static const MeshcoreResponse contactMsgRecvV3 = MeshcoreResponse(0x10);
  static const MeshcoreResponse channelMsgRecvV3 = MeshcoreResponse(0x11);
  static const MeshcoreResponse channelInfo = MeshcoreResponse(0x12);

  /// `RESP_CODE_CUSTOM_VARS` (21 = 0x15) — reply to CMD_GET_CUSTOM_VARS.
  /// Payload: comma-separated `name:value` pairs (ASCII, no NUL).
  static const MeshcoreResponse customVars = MeshcoreResponse(0x15);

  /// `RESP_CODE_STATS` (24 = 0x18) — reply to CMD_GET_STATS.
  static const MeshcoreResponse stats = MeshcoreResponse(0x18);

  /// `RESP_ALLOWED_REPEAT_FREQ` (26) — one or more (lower u32, upper u32)
  /// frequency ranges, in kHz.
  static const MeshcoreResponse allowedRepeatFreq = MeshcoreResponse(0x1A);

  /// `RESP_CODE_DEFAULT_FLOOD_SCOPE` (28).
  static const MeshcoreResponse defaultFloodScope = MeshcoreResponse(0x1C);

  /// `RESP_CODE_EXPORT_CONTACT` (11) — `[0B][raw advert packet]`.
  /// `MyMesh.cpp:82`, written at `:1351` and `:1363`.
  static const MeshcoreResponse exportContact = MeshcoreResponse(0x0B);

  /// `RESP_CODE_PRIVATE_KEY` (14) — `[0E][key 64]`. `MyMesh.cpp:85,1492`.
  static const MeshcoreResponse privateKey = MeshcoreResponse(0x0E);

  /// `RESP_CODE_DISABLED` (15) — the command is compiled out
  /// (`ENABLE_PRIVATE_KEY_EXPORT/IMPORT`). `MyMesh.cpp:86,160-163`.
  static const MeshcoreResponse disabled = MeshcoreResponse(0x0F);

  /// `RESP_CODE_SIGN_START` (19) — `[13][0][max_len u32]`. `MyMesh.cpp:1740`.
  static const MeshcoreResponse signStart = MeshcoreResponse(0x13);

  /// `RESP_CODE_SIGNATURE` (20) — `[14][signature 64]`. `MyMesh.cpp:1766`.
  static const MeshcoreResponse signature = MeshcoreResponse(0x14);

  /// `RESP_CODE_ADVERT_PATH` (22) — `[16][ts u32][path_len][path]`.
  /// `MyMesh.cpp:1864`.
  static const MeshcoreResponse advertPath = MeshcoreResponse(0x16);

  /// `RESP_CODE_TUNING_PARAMS` (23) — `[17][rx u32][af u32]`.
  /// `MyMesh.cpp:1446`.
  static const MeshcoreResponse tuningParams = MeshcoreResponse(0x17);

  /// `RESP_CODE_AUTOADD_CONFIG` (25) — `[19][flags][max_hops]`.
  /// `MyMesh.cpp:1990`.
  static const MeshcoreResponse autoAddConfig = MeshcoreResponse(0x19);

  /// --- Asynchronous push codes (>= 0x80) ---
  static const MeshcoreResponse advertisement = MeshcoreResponse(0x80);
  static const MeshcoreResponse ack = MeshcoreResponse(0x82);
  static const MeshcoreResponse messagesWaiting = MeshcoreResponse(0x83);

  /// `PUSH_CODE_LOGIN_SUCCESS` (0x85). `MyMesh.cpp:686,695`.
  static const MeshcoreResponse loginSuccess = MeshcoreResponse(0x85);

  /// `PUSH_CODE_LOGIN_FAIL` (0x86). `MyMesh.cpp:704`.
  static const MeshcoreResponse loginFail = MeshcoreResponse(0x86);

  /// `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D). `MyMesh.cpp:762`.
  static const MeshcoreResponse pathDiscoveryResponse =
      MeshcoreResponse(0x8D);

  /// `PUSH_CODE_CONTACT_DELETED` (0x8F) — `[8F][pub_key 32]`, sent when a
  /// contact is overwritten. `MyMesh.cpp:340`.
  static const MeshcoreResponse contactDeleted = MeshcoreResponse(0x8F);

  /// `PUSH_CODE_CONTACTS_FULL` (0x90) — bare code. `MyMesh.cpp:348`.
  static const MeshcoreResponse contactsFull = MeshcoreResponse(0x90);

  /// `PUSH_CODE_PATH_UPDATED` (0x81) — `[81][pub_key 32]`. Carries ONLY the
  /// key: the app must re-read the contact to learn the new path
  /// (`MyMesh.cpp:404-410`). Not queued; lost if no app is connected.
  static const MeshcoreResponse pathUpdated = MeshcoreResponse(0x81);

  /// `PUSH_CODE_RAW_DATA` (0x84) — `[84][snr*4 i8][rssi i8][0xFF][payload]`.
  /// Pushed only while an app is connected and NEVER queued
  /// (`MyMesh.cpp:811-816`). Carries no sender identity.
  static const MeshcoreResponse rawData = MeshcoreResponse(0x84);

  /// `PUSH_CODE_NEW_ADVERT` (0x8A) — a full contact frame for a node heard
  /// for the first time (`MyMesh.cpp:356`).
  static const MeshcoreResponse newAdvert = MeshcoreResponse(0x8A);

  /// `RESP_CODE_CHANNEL_DATA_RECV` (0x1B) — queued channel data message
  /// (`MyMesh.cpp:601`).
  static const MeshcoreResponse channelDataRecv = MeshcoreResponse(0x1B);

  /// RF log data — safely ignorable by the codec.
  static const MeshcoreResponse logData = MeshcoreResponse(0x88);

  /// `PUSH_CODE_TELEMETRY_RESPONSE` (0x8B). Async push delivering a
  /// telemetry payload either for self (immediate after a
  /// `CMD_SEND_TELEMETRY_REQ` with len==4) or for a peer (arrives
  /// some seconds later after the OTA round-trip).
  /// Wire format: `[0x8B][reserved 1B = 0][pubkey_prefix 6B][CayenneLPP payload]`.
  static const MeshcoreResponse telemetryResponse =
      MeshcoreResponse(0x8B);

  /// `PUSH_CODE_STATUS_RESPONSE` (0x87) — a repeater's status reply.
  static const MeshcoreResponse statusResponse = MeshcoreResponse(0x87);

  /// `PUSH_CODE_TRACE_DATA` (0x89) — a TRACE reached the end of its path.
  static const MeshcoreResponse traceData = MeshcoreResponse(0x89);

  /// `PUSH_CODE_CONTROL_DATA` (0x8E) — a control packet (e.g. a
  /// discover response) was heard.
  static const MeshcoreResponse controlData = MeshcoreResponse(0x8E);

  /// `PUSH_CODE_BINARY_RESPONSE` (0x8C). Async push delivering a peer's
  /// reply to a `CMD_SEND_BINARY_REQ`. Wire format:
  /// `[0x8C][reserved 1B = 0][tag 4B LE][payload]`.
  ///
  /// The tag echoes the one `RESP_CODE_SENT` reported. Note what the
  /// frame does _not_ carry: any sender public key. Responder identity is
  /// only provable by an end-to-end layer above this one.
  static const MeshcoreResponse binaryResponse = MeshcoreResponse(0x8C);

  /// `RESP_CODE_CLI_REPLY` (0x1D) — one line of a command's output, sent
  /// as its own frame and terminated by an `OK`. Numbered with the
  /// replies, not the pushes, because it only ever follows
  /// `CMD_RUN_CLI_COMMAND`; a CLI command can produce several of them.
  static const MeshcoreResponse cliReply = MeshcoreResponse(0x1D);

  /// True for an asynchronous push the radio may emit at any time.
  ///
  /// This is the firmware's own split, not a guess: every `PUSH_CODE_*`
  /// sits at `0x80` and above under the block comment "these are _pushed_
  /// to client app at any time" (`MyMesh.cpp:111-128`), and every
  /// `RESP_CODE_*` below it, including the two that arrive without the app
  /// asking for them in the same breath — `CHANNEL_DATA_RECV` (0x1B, a
  /// queued item drained by `CMD_SYNC_NEXT_MESSAGE`) and `CLI_REPLY`
  /// (0x1D, the output stream of `CMD_RUN_CLI_COMMAND`) — because both are
  /// answers to a command the app sent. `constants_test.dart` pins every
  /// code in both trees so a new one cannot land on the wrong side.
  bool get isPush => code >= 0x80;
}

/// `RESP_CODE_ERR` (0x01) error codes. Second byte of a 2-byte frame
/// `[0x01][code]` (firmware: `MyMesh::writeErrFrame`).
extension type const MeshcoreErrorCode(int code) {
  static const MeshcoreErrorCode unsupportedCmd = MeshcoreErrorCode(1);
  static const MeshcoreErrorCode notFound = MeshcoreErrorCode(2);
  static const MeshcoreErrorCode tableFull = MeshcoreErrorCode(3);
  static const MeshcoreErrorCode badState = MeshcoreErrorCode(4);
  static const MeshcoreErrorCode fileIoError = MeshcoreErrorCode(5);
  static const MeshcoreErrorCode illegalArg = MeshcoreErrorCode(6);

  /// A short stable name for diagnostics and test vectors.
  String get name => switch (code) {
        1 => 'unsupported_cmd',
        2 => 'not_found',
        3 => 'table_full',
        4 => 'bad_state',
        5 => 'file_io_error',
        6 => 'illegal_arg',
        _ => 'unknown_$code',
      };
}

/// `CMD_GET_STATS` sub-types.
const int kStatsTypeCore = 0;
const int kStatsTypeRadio = 1;
const int kStatsTypePackets = 2;

/// Control-packet types (upper nibble of the first payload byte).
const int kCtlTypeNodeDiscoverReq = 0x80;
const int kCtlTypeNodeDiscoverResp = 0x90;

/// `ERR_CODE_*` values carried by RESP_CODE_ERR.
const int kErrUnsupportedCmd = 1;
const int kErrNotFound = 2;
const int kErrTableFull = 3;
const int kErrIllegalArg = 6;

/// SNR byte → dB conversion used by the V3 receive frames.
///
/// `snrDb = (signed8(value)) / 4.0`
double snrByteToDb(int rawByte) {
  assert(rawByte >= 0 && rawByte <= 0xFF, 'expected an unsigned byte');
  final int signed = rawByte < 128 ? rawByte : rawByte - 256;
  return signed / 4.0;
}

/// Limits and bit assignments for the contact/identity/admin commands.
/// Each is the firmware's own constant or guard, not a recommendation.

/// `MAX_SIGN_DATA_LEN` (8 KiB) — `MyMesh.cpp:137`. The reply to
/// `CMD_SIGN_START` carries this same number.
const int kMaxSignDataLen = 8 * 1024;

/// A single `CMD_SIGN_DATA` frame carries at most `176 - 1` bytes.
const int kSignChunkMax = 175;

/// `BaseChatMesh::sendLogin` silently truncates a password to 15 bytes
/// (`src/helpers/BaseChatMesh.cpp:581,585`); the encoder refuses instead.
const int kLoginPasswordMax = 15;

/// Longest `CMD_SEND_ANON_REQ` payload that `Mesh::createAnonDatagram`
/// accepts: `(4 tag + n) + 1 + 32 + 15 <= MAX_PACKET_PAYLOAD (184)`
/// (`src/Mesh.cpp:514`). A longer one comes back ERR(table_full).
const int kAnonReqDataMax = 132;

/// `CMD_IMPORT_CONTACT` guard is `len > 2 + 32 + 64` including the
/// opcode, so the packet must be at least 98 bytes (`MyMesh.cpp:1369`).
const int kImportContactMin = 2 + 32 + 64;

/// Largest advert packet one frame can carry: `176 - 1`.
const int kImportContactMax = 175;

/// `AUTO_ADD_*` bits, `MyMesh.cpp:140-146`.
const int kAutoAddOverwriteOldest = 0x01;
const int kAutoAddChat = 0x02;
const int kAutoAddRepeater = 0x04;
const int kAutoAddRoomServer = 0x08;
const int kAutoAddSensor = 0x10;

/// `autoadd_max_hops` is clamped to 64 by the firmware
/// (`MyMesh.cpp:1981-1987`); the encoder refuses a larger value.
const int kAutoAddMaxHops = 64;
