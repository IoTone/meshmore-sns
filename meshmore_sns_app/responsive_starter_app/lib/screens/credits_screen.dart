// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gen/app_localizations.dart';
import '../legal/shipped_packages.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';

/// Everything this app is built out of, in one flat list.
///
/// The owner's report: the licence page was "just categories with all the
/// different licenses", unlabelled, and it named only the Dart packages. That
/// page is Flutter's own `showLicensePage`, which groups by package and knows
/// nothing about the native libraries, the fonts or the map data, so the things
/// that actually carry obligations were the ones missing.
///
/// This screen is one alphabetical list with no categories, because a reader
/// looking for "is libaom credited" should not have to guess which heading it
/// would be under. Each row names the component, its version where there is
/// one, its licence, and where it comes from. A row opens the full licence text
/// when the app has it (every Dart package does, through `LicenseRegistry`) and
/// the project's own page when it does not.
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => CreditsScreenState();
}

class CreditsScreenState extends State<CreditsScreen> {
  /// The Dart packages, read from the licence registry Flutter fills at build
  /// time. Null until the future resolves.
  List<Credit>? _packages;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Credit> out = <Credit>[];
    final Set<String> seen = <String>{};
    await for (final LicenseEntry entry in LicenseRegistry.licenses) {
      for (final String pkg in entry.packages) {
        // Only what ships. The registry carries the whole graph, including the
        // SDK's build-time packages and every AAR a plugin pulls in, which is
        // right for licensing and wrong for a page a reader looks at.
        if (!kShippedPackages.contains(pkg)) continue;
        if (!seen.add(pkg)) continue;
        out.add(Credit(
          name: pkg,
          licence: _spdxFor(pkg),
          body: entry.paragraphs.map((LicenseParagraph p) => p.text).join('\n\n'),
        ));
      }
    }
    if (!mounted) return;
    setState(() => _packages = out);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final List<Credit> all = <Credit>[
      ...kNativeCredits,
      ...?_packages,
    ]..sort((Credit a, Credit b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: Text(l.creditsTitle)),
      body: MmScaffold(
        child: _packages == null
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: EdgeInsets.symmetric(
                    horizontal: skin.space.screenEdge,
                    vertical: skin.space.rowGap),
                itemCount: all.length + 1,
                separatorBuilder: (_, __) => Divider(
                    height: 1, color: skin.color.line.withValues(alpha: .4)),
                itemBuilder: (BuildContext c, int i) {
                  if (i == 0) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: skin.space.rowGap),
                      child: Text(
                        l.creditsIntro,
                        style: TextStyle(
                            color: skin.color.fgMuted,
                            fontSize: skin.type.sizeSm,
                            height: 1.4),
                      ),
                    );
                  }
                  final Credit credit = all[i - 1];
                  return ListTile(
                    key: ValueKey<String>('credit-${credit.name}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      credit.version == null
                          ? credit.name
                          : '${credit.name} ${credit.version}',
                      style: TextStyle(
                          color: skin.color.fg, fontSize: skin.type.sizeBody),
                    ),
                    subtitle: Text(
                      credit.licence,
                      style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeSm),
                    ),
                    trailing: credit.url == null
                        ? null
                        : Icon(Icons.open_in_new,
                            size: 16, color: skin.color.fgMuted),
                    onTap: () => _open(context, credit),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Credit credit) async {
    if (credit.body != null) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext c) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          builder: (BuildContext c2, ScrollController scroll) => ListView(
            controller: scroll,
            padding: EdgeInsets.all(context.skin.space.screenEdge),
            children: <Widget>[
              Builder(builder: (BuildContext c) {
                final MmSkin skin = c.skin;
                return Text(credit.name,
                    style: TextStyle(
                        color: skin.color.fg,
                        fontSize: skin.type.sizeLg,
                        fontWeight: FontWeight.w700));
              }),
              const SizedBox(height: 8),
              Text(credit.licence),
              const SizedBox(height: 12),
              SelectableText(credit.body!),
            ],
          ),
        ),
      );
      return;
    }
    final Uri? url = credit.url;
    if (url != null) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

