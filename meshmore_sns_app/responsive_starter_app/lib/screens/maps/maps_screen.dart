// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../maps/event_layer.dart';
import '../../maps/map_archive.dart';
import '../../maps/map_pack.dart';
import '../../maps/map_source.dart';
import '../../maps/maps_controller.dart';
import '../../maps/pack_catalog.dart';
import '../../theme/mm_skin.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_scaffold.dart';
import '../tools/tool_widgets.dart';

/// "12.3 MB" — decimal units, as the budget choices are.
String fmtBytes(int b) {
  if (b < 1000) return '$b B';
  if (b < 1000 * 1000) return '${(b / 1000).toStringAsFixed(0)} kB';
  if (b < 1000 * 1000 * 1000) {
    final double mb = b / 1e6;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
  return '${(b / 1e9).toStringAsFixed(1)} GB';
}

String keepLabel(AppLocalizations l, int days) =>
    days == 0 ? l.mapsKeepNever : l.mapsKeepDays(days);

String packStateLabel(AppLocalizations l, PackState s) => switch (s) {
      PackState.downloading => l.packStateDownloading,
      PackState.updating => l.packStateUpdating,
      PackState.waitingForNetwork => l.packStateWaiting,
      PackState.overBudget => l.packStateOverBudget,
      PackState.paused => l.packStatePaused,
      PackState.complete => l.packStateComplete,
    };

String packRefusalText(AppLocalizations l, PackRefusal r) => switch (r) {
      PackRefusal.noName => l.packRefusalNoName,
      PackRefusal.offline => l.packRefusalOffline,
      PackRefusal.sourceViewOnly => l.packRefusalViewOnly,
      PackRefusal.outsideCoverage => l.packRefusalCoverage,
      PackRefusal.tooManyTiles => l.packRefusalTooMany,
      PackRefusal.overBudget => l.packRefusalBudget,
    };

String archiveStateLabel(AppLocalizations l, ArchiveState s) => switch (s) {
      ArchiveState.downloading => l.packStateDownloading,
      ArchiveState.waitingForWifi => l.archiveStateWaitingWifi,
      ArchiveState.waitingForNetwork => l.packStateWaiting,
      ArchiveState.overBudget => l.packStateOverBudget,
      ArchiveState.paused => l.packStatePaused,
      ArchiveState.complete => l.packStateComplete,
      ArchiveState.failed => l.archiveStateFailed,
    };

String archiveFailureText(AppLocalizations l, ArchiveFailure f) => switch (f) {
      ArchiveFailure.badHash => l.archiveFailBadHash,
      ArchiveFailure.badSize => l.archiveFailBadSize,
      ArchiveFailure.notPmTiles => l.archiveFailNotPm,
      ArchiveFailure.wrongSchema => l.archiveFailSchema,
      ArchiveFailure.notFound => l.archiveFailNotFound,
    };

String archiveRefusalText(AppLocalizations l, ArchiveRefusal r) => switch (r) {
      ArchiveRefusal.noName => l.packRefusalNoName,
      ArchiveRefusal.badUrl => l.layerRefusalBadUrl,
      ArchiveRefusal.duplicate => l.archiveRefusalDuplicate,
      ArchiveRefusal.overBudget => l.packRefusalBudget,
      ArchiveRefusal.notEnoughSpace => l.archiveRefusalNoSpace,
    };

String layerRefusalText(AppLocalizations l, LayerRefusal r) => switch (r) {
      LayerRefusal.badUrl => l.layerRefusalBadUrl,
      LayerRefusal.offline => l.packRefusalOffline,
      LayerRefusal.notGeoJson => l.layerRefusalNotGeoJson,
      LayerRefusal.tooLarge => l.layerRefusalTooLarge,
      LayerRefusal.overBudget => l.packRefusalBudget,
    };

String expiryText(AppLocalizations l, int? atMs) {
  if (atMs == null) return l.mapsKeepForever;
  final int days = ((atMs - DateTime.now().millisecondsSinceEpoch) /
          Duration.millisecondsPerDay)
      .ceil();
  return l.mapsExpiresIn(days < 0 ? 0 : days);
}

/// R61 — Settings → Offline maps (issue #5).
class MapsScreen extends StatelessWidget {
  const MapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MapsController maps = context.watch<MapsController>();
    final MmSkin skin = context.skin;
    final double used = maps.budgetBytes == 0
        ? 0
        : (maps.usedBytes / maps.budgetBytes).clamp(0, 1).toDouble();
    return Scaffold(
      appBar: AppBar(title: Text(l.mapsTitle), actions: <Widget>[
        IconButton(
          tooltip: l.mapsSelfTest,
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () => context.push('/settings/maps/selftest'),
        ),
      ]),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            if (!maps.online) ...<Widget>[
              ToolNotice(text: l.mapsOffline, icon: Icons.cloud_off),
              const SizedBox(height: 12),
            ],
            MmSectionHeader(l.mapsStorage),
            const SizedBox(height: 6),
            ToolLine(l.mapsUsed(
                fmtBytes(maps.usedBytes), fmtBytes(maps.budgetBytes))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(value: used),
            ),
            ToolLine(
              l.mapsBreakdown(
                fmtBytes(maps.pinnedBytes - maps.layerBytes),
                fmtBytes(maps.layerBytes),
                fmtBytes(maps.viewBytes),
              ),
              muted: true,
            ),
            ToolField(
              label: l.mapsBudget,
              child: ToolChoice<int>(
                value: maps.budgetMb,
                values: MapsController.budgetChoicesMb,
                label: (int mb) => fmtBytes(mb * 1000 * 1000),
                onChanged: maps.setBudgetMb,
              ),
            ),
            ToolField(
              label: l.mapsViewKeep,
              child: ToolChoice<int>(
                value: maps.viewKeepDays,
                values: MapsController.viewKeepChoicesDays,
                label: (int d) => l.mapsKeepDays(d),
                onChanged: maps.setViewKeepDays,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(l.mapsClearView),
                onPressed: maps.viewBytes == 0 ? null : maps.clearViewCache,
              ),
            ),
            const SizedBox(height: 16),
            MmSectionHeader(l.mapsPacks),
            const SizedBox(height: 6),
            if (maps.packs.isEmpty) ToolLine(l.mapsNoPacks, muted: true),
            for (final MapPack p in maps.packs) _PackRow(pack: p),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(l.mapsAddPack),
                onPressed: () => context.push('/settings/maps/new'),
              ),
            ),
            const SizedBox(height: 16),
            _PackCatalogueSection(maps: maps),
            const SizedBox(height: 16),
            MmSectionHeader(l.mapsLayers),
            const SizedBox(height: 6),
            if (maps.layers.isEmpty) ToolLine(l.mapsNoLayers, muted: true),
            for (final EventLayer e in maps.layers) _LayerRow(layer: e),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(l.mapsAddLayer),
                onPressed: () => _addLayer(context, maps),
              ),
            ),
            const SizedBox(height: 16),
            MmSectionHeader(l.mapsSources),
            const SizedBox(height: 6),
            for (final MapSource s in maps.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: MmListRow(
                  leading: Icon(
                      s.allowsPacks
                          ? Icons.download_done
                          : Icons.visibility_outlined,
                      color: skin.color.accent),
                  title: Text(s.name),
                  subtitle: Text(
                    s.allowsPacks
                        ? (s.coverage.isEmpty
                            ? l.mapsSourcePacks
                            : l.mapsSourcePacksUs)
                        : l.mapsSourceViewOnly,
                    style: TextStyle(color: skin.color.fgMuted, fontSize: 12),
                  ),
                  trailing: s.custom
                      ? IconButton(
                          tooltip: l.mapsDelete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirmDelete(context, s.name)) {
                              await maps.removeCustomSource(s);
                            }
                          },
                        )
                      : null,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l.mapsAddSource),
                onPressed: () => _addSource(context, maps),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final AppLocalizations l = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          content: Text(l.mapsDeleteConfirm(name)),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.mapsDelete)),
          ],
        ),
      ) ??
      false;
}

