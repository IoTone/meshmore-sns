// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
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
import 'constants.dart';
import 'decode_error.dart';

/// A decoded device→app frame. Sealed so callers exhaustively switch.
sealed class MeshcoreInbound {
  const MeshcoreInbound();
}

/// `RESP_CODE_OK` (0x00). [value] is the optional trailing uint32.
class OkFrame extends MeshcoreInbound {
  const OkFrame(this.value);
  final int? value;
  @override
  String toString() => 'OkFrame($value)';
}

/// `RESP_CODE_ERR` (0x01). [code] is the optional trailing error byte.
class ErrorFrame extends MeshcoreInbound {
  const ErrorFrame(this.code);
  final int? code;
  @override
  String toString() => 'ErrorFrame($code)';
}

/// `RESP_CODE_CONTACTS_START` (0x02).
class ContactsStartFrame extends MeshcoreInbound {
  const ContactsStartFrame(this.count);
  final int count;
  @override
  String toString() => 'ContactsStartFrame($count)';
}

/// `RESP_CODE_CONTACT` (0x03).
class ContactFrame extends MeshcoreInbound {
  const ContactFrame(this.contact);
  final Contact contact;
  @override
  String toString() => 'ContactFrame($contact)';
}

/// `RESP_CODE_END_OF_CONTACTS` (0x04).
class EndOfContactsFrame extends MeshcoreInbound {
  const EndOfContactsFrame(this.mostRecentLastMod);
  final int mostRecentLastMod;
  @override
  String toString() => 'EndOfContactsFrame($mostRecentLastMod)';
}

/// `RESP_CODE_SELF_INFO` (0x05) — also the APP_START reply.
class SelfInfoFrame extends MeshcoreInbound {
  const SelfInfoFrame(this.selfInfo);
  final SelfInfo selfInfo;
  @override
  String toString() => 'SelfInfoFrame($selfInfo)';
}

/// `RESP_CODE_SENT` (0x06) — send confirmation.
class MsgSentFrame extends MeshcoreInbound {
  const MsgSentFrame(this.sent);
  final MsgSent sent;
  @override
  String toString() => 'MsgSentFrame($sent)';
}

/// `PUSH_CODE_ACK` (0x82) — delivery acknowledgement for a sent
/// (direct) message. Carries the 4-byte CRC tag the device reported
/// as `MsgSent.expectedAck`, so the client can match it back to the
/// originating message and mark it delivered. Broadcast/channel
/// messages are flood-routed and never produce an ACK.
class AckFrame extends MeshcoreInbound {
  const AckFrame(this.ackCrc, {this.roundTripMs});

  /// The acknowledged message's CRC tag (u32 LE), equal to the
  /// [MsgSent.expectedAck] returned when the message was submitted.
  final int ackCrc;

  /// The radio's own send→ACK time (`PUSH_CODE_SEND_CONFIRMED` carries
  /// it after the tag). Null when the firmware omits it.
  final int? roundTripMs;

  @override
  String toString() =>
      'AckFrame(0x${ackCrc.toRadixString(16).padLeft(8, '0')})';
}

/// `RESP_CODE_CHANNEL_MSG_RECV` (0x08) and V3 (0x11).
class ChannelMessageFrame extends MeshcoreInbound {
  const ChannelMessageFrame(this.message);
  final ChannelMessage message;
  @override
  String toString() => 'ChannelMessageFrame($message)';
}

/// `RESP_CODE_CHANNEL_INFO` (0x12).
class ChannelInfoFrame extends MeshcoreInbound {
  const ChannelInfoFrame(this.info);
  final ChannelInfo info;
  @override
  String toString() => 'ChannelInfoFrame($info)';
}

/// `RESP_CODE_CONTACT_MSG_RECV` (0x07) and V3 (0x10).
class ContactMessageFrame extends MeshcoreInbound {
  const ContactMessageFrame(this.message);
  final ContactMessage message;
  @override
  String toString() => 'ContactMessageFrame($message)';
}

/// `PUSH_CODE_ADVERTISEMENT` (0x80).
class AdvertFrame extends MeshcoreInbound {
  const AdvertFrame(this.advert);
  final Advert advert;
  @override
  String toString() => 'AdvertFrame($advert)';
}

/// `RESP_CODE_DEVICE_INFO` (0x0D).
class DeviceInfoFrame extends MeshcoreInbound {
  const DeviceInfoFrame(this.info);
  final DeviceInfo info;
  @override
  String toString() => 'DeviceInfoFrame($info)';
}

