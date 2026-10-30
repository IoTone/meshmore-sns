// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A companion radio on a USB-serial port.
///
/// TTY policy lives here rather than in the protocol code, so
/// `serial_transport.dart` stays a pure byte pipe and can be tested without a
/// device. `stty` configures the port because a native libserialport binding
/// would be one more thing to build on every host.
class SerialPort {
  SerialPort._(this._read, this._writeHandle);

  final RandomAccessFile _read;
  final RandomAccessFile _writeHandle;
  bool _stopping = false;

  /// `RandomAccessFile` accepts one operation at a time and throws
  /// "An async operation is currently pending" if two are issued. The L1 link
  /// does not serialize its own writes, so this does. Found on hardware: the
  /// in-memory write in tests is synchronous and never overlaps.
  Future<void> _writeTail = Future<void>.value();

  static Future<SerialPort> open(String path, int baud) async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError(
        'this launcher supports Linux and macOS; use a serial library on '
        'other hosts',
      );
    }
    final String flag = Platform.isMacOS ? '-f' : '-F';
    final ProcessResult result = await Process.run('stty', <String>[
      flag,
      path,
      '$baud',
      'raw',
      '-echo',
      '-hupcl',
      // No hardware flow control: the firmware does not drive RTS/CTS.
      '-crtscts',
    ]);
    if (result.exitCode != 0) {
      throw StateError('stty failed on $path: ${result.stderr}');
    }
    final RandomAccessFile read = await File(path).open(mode: FileMode.read);
    // `writeOnlyAppend` makes the VM seek to end of file before opening, and a
    // TTY rejects that with ESPIPE ("Illegal seek"). Plain `writeOnly` opens
    // without seeking; O_TRUNC is ignored on a character device. Observed on
    // a USB CDC tty (ESP32-S3) on 2026-10-28.
    final RandomAccessFile write =
        await File(path).open(mode: FileMode.writeOnly);
    return SerialPort._(read, write);
  }

  Future<void> write(List<int> bytes) {
    final Future<void> next = _writeTail.then((_) async {
      // No flush: it maps to fsync, and a TTY answers EINVAL ("Invalid
      // argument"). Character devices are unbuffered, so the write syscall is
      // already the whole delivery. Observed on a USB CDC tty, 2026-10-28.
      await _writeHandle.writeFrom(bytes);
    });
    // The tail must never carry an error, or one failed write would poison
    // every later one.
    _writeTail = next.catchError((Object _) {});
    return next;
  }

  /// Reads until [stop] is called or the port errors.
  ///
  /// A blocking read on a TTY cannot be cancelled from Dart, so a pending read
  /// outlives [close]. That is why [stop] exists separately: it ends the loop,
  /// and [close] tolerates the one pending operation it cannot cancel.
  Future<void> pump(StreamController<List<int>> out) async {
    try {
      while (!_stopping && !out.isClosed) {
        final Uint8List chunk = await _read.read(4096);
        if (_stopping) break;
        if (chunk.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        out.add(chunk);
      }
    } catch (e) {
      if (!_stopping && !out.isClosed) out.addError(e);
    }
  }

  void stop() => _stopping = true;

  Future<void> close() async {
    _stopping = true;
    try {
      await _writeTail;
    } on Object {
      // A failed write is reported through [write]'s future.
    }
    // The VM throws "An async operation is currently pending" when a blocking
    // read is still outstanding. Nothing is lost: the process exit closes the
    // port, and a half-read frame was already incomplete.
    try {
      await _read.close();
    } on FileSystemException {
      // Deliberate: see above.
    }
    try {
      await _writeHandle.close();
    } on FileSystemException {
      // Deliberate: see above.
    }
  }
}