Future<int?> pickKeepDays(BuildContext context, int current) {
  final AppLocalizations l = AppLocalizations.of(context);
  return showDialog<int>(
    context: context,
    builder: (BuildContext ctx) => SimpleDialog(
      title: Text(l.mapsKeepFor),
      children: <Widget>[
        for (final int d in MapsController.keepChoicesDays)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, d),
            child: Row(children: <Widget>[
              Icon(d == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18),
              const SizedBox(width: 8),
              Text(keepLabel(l, d)),
            ]),
          ),
      ],
    ),
  );
}

enum _PackAction { pause, resume, update, keep, delete }

class _PackRow extends StatelessWidget {
  const _PackRow({required this.pack});
  final MapPack pack;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MapsController maps = context.read<MapsController>();
    final MmSkin skin = context.skin;
    final MapPack p = pack;
    final String src = maps.sourceById(p.sourceId)?.name ?? p.sourceId;
    final bool running = p.wantsWork;
    final TextStyle sub = TextStyle(color: skin.color.fgMuted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MmListRow(
        leading: Icon(
            p.state == PackState.complete
                ? Icons.download_done
                : Icons.downloading,
            color: p.state == PackState.overBudget
                ? skin.color.alert
                : skin.color.accent),
        title: Text(p.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l.mapsPackLine(src, p.minZoom, p.maxZoom), style: sub),
            Text(
              '${packStateLabel(l, p.state)} · '
              '${l.mapsProgress(p.done, p.total)} · '
              '${fmtBytes(maps.packBytes(p))}'
              '${p.missing > 0 ? ' · ${l.mapsMissing(p.missing)}' : ''}',
              style: sub,
            ),
            Text(expiryText(l, p.expiresAtMs), style: sub),
            if (p.state != PackState.complete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: p.progress),
              ),
          ],
        ),
        trailing: PopupMenuButton<_PackAction>(
          onSelected: (_PackAction a) async {
            switch (a) {
              case _PackAction.pause:
                maps.pausePack(p);
              case _PackAction.resume:
                maps.resumePack(p);
              case _PackAction.update:
                maps.updatePack(p);
              case _PackAction.keep:
                final int? d = await pickKeepDays(context, p.keepDays);
                if (d != null) maps.setPackKeep(p, d);
              case _PackAction.delete:
                if (await confirmDelete(context, p.name)) {
                  await maps.deletePack(p);
                }
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<_PackAction>>[
            if (running)
              PopupMenuItem<_PackAction>(
                  value: _PackAction.pause, child: Text(l.mapsPause))
            else if (p.state != PackState.complete)
              PopupMenuItem<_PackAction>(
                  value: _PackAction.resume, child: Text(l.mapsResume)),
            PopupMenuItem<_PackAction>(
                value: _PackAction.update, child: Text(l.mapsUpdate)),
            PopupMenuItem<_PackAction>(
                value: _PackAction.keep, child: Text(l.mapsKeepFor)),
            PopupMenuItem<_PackAction>(
                value: _PackAction.delete, child: Text(l.mapsDelete)),
          ],
        ),
      ),
    );
  }
}