/// `RESP_CODE_BATT_AND_STORAGE` (0x0C).
class BatteryStorageFrame extends MeshcoreInbound {
  const BatteryStorageFrame(this.battery);
  final BatteryStorage battery;
  @override
  String toString() => 'BatteryStorageFrame($battery)';
}

/// `PUSH_CODE_LOG_RX_DATA` (0x88) — raw received OTA packet + SNR/RSSI.
class RfLogFrame extends MeshcoreInbound {
  const RfLogFrame(this.log);
  final RfLog log;
  @override
  String toString() => 'RfLogFrame($log)';
}

/// `RESP_CODE_CURR_TIME` (0x09).
class CurrentTimeFrame extends MeshcoreInbound {
  const CurrentTimeFrame(this.unixSeconds);
  final int unixSeconds;

  DateTime get utc =>
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

  @override
  String toString() => 'CurrentTimeFrame($unixSeconds)';
}

/// `RESP_CODE_NO_MORE_MESSAGES` (0x0A).
class NoMoreMessagesFrame extends MeshcoreInbound {
  const NoMoreMessagesFrame();
  @override
  String toString() => 'NoMoreMessagesFrame()';
}

/// `RESP_CODE_CUSTOM_VARS` (0x15) — reply to CMD_GET_CUSTOM_VARS.
/// Carries the device's string-keyed settings (e.g. `gps`,
/// `gps_interval`). Known keys are documented in the firmware
/// `examples/companion_radio/MyMesh.cpp` — the codec is permissive
/// and surfaces everything the device reports.
class CustomVarsFrame extends MeshcoreInbound {
  const CustomVarsFrame(this.values);
  final Map<String, String> values;
  @override
  String toString() => 'CustomVarsFrame($values)';
}

/// `PUSH_CODE_MSGS_WAITING` (0x83) — the device has queued inbound
/// item(s) (received messages and/or newly heard contacts/adverts).
/// The app must drain them with `CMD_SYNC_NEXT_MESSAGE` until it gets
/// a [NoMoreMessagesFrame]. Some firmware appends a count byte; it is
/// advisory only, so [count] is null when absent.
class MessagesWaitingFrame extends MeshcoreInbound {
  const MessagesWaitingFrame([this.count]);
  final int? count;
  @override
  String toString() => 'MessagesWaitingFrame($count)';
}

/// `PUSH_CODE_TELEMETRY_RESPONSE` (0x8B) — the device delivered a
/// CayenneLPP telemetry payload, either for itself (immediate after a
/// self-telemetry `CMD_SEND_TELEMETRY_REQ`) or for a peer it queried
/// over the air on our behalf.
///
/// Wire layout: `[0x8B][reserved 1B][6B pubkey-prefix][LPP payload]`.
/// The pubkey-prefix identifies *which* node the payload belongs to —
/// matches the first 6 bytes of the originator's public key. For self-
/// telemetry the prefix is the device's own pubkey6.
class TelemetryResponseFrame extends MeshcoreInbound {
  const TelemetryResponseFrame({
    required this.pubKeyPrefix,
    required this.lppPayload,
  });
  final Uint8List pubKeyPrefix;
  final Uint8List lppPayload;
  @override
  String toString() =>
      'TelemetryResponseFrame(pub6=${pubKeyPrefix.length}B, '
      'lpp=${lppPayload.length}B)';
}

/// `RESP_CODE_STATS` (0x18). Exactly one of the three is set, per the
/// sub-type the radio answered.
class StatsFrame extends MeshcoreInbound {
  const StatsFrame({this.core, this.radio, this.packets});
  final CoreStats? core;
  final RadioStats? radio;
  final PacketStats? packets;
  @override
  String toString() => 'StatsFrame(${core ?? radio ?? packets})';
}

/// `PUSH_CODE_STATUS_RESPONSE` (0x87) — a repeater/sensor status reply.
/// The firmware matches it to our request by pubkey; so do we.
class StatusResponseFrame extends MeshcoreInbound {
  const StatusResponseFrame({required this.pubKeyPrefix, this.status});
  final Uint8List pubKeyPrefix;

  /// Null when the payload is too short to be a `RepeaterStats`.
  final RepeaterStatus? status;
  @override
  String toString() => 'StatusResponseFrame($status)';
}