/// One component: what it is called, what it is licensed under, and where it
/// comes from.
@immutable
final class Credit {
  const Credit({
    required this.name,
    required this.licence,
    this.version,
    this.url,
    this.body,
  });

  final String name;
  final String licence;
  final String? version;
  final Uri? url;

  /// The full licence text, when the app has it.
  final String? body;
}

/// The components that are not Dart packages.
///
/// These are the ones with real obligations and no entry in Flutter's licence
/// registry: the image codec's three libraries, the speech codec, the six type
/// faces, and the map data and style. Each is named with the licence it is
/// actually under, and the URL is the project's own page rather than a guess.
const List<Credit> kNativeCredits = <Credit>[
  // The neural image codec's model bundle. Not a package: it is downloaded from
  // its publisher on demand (about 1 GB), so the registry never sees it and the
  // attribution has to be written here. MIT, and the copyright line is the one
  // the model card carries.
  Credit(
    name: 'AEIC-SE image codec (zjs81/aeic-se-onnx)',
    licence: 'MIT',
    body: 'Copyright (c) 2026 zjs81\n\n'
        'The AEIC-SE neural image codec models (three ONNX graphs and the rANS '
        'CDF table) are published at huggingface.co/zjs81/aeic-se-onnx under the '
        'MIT licence. They are downloaded from that address only when the reader '
        'installs the codec from Settings → Chat & photos, and deleted when they\n'
        'remove it.',
  ),
  Credit(
    name: 'libavif',
    licence: 'BSD-2-Clause',
    url: null,
  ),
  Credit(
    name: 'libaom (AV1)',
    licence: 'BSD-2-Clause',
    url: null,
  ),
  Credit(
    name: 'dav1d',
    licence: 'BSD-2-Clause',
    url: null,
  ),
  Credit(
    name: 'Codec 2',
    licence: 'LGPL-2.1',
    version: '1.2.0',
    url: null,
  ),
  Credit(
    name: 'Saira',
    licence: 'SIL OFL 1.1',
    url: null,
  ),
  Credit(
    name: 'JetBrains Mono',
    licence: 'SIL OFL 1.1',
    url: null,
  ),
  Credit(
    name: 'Fira Mono',
    licence: 'SIL OFL 1.1',
    url: null,
  ),
  Credit(
    name: 'Source Code Pro',
    licence: 'SIL OFL 1.1',
    url: null,
  ),
  Credit(
    name: 'Geist Mono',
    licence: 'SIL OFL 1.1',
    url: null,
  ),
  Credit(
    name: 'Cascadia Code',
    licence: 'SIL OFL 1.1',
    url: null,
  ),
  Credit(
    name: 'OpenStreetMap data',
    licence: 'ODbL 1.0',
    url: null,
  ),
  Credit(
    name: 'OpenFreeMap style',
    licence: 'Apache-2.0',
    url: null,
  ),
  Credit(
    name: 'Shortbread vector schema',
    licence: 'CC0 1.0',
    url: null,
  ),
  Credit(
    name: 'Flutter',
    licence: 'BSD-3-Clause',
    url: null,
  ),
];

/// The SPDX identifier for a Dart package, where it is known.
///
/// Flutter's registry carries the licence *text*, not an identifier, and a
/// reader scanning a list wants the identifier. The map covers the packages
/// this app actually ships; anything else falls back to the text's own first
/// line, which is honest rather than invented.
String _spdxFor(String package) => switch (package) {
      'flutter' || 'flutter_localizations' || 'flutter_test' => 'BSD-3-Clause',
      'provider' || 'go_router' || 'shared_preferences' => 'BSD-3-Clause',
      'audioplayers' || 'flutter_blue_plus' || 'flutter_map' => 'MIT',
      'latlong2' || 'vector_tile' || 'vector_tile_renderer' => 'Apache-2.0',
      'avif_native' => 'BSD-2-Clause',
      'archive' => 'MIT',
      'url_launcher' || 'permission_handler' => 'BSD-3-Clause',
      'flutter_foreground_task' => 'MIT',
      'geolocator' => 'MIT',
      'flutter_local_notifications' => 'BSD-3-Clause',
      'crypto' || 'convert' || 'collection' => 'BSD-3-Clause',
      _ => 'see licence text',
    };