enum _LayerAction { refresh, keep, delete }

class _LayerRow extends StatelessWidget {
  const _LayerRow({required this.layer});
  final EventLayer layer;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MapsController maps = context.read<MapsController>();
    final MmSkin skin = context.skin;
    final EventLayer e = layer;
    final TextStyle sub = TextStyle(color: skin.color.fgMuted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MmListRow(
        leading: Switch(
          value: e.visible,
          onChanged: (bool v) => maps.setLayerVisible(e, v),
        ),
        title: Text(e.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(Uri.parse(e.url).host, style: sub),
            Text('${l.mapsLayerFeatures(e.features)} · ${fmtBytes(e.bytes)}',
                style: sub),
            Text(expiryText(l, e.expiresAtMs), style: sub),
          ],
        ),
        trailing: PopupMenuButton<_LayerAction>(
          onSelected: (_LayerAction a) async {
            switch (a) {
              case _LayerAction.refresh:
                final LayerRefusal? why = await maps.refreshLayer(e);
                if (why != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(layerRefusalText(l, why))));
                }
              case _LayerAction.keep:
                final int? d = await pickKeepDays(context, e.keepDays);
                if (d != null) maps.setLayerKeep(e, d);
              case _LayerAction.delete:
                if (await confirmDelete(context, e.name)) {
                  await maps.deleteLayer(e);
                }
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<_LayerAction>>[
            PopupMenuItem<_LayerAction>(
                value: _LayerAction.refresh, child: Text(l.mapsRedownload)),
            PopupMenuItem<_LayerAction>(
                value: _LayerAction.keep, child: Text(l.mapsKeepFor)),
            PopupMenuItem<_LayerAction>(
                value: _LayerAction.delete, child: Text(l.mapsDelete)),
          ],
        ),
      ),
    );
  }
}