/// `PUSH_CODE_TRACE_DATA` (0x89).
class TraceDataFrame extends MeshcoreInbound {
  const TraceDataFrame(this.trace);
  final TraceResult trace;
  @override
  String toString() => 'TraceDataFrame($trace)';
}

/// `PUSH_CODE_CONTROL_DATA` (0x8E). [discover] is decoded when the
/// payload is a node-discover response; [payload] is always kept.
class ControlDataFrame extends MeshcoreInbound {
  const ControlDataFrame({
    required this.snrDb,
    required this.rssi,
    required this.pathLen,
    required this.payload,
    this.discover,
  });
  final double snrDb;
  final int rssi;
  final int pathLen;
  final Uint8List payload;
  final DiscoverResponse? discover;
  @override
  String toString() => 'ControlDataFrame(${discover ?? '${payload.length}B'})';
}

/// `RESP_CODE_EXPORT_CONTACT` (0x0B) — a raw advert packet, ready for
/// `CMD_IMPORT_CONTACT` on another node.
class ExportedContactFrame extends MeshcoreInbound {
  const ExportedContactFrame(this.advertPacket);
  final Uint8List advertPacket;
  @override
  String toString() => 'ExportedContactFrame(${advertPacket.length}B)';
}

/// `RESP_CODE_PRIVATE_KEY` (0x0E). The key is a secret: [toString]
/// redacts it so it cannot leak through logging.
class PrivateKeyFrame extends MeshcoreInbound {
  const PrivateKeyFrame(this.privateKey);
  final Uint8List privateKey;
  @override
  String toString() => 'PrivateKeyFrame(<redacted ${privateKey.length}B>)';
}

/// `RESP_CODE_DISABLED` (0x0F) — the firmware was built without this
/// command (`ENABLE_PRIVATE_KEY_EXPORT` / `_IMPORT`).
class DisabledFrame extends MeshcoreInbound {
  const DisabledFrame();
  @override
  String toString() => 'DisabledFrame()';
}

/// `RESP_CODE_SIGN_START` (0x13) — [maxLength] is the signing buffer size.
class SignStartFrame extends MeshcoreInbound {
  const SignStartFrame(this.maxLength);
  final int maxLength;
  @override
  String toString() => 'SignStartFrame($maxLength)';
}

/// `RESP_CODE_SIGNATURE` (0x14) — a 64-byte Ed25519 signature.
class SignatureFrame extends MeshcoreInbound {
  const SignatureFrame(this.signature);
  final Uint8List signature;
  @override
  String toString() => 'SignatureFrame(${signature.length}B)';
}

/// `RESP_CODE_ADVERT_PATH` (0x16).
class AdvertPathFrame extends MeshcoreInbound {
  const AdvertPathFrame(this.advertPath);
  final AdvertPath advertPath;
  @override
  String toString() => 'AdvertPathFrame(${advertPath.pathLen})';
}

/// `RESP_CODE_TUNING_PARAMS` (0x17).
class TuningParamsFrame extends MeshcoreInbound {
  const TuningParamsFrame(this.params);
  final TuningParams params;
  @override
  String toString() => 'TuningParamsFrame($params)';
}

/// `RESP_CODE_AUTOADD_CONFIG` (0x19).
class AutoAddConfigFrame extends MeshcoreInbound {
  const AutoAddConfigFrame(this.config);
  final AutoAddConfig config;
  @override
  String toString() => 'AutoAddConfigFrame($config)';
}

/// `PUSH_CODE_LOGIN_SUCCESS` (0x85) / `PUSH_CODE_LOGIN_FAIL` (0x86).
class LoginResultFrame extends MeshcoreInbound {
  const LoginResultFrame(this.result);
  final LoginResult result;
  @override
  String toString() => 'LoginResultFrame(success=${result.success})';
}

/// `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D).
class PathDiscoveryFrame extends MeshcoreInbound {
  const PathDiscoveryFrame(this.result);
  final PathDiscoveryResult result;
  @override
  String toString() => 'PathDiscoveryFrame(out=${result.outPathLen}, '
      'in=${result.inPathLen})';
}

/// `PUSH_CODE_CONTACT_DELETED` (0x8F) — a contact was overwritten to make
/// room; the app must drop its copy.
class ContactDeletedFrame extends MeshcoreInbound {
  const ContactDeletedFrame(this.publicKey);
  final Uint8List publicKey;
  @override
  String toString() => 'ContactDeletedFrame()';
}

