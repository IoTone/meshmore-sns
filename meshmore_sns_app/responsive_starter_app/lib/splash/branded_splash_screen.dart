// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../gen/app_localizations.dart';
import '../shell/boot_surface.dart';

/// The launch screen shown while preferences, terms and the radio come up.
///
/// It is `MmBootSurface` and nothing else. It used to be a second design — a
/// centred logo, the name, the tagline and a version readout in Material's own
/// colours, rotated for two and a bit seconds, after which `BootOverlay` replaced
/// it with a different screen that waited for the radio. Two loading screens in
/// a row, built from different shapes, is a launch that looks like two apps.
///
/// The only thing this widget adds is what the launch says: the app's name, the
/// version, and one line of state. Everything visible about it belongs to
/// `MmBootSurface`, which means every theme launches in its own palette without
/// this file knowing a colour.
class BrandedSplashScreen extends StatefulWidget {
  const BrandedSplashScreen({super.key});

  @override
  State<BrandedSplashScreen> createState() => _BrandedSplashScreenState();
}

class _BrandedSplashScreenState extends State<BrandedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dial = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  /// The version, once the platform has answered. Never a placeholder: an empty
  /// line is honest and a guessed one is not.
  String _version = '';

  @override
  void initState() {
    super.initState();
    _info.then((PackageInfo p) {
      if (mounted) setState(() => _version = 'v${p.version}+${p.buildNumber}');
    });
  }

  @override
  void dispose() {
    _dial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      body: MmBootSurface(
        dial: _dial,
        name: 'Meshmore SNS',
        subtitle: l.appSubtitle.toUpperCase(),
        status: _version.isEmpty ? l.bootStarting : _version,
      ),
    );
  }
}