Future<void> _addLayer(BuildContext context, MapsController maps) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => _AddLayerDialog(maps: maps),
  );
}

class _AddLayerDialog extends StatefulWidget {
  const _AddLayerDialog({required this.maps});
  final MapsController maps;

  @override
  State<_AddLayerDialog> createState() => _AddLayerDialogState();
}

class _AddLayerDialogState extends State<_AddLayerDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();
  int _keep = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final LayerRefusal? why = await widget.maps
        .addLayer(name: _name.text, url: _url.text, keepDays: _keep);
    if (!mounted) return;
    if (why == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = layerRefusalText(l, why);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.mapsAddLayer),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l.mapsLayerName)),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                  labelText: l.mapsLayerUrl,
                  hintText: 'https://…/streets.geojson'),
            ),
            const SizedBox(height: 8),
            ToolField(
              label: l.newPackKeep,
              child: ToolChoice<int>(
                value: _keep,
                values: MapsController.keepChoicesDays,
                label: (int d) => keepLabel(l, d),
                enabled: !_busy,
                onChanged: (int d) => setState(() => _keep = d),
              ),
            ),
            const SizedBox(height: 8),
            Text(l.mapsLayerTerms, style: const TextStyle(fontSize: 12)),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              ToolNotice(text: _error!, icon: Icons.error_outline),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.cancel)),
        FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? l.mapsWorking : l.mapsAdd)),
      ],
    );
  }
}

Future<void> _addSource(BuildContext context, MapsController maps) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => _AddSourceDialog(maps: maps),
  );
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog({required this.maps});
  final MapsController maps;

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _attr = TextEditingController();
  bool _packs = false;
  bool _bad = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _attr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.mapsAddSource),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l.mapsSourceName)),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                  labelText: l.mapsSourceUrl,
                  hintText: 'https://tiles.example.org/{z}/{x}/{y}.png'),
            ),
            TextField(
                controller: _attr,
                decoration: InputDecoration(labelText: l.mapsSourceAttr)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _packs,
              onChanged: (bool? v) => setState(() => _packs = v ?? false),
              title: Text(l.mapsSourceAllowsPacks,
                  style: const TextStyle(fontSize: 13)),
            ),
            if (_bad) ToolNotice(text: l.mapsSourceBad, icon: Icons.error_outline),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          onPressed: () {
            final MapSource? s = widget.maps.addCustomSource(
              name: _name.text,
              urlTemplate: _url.text,
              attribution: _attr.text,
              allowsPacks: _packs,
            );
            if (s == null) {
              setState(() => _bad = true);
            } else {
              Navigator.pop(context);
            }
          },
          child: Text(l.mapsAdd),
        ),
      ],
    );
  }
}

