// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One file of the AEIC codec's model bundle.
///
/// Sizes and digests are the ones the host publishes: `huggingface.co/zjs81/
/// aeic-se-onnx` at `d16423e0`. The digest is the file's own SHA-256 (the host's
/// large-file object id), so a download is verified against the published bytes
/// rather than against our own transfer.
@immutable
class AeicModelFile {
  const AeicModelFile({
    required this.name,
    required this.bytes,
    required this.sha256,
    required this.role,
  });

  final String name;
  final int bytes;
  final String sha256;

  /// What the file is for, in the settings copy.
  final String role;

  Uri get url => Uri.parse(
      'https://huggingface.co/zjs81/aeic-se-onnx/resolve/main/$name');
}

/// The bundle: three ONNX graphs and the rANS CDF table.
///
/// The decoder file is the `.onnx.data` beside its `.onnx` graph — 832 MB of
/// weights, which is why this is a download and not an asset.
const List<AeicModelFile> kAeicModelFiles = <AeicModelFile>[
  AeicModelFile(
    name: 'aeic_decoder_qdq_conv_pct.onnx',
    bytes: 3066597,
    sha256: 'fa1ca65c52ecb9e1ec43c05ef792ac8b95ecab21dcb6ab89a825b4dad6a5a571',
    role: 'Decoder graph',
  ),
  AeicModelFile(
    name: 'aeic_decoder_qdq_conv_pct.onnx.data',
    bytes: 872896480,
    sha256: 'f7714df0ec8cc495be1fb4bad3be0458c186c8a61d87b8487f2e8e6b84b8242a',
    role: 'Decoder weights',
  ),
  AeicModelFile(
    name: 'aeic_entropy_decode_fp32_op17.onnx',
    bytes: 60509540,
    sha256: 'efcbbc4829a0029f487f17b7b52373c6af339d7f74a6417463981d0778d6d444',
    role: 'Decode-side entropy model',
  ),
  AeicModelFile(
    name: 'aeic_entropy_side_fp32_op17.onnx',
    bytes: 67262167,
    sha256: 'b7b55b0f6a8a02ec2e8f6e85820c064c741c870c226d276c78df45e83ca1a9d6',
    role: 'Send-side entropy model',
  ),
  AeicModelFile(
    name: 'aeic_cdf_ft32.bin',
    bytes: 813648,
    sha256: '4089fde2af16c340642a5c857be42f6d0f21caf71dd5b4f32d62efcd41c77bd5',
    role: 'rANS tables',
  ),
];

/// Total download size of the bundle.
int get kAeicBundleBytes =>
    kAeicModelFiles.fold(0, (int n, AeicModelFile f) => n + f.bytes);

/// Where the codec is in its life.
enum AeicState {
  /// Nothing on disk.
  absent,

  /// Some files are present; the bundle is not usable.
  partial,

  /// Bytes arriving or hashes being checked.
  working,

  /// Every file present and verified.
  ready,

  /// The last attempt failed; [AeicInstaller.error] says how.
  failed,
}

/// Downloads, verifies and removes the AEIC model bundle.
///
/// Deliberately small and dull: this is a file transfer with a checksum, not a
/// codec. The codec port lives beside it and is only reachable when [ready].
///
/// Three properties matter and each has a reason:
/// * **Resumable** — the bundle is ~1 GB; a phone that loses a train tunnel at
///   800 MB must not start again. `Range` is sent when bytes are already on
///   disk, and a server that ignores it rewrites the file from zero.
/// * **Verified** — each file is hashed and compared to the published digest.
///   A bundle that half-arrived through a proxy would otherwise make the codec
///   fail at a random frame, which reads as a broken app rather than as a bad
///   download.
/// * **Removable** — the reader can take the gigabyte back. [remove] deletes the
///   directory, and [state] then reports [AeicState.absent].
class AeicInstaller extends ChangeNotifier {
  AeicInstaller({
    Future<Directory> Function()? root,
    http.Client Function()? clientFactory,
    List<AeicModelFile>? files,
  })  : _root = root ?? _defaultRoot,
        _newClient = clientFactory ?? http.Client.new,
        files = files ?? kAeicModelFiles;

  static Future<Directory> _defaultRoot() async {
    final Directory base = await getApplicationSupportDirectory();
    return Directory('${base.path}/aeic');
  }

  final Future<Directory> Function() _root;
  final http.Client Function() _newClient;

  /// The bundle this installer owns. Injectable so the transfer, the resume and
  /// the checksum can be tested against a handful of bytes instead of a
  /// gigabyte.
  final List<AeicModelFile> files;

