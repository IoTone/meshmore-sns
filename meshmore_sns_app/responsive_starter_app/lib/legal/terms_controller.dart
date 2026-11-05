// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The terms and privacy text the user is shown, and the version they agreed
/// to.
///
/// The version exists because the page is a commitment: bumping [version]
/// when the wording changes materially makes the gate show it again, so
/// nobody stays bound by text they never saw. One integer in
/// `SharedPreferences` is the whole record — there is no account, no server
/// and no consent log to keep.
class TermsController extends ChangeNotifier {
  TermsController({int? acceptedVersion, bool? loaded})
      : _acceptedVersion = acceptedVersion,
        _loaded = loaded ?? acceptedVersion != null;

  /// Test helper: a controller that already knows the stored answer.
  factory TermsController.accepted({int version = currentVersion}) =>
      TermsController(acceptedVersion: version, loaded: true);

  /// Bump when the text changes materially.
  static const int currentVersion = 2;

  static const String _key = 'mm.legal.acceptedVersion';

  int? _acceptedVersion;
  bool _loaded;

  bool get loaded => _loaded;

  /// True when the user has agreed to the current version.
  bool get accepted => _loaded && _acceptedVersion == currentVersion;

  /// The version they agreed to, or null if they never did.
  int? get acceptedVersion => _acceptedVersion;

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    _acceptedVersion = p.getInt(_key);
    _loaded = true;
    notifyListeners();
  }

  Future<void> accept() async {
    if (accepted) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt(_key, currentVersion);
    _acceptedVersion = currentVersion;
    _loaded = true;
    notifyListeners();
  }

  /// Test/debug only: makes the gate show the page again.
  @visibleForTesting
  Future<void> forget() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_key);
    _acceptedVersion = null;
    notifyListeners();
  }
}