/// R84 — the pack list plus what is already installed.
///
/// The list is read once per visit: the bundle always, and a published list
/// when this build was pointed at one. A pack is one PMTiles file from a host
/// that permits it, so the row shows the licence and the attribution the data
/// requires before anyone taps Download.
class _PackCatalogueSection extends StatefulWidget {
  const _PackCatalogueSection({required this.maps});

  final MapsController maps;

  @override
  State<_PackCatalogueSection> createState() => _PackCatalogueSectionState();
}

class _PackCatalogueSectionState extends State<_PackCatalogueSection> {
  @override
  void initState() {
    super.initState();
    if (widget.maps.catalog == null && !widget.maps.catalogLoading) {
      unawaited(widget.maps.refreshCatalog());
    }
  }

  Future<void> _install(CatalogPack pack) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final ArchiveRefusal? why = await widget.maps.addArchive(
      name: pack.name,
      url: pack.url,
      expectedBytes: pack.bytes <= 0 ? null : pack.bytes,
      sha256: pack.sha256,
    );
    if (!mounted) return;
    if (why != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(archiveRefusalText(l, why))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MapsController maps = widget.maps;
    final PackCatalog? catalog = maps.catalog;
    final String source = maps.catalogUrl.isEmpty
        ? l.mapsPacksBundle
        : Uri.tryParse(maps.catalogUrl)?.host ?? maps.catalogUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MmSectionHeader(l.mapsPacksPublished),
        const SizedBox(height: 6),
        if (catalog == null || maps.catalogLoading)
          ToolLine(l.mapsPacksBundle, muted: true)
        else ...<Widget>[
          ToolLine(l.mapsPacksFrom(source), muted: true),
          if (catalog.remoteProblem != null) ...<Widget>[
            const SizedBox(height: 4),
            ToolLine(l.mapsPacksUnreadable, muted: true),
          ],
          const SizedBox(height: 4),
          if (catalog.isEmpty)
            ToolLine(l.mapsPacksEmpty, muted: true)
          else
            for (final CatalogPack p in catalog.packs)
              _CatalogRow(pack: p, onInstall: () => _install(p)),
        ],
        const SizedBox(height: 12),
        MmSectionHeader(l.mapsArchives),
        const SizedBox(height: 6),
        if (maps.archives.isEmpty)
          ToolLine(l.mapsNoArchives, muted: true),
        for (final MapArchive a in maps.archives) _ArchiveRow(archive: a),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.mapsWifiOnly),
          subtitle: Text(l.mapsWifiOnlyHint),
          value: maps.wifiOnlyArchives,
          onChanged: maps.setWifiOnlyArchives,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.folder_zip_outlined),
            label: Text(l.mapsAddArchive),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext ctx) => _AddArchiveDialog(maps: maps),
            ),
          ),
        ),
      ],
    );
  }
}

/// One pack a host has published, with the terms it carries.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.pack, required this.onInstall});

  final CatalogPack pack;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: skin.space.pad(3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(pack.summary, style: TextStyle(color: cs.onSurface)),
                Text(
                  l.mapsPackLicence(pack.licence, pack.attribution),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: .6),
                    fontSize: skin.type.sizeSm,
                  ),
                ),
                if (pack.description.isNotEmpty)
                  Text(
                    pack.description,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: .6),
                      fontSize: skin.type.sizeSm,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onInstall,
            child: Text(l.mapsPackInstall),
          ),
        ],
      ),
    );
  }
}