  AeicState _state = AeicState.absent;
  AeicState get state => _state;

  String? _error;
  String? get error => _error;

  /// Bytes already on disk for the whole bundle.
  int _have = 0;
  int get downloadedBytes => _have;
  int get totalBytes =>
      files.fold(0, (int n, AeicModelFile f) => n + f.bytes);

  /// 0..1 for the current install, or null when nothing is downloading.
  double? get progress =>
      _state == AeicState.working && totalBytes > 0 ? _have / totalBytes : null;

  bool get ready => _state == AeicState.ready;
  bool _busy = false;
  bool get busy => _busy;

  bool _cancel = false;
  void cancel() => _cancel = true;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(AeicState s, {String? error}) {
    if (_disposed) return;
    _state = s;
    _error = error;
    notifyListeners();
  }

  /// What is on disk right now, without hashing anything.
  Future<void> refresh() async {
    final Directory dir = await _root();
    if (!await dir.exists()) {
      _have = 0;
      _set(AeicState.absent);
      return;
    }
    int have = 0;
    int present = 0;
    for (final AeicModelFile f in files) {
      final File file = File('${dir.path}/${f.name}');
      final int size = await file.exists() ? await file.length() : 0;
      if (size >= f.bytes) present++;
      have += size.clamp(0, f.bytes);
    }
    _have = have;
    if (present == files.length) {
      _set(AeicState.ready);
    } else if (present == 0 && have == 0) {
      _set(AeicState.absent);
    } else {
      _set(AeicState.partial);
    }
  }

  /// Fetch whatever is missing, verify it, and report.
  ///
  /// A file whose digest does not match is deleted and fetched once more, so a
  /// corrupted resume is repaired rather than reported. Two failures in a row
  /// set [AeicState.failed] with the reason.
  Future<void> install() async {
    if (_busy) return;
    _busy = true;
    _cancel = false;
    _error = null;
    _set(AeicState.working);
    final Directory dir = await _root();
    if (!await dir.exists()) await dir.create(recursive: true);
    try {
      for (final AeicModelFile f in files) {
        if (_cancel) {
          _set(AeicState.partial);
          return;
        }
        final File file = File('${dir.path}/${f.name}');
        if (await _verified(file, f)) {
          _have += f.bytes;
          continue;
        }
        bool ok = await _fetch(file, f);
        if (!ok) {
          // One repair attempt: delete what is there and take it whole.
          if (await file.exists()) await file.delete();
          ok = await _fetch(file, f);
        }
        if (!ok) {
          _set(AeicState.failed,
              error: '${f.name}: the download did not match its checksum');
          return;
        }
        _have += f.bytes;
      }
      await refresh();
    } on Object catch (e) {
      _set(AeicState.failed, error: '$e');
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Delete the bundle and its bytes.
  Future<void> remove() async {
    final Directory dir = await _root();
    if (await dir.exists()) await dir.delete(recursive: true);
    _have = 0;
    _set(AeicState.absent);
  }

  /// The path the codec should load [name] from, or null when it is absent.
  Future<String?> pathOf(String name) async {
    final Directory dir = await _root();
    final File file = File('${dir.path}/$name');
    return await file.exists() ? file.path : null;
  }

  Future<bool> _verified(File file, AeicModelFile f) async {
    if (!await file.exists()) return false;
    if (await file.length() != f.bytes) return false;
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == f.sha256;
  }

  /// One file, resuming from whatever is on disk.
  Future<bool> _fetch(File file, AeicModelFile f) async {
    int start = await file.exists() ? await file.length() : 0;
    if (start > f.bytes) {
      await file.delete();
      start = 0;
    }
    if (start == f.bytes) return _verified(file, f);
    final http.Client client = _newClient();
    try {
      final http.Request req = http.Request('GET', f.url);
      if (start > 0) req.headers['Range'] = 'bytes=$start-';
      final http.StreamedResponse res = await client.send(req);
      final bool resumed = start > 0 && res.statusCode == 206;
      if (res.statusCode != 200 && res.statusCode != 206) return false;
      if (!resumed) start = 0;
      final IOSink sink =
          file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      try {
        await for (final List<int> chunk in res.stream) {
          if (_cancel || _disposed) break;
          sink.add(chunk);
          _have += chunk.length;
          if (!_disposed) notifyListeners();
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (_cancel) return false;
      return await _verified(file, f);
    } finally {
      client.close();
    }
  }
}