/// `PUSH_CODE_CONTACTS_FULL` (0x90).
class ContactsFullFrame extends MeshcoreInbound {
  const ContactsFullFrame();
  @override
  String toString() => 'ContactsFullFrame()';
}

/// `PUSH_CODE_ONE_KEY_DM_REJECTED` (0x91). The radio refused a stranger's
/// message for want of a signed introduction; [publicKey] is the sender.
class OneKeyRejectedFrame extends MeshcoreInbound {
  const OneKeyRejectedFrame(this.publicKey);
  final Uint8List publicKey;
  @override
  String toString() => 'OneKeyRejectedFrame(${publicKey.length} bytes)';
}

/// `PUSH_CODE_PATH_UPDATED` (0x81). Only the key: re-read the contact.
class PathUpdatedFrame extends MeshcoreInbound {
  const PathUpdatedFrame(this.publicKey);
  final Uint8List publicKey;
  @override
  String toString() => 'PathUpdatedFrame()';
}

/// `PUSH_CODE_RAW_DATA` (0x84): a raw-custom packet heard by the radio.
///
/// Carries no sender identity and is never queued by the firmware, so a
/// disconnected app loses it (`MyMesh.cpp:801-818`).
class RawDataFrame extends MeshcoreInbound {
  const RawDataFrame({
    required this.snrDb,
    required this.rssi,
    required this.payload,
    this.via = RxVia.unknown,
  });
  final double snrDb;
  final int rssi;
  final Uint8List payload;

  /// Which radio profile delivered the packet, when the radio reports it
  /// (the same byte `ChannelDataFrame.via` comes from, with 0xFF as its
  /// "none" value).
  final RxVia via;

  @override
  String toString() =>
      'RawDataFrame(${payload.length}B, rssi $rssi, via ${via.name})';
}

/// `PUSH_CODE_NEW_ADVERT` (0x8A): a contact frame for a first-heard node.
class NewAdvertFrame extends MeshcoreInbound {
  const NewAdvertFrame(this.contact);
  final Contact contact;
  @override
  String toString() => 'NewAdvertFrame($contact)';
}

/// `RESP_CODE_CHANNEL_DATA_RECV` (0x1B): `data_type` is the 16-bit
/// application tag (`docs/number_allocations.md`); [pathLen] is 0xFF when
/// the packet was not flooded.
class ChannelDataFrame extends MeshcoreInbound {
  const ChannelDataFrame({
    required this.snrDb,
    required this.channelIndex,
    required this.pathLen,
    required this.dataType,
    required this.data,
    this.via = RxVia.unknown,
  });
  final double snrDb;
  final int channelIndex;
  final int pathLen;
  final int dataType;
  final Uint8List data;

  /// Which radio profile delivered the datagram, when the radio reports it.
  ///
  /// Always [RxVia.unknown] on a single-profile radio and on mainline
  /// firmware, which writes 0 in this byte.
  final RxVia via;

  @override
  String toString() =>
      'ChannelDataFrame(ch $channelIndex, via ${via.name}, '
      'type 0x${dataType.toRadixString(16)}, ${data.length}B)';
}

/// `RESP_CODE_CLI_REPLY` (0x1D): one line of a command's output.
///
/// A `CMD_RUN_CLI_COMMAND` produces zero or more of these, each its own
/// frame, followed by `OK`. The line is [text] and carries no framing
/// beyond the frame length.
class CliReplyFrame extends MeshcoreInbound {
  const CliReplyFrame(this.text);
  final String text;
  @override
  String toString() => 'CliReplyFrame("$text")';
}

/// A well-formed frame whose opcode this milestone does not decode yet.
/// Carries the raw bytes so higher layers can log/skip without data loss.
class UnsupportedFrame extends MeshcoreInbound {
  const UnsupportedFrame(this.opcode, this.raw);
  final int opcode;
  final Uint8List raw;
  @override
  String toString() =>
      'UnsupportedFrame(0x${opcode.toRadixString(16)}, ${raw.length}B)';
}

/// Decoding failed (empty/truncated). Never thrown — always returned.
class DecodeFailure extends MeshcoreInbound {
  const DecodeFailure(this.error);
  final MeshcoreDecodeError error;
  @override
  String toString() => 'DecodeFailure($error)';
}