enum _ArchiveAction { pause, resume, keep, delete }

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({required this.archive});
  final MapArchive archive;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MapsController maps = context.read<MapsController>();
    final MmSkin skin = context.skin;
    final MapArchive a = archive;
    final TextStyle sub = TextStyle(color: skin.color.fgMuted, fontSize: 12);
    final int have = maps.archiveBytesOf(a);
    final bool active = a.state == ArchiveState.downloading ||
        a.state == ArchiveState.waitingForNetwork;
    final double? progress = a.expectedBytes == null || a.expectedBytes == 0
        ? null
        : (have / a.expectedBytes!).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MmListRow(
        leading: Icon(
            a.complete ? Icons.download_done : Icons.downloading,
            color: a.state == ArchiveState.failed ||
                    a.state == ArchiveState.overBudget
                ? skin.color.alert
                : skin.color.accent),
        title: Text(a.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${archiveStateLabel(l, a.state)} · '
              '${fmtBytes(have)}'
              '${a.expectedBytes != null && !a.complete ? ' / ${fmtBytes(a.expectedBytes!)}' : ''}',
              style: sub,
            ),
            if (a.failure != null)
              Text(archiveFailureText(l, a.failure!), style: sub),
            if (a.complete) Text(expiryText(l, a.expiresAtMs), style: sub),
            if (active)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: progress),
              ),
          ],
        ),
        trailing: PopupMenuButton<_ArchiveAction>(
          onSelected: (_ArchiveAction act) async {
            switch (act) {
              case _ArchiveAction.pause:
                maps.pauseArchive(a);
              case _ArchiveAction.resume:
                maps.resumeArchive(a);
              case _ArchiveAction.keep:
                final int? d = await pickKeepDays(context, a.keepDays);
                if (d != null) maps.setArchiveKeep(a, d);
              case _ArchiveAction.delete:
                if (await confirmDelete(context, a.name)) {
                  await maps.deleteArchive(a);
                }
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<_ArchiveAction>>[
            if (active)
              PopupMenuItem<_ArchiveAction>(
                  value: _ArchiveAction.pause, child: Text(l.mapsPause))
            else if (a.state == ArchiveState.paused ||
                a.state == ArchiveState.overBudget)
              PopupMenuItem<_ArchiveAction>(
                  value: _ArchiveAction.resume, child: Text(l.mapsResume)),
            if (a.complete)
              PopupMenuItem<_ArchiveAction>(
                  value: _ArchiveAction.keep, child: Text(l.mapsKeepFor)),
            PopupMenuItem<_ArchiveAction>(
                value: _ArchiveAction.delete, child: Text(l.mapsDelete)),
          ],
        ),
      ),
    );
  }
}

class _AddArchiveDialog extends StatefulWidget {
  const _AddArchiveDialog({required this.maps});
  final MapsController maps;

  @override
  State<_AddArchiveDialog> createState() => _AddArchiveDialogState();
}

class _AddArchiveDialogState extends State<_AddArchiveDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _mb = TextEditingController();
  final TextEditingController _sha = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _mb.dispose();
    _sha.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final double? mb = double.tryParse(_mb.text.trim());
    final String sha = _sha.text.trim();
    final ArchiveRefusal? why = await widget.maps.addArchive(
      name: _name.text,
      url: _url.text,
      expectedBytes: mb == null ? null : (mb * 1000 * 1000).round(),
      sha256: sha.isEmpty ? null : sha,
    );
    if (!mounted) return;
    if (why == null) {
      Navigator.pop(context);
    } else {
      setState(() => _error = archiveRefusalText(l, why));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.mapsAddArchive),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l.mapsLayerName)),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                  labelText: l.archiveUrl, hintText: 'https://…/region.pmtiles'),
            ),
            TextField(
              controller: _mb,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.archiveSize),
            ),
            TextField(
              controller: _sha,
              decoration: InputDecoration(labelText: l.archiveSha),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              ToolNotice(text: _error!, icon: Icons.error_outline),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _submit, child: Text(l.mapsAdd)),
      ],
    );
  }
}
