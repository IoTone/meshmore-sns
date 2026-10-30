// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../gen/app_localizations.dart';
import '../meshcore/gateway/gateway_service.dart';
import '../ui/mm_scaffold.dart';

/// The text the QR encodes: the structured payload (endpoint, version, token)
/// when [port] is a real listening port, and otherwise the bare token, which
/// the phone reads as the default endpoint. Never throws: the screen must
/// render while the gateway is still coming up.
@visibleForTesting
String gatewayQrData(int port, Uint8List token) {
  if (port < 1 || port > 65535) {
    return token.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  return GatewayPairingPayload(port: port, token: token).encode();
}

/// Settings -> Connected apps: lets another app on this phone (LDMUX) use
/// the radio over the loopback gateway.
///
/// Shows the one secret the user must carry to the other app (the pairing
/// token) and nothing else sensitive: **no key material, no radio secrets**.
///
/// The QR carries a [GatewayPairingPayload]: the loopback endpoint, the
/// protocol version and the token. That is the L2 grant only. The other app's
/// end-to-end session keys come from its own pairing code and never pass
/// through MeshMore. The bare token stays selectable underneath for typing by
/// hand, and a bare-token code from an earlier build still parses.
class ConnectedAppsScreen extends StatefulWidget {
  const ConnectedAppsScreen({super.key});

  @override
  State<ConnectedAppsScreen> createState() => _ConnectedAppsScreenState();
}

class _ConnectedAppsScreenState extends State<ConnectedAppsScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Bound peer and airtime are read off the live gateway, which has no
    // change events, so refresh while this screen is open.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _hex(Uint8List b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

  Future<void> _revoke(BuildContext ctx, GatewayService svc) async {
    final AppLocalizations l = AppLocalizations.of(ctx);
    final bool? ok = await showDialog<bool>(
      context: ctx,
      builder: (BuildContext d) => AlertDialog(
        title: Text(l.connectedAppsRevokeTitle),
        content: Text(l.connectedAppsRevokeBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(l.connectedAppsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(l.connectedAppsRevokeConfirm),
          ),
        ],
      ),
    );
    if (ok == true) await svc.revokePairing();
  }

  String _stateText(AppLocalizations l, GatewayService svc) =>
      switch (svc.status) {
        GatewayRunState.off => l.connectedAppsStateOff,
        GatewayRunState.waitingForRadio => l.connectedAppsStateWaiting,
        GatewayRunState.running => l.connectedAppsStateRunning(svc.port),
        GatewayRunState.failed => l.connectedAppsStateFailed(svc.error ?? ''),
      };

  @override
  Widget build(BuildContext context) {
    final GatewayService svc = context.watch<GatewayService>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Uint8List? token = svc.pairingToken;
    final String? tokenHex = token == null ? null : _hex(token);
    final TextStyle muted =
        TextStyle(color: cs.onSurface.withValues(alpha: .6));
    return Scaffold(
      appBar: AppBar(title: Text(l.connectedAppsTitle)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SwitchListTile(
              key: const Key('gateway-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.connectedAppsSwitch),
              subtitle: Text(
                _stateText(l, svc),
                key: const Key('gateway-state'),
                style: svc.status == GatewayRunState.failed
                    ? TextStyle(color: cs.error)
                    : muted,
              ),
              value: svc.enabled,
              onChanged: (bool v) => svc.setEnabled(v),
            ),
            // Airtime is a policy, not a property of the link (§5.5b). The
            // default keeps the voluntary 1 % duty cycle; the other mode says
            // the channel is ours. Stated as the consequence, not as a gadget.
            SwitchListTile(
              key: const Key('airtime-policy'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.connectedAppsAirtimeTitle),
              subtitle: Text(
                svc.airtimePolicy == AirtimePolicy.ownedChannel
                    ? l.connectedAppsAirtimeOwned
                    : l.connectedAppsAirtimeDutyCycle,
                key: const Key('airtime-policy-state'),
                style: muted,
              ),
              value: svc.airtimePolicy == AirtimePolicy.ownedChannel,
              onChanged: (bool v) => svc.setAirtimePolicy(v
                  ? AirtimePolicy.ownedChannel
                  : AirtimePolicy.onePercentDutyCycle),
            ),
            if (tokenHex != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(l.connectedAppsToken,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(l.connectedAppsTokenHelp, style: muted),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    key: const Key('gateway-token-qr'),
                    data: gatewayQrData(svc.port, token!),
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                tokenHex,
                key: const Key('gateway-token-text'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.connectedAppsPeer),
                subtitle: Text(
                  svc.boundPeer == null
                      ? l.connectedAppsNoPeer
                      : (svc.boundPeerName ?? _hex(svc.boundPeer!)),
                  key: const Key('gateway-peer'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l.connectedAppsAirtime(
                    (svc.airtimeUsed.inMilliseconds / 1000).toStringAsFixed(1),
                    (svc.airtimeBudget.inMilliseconds / 1000)
                        .toStringAsFixed(0),
                  ),
                  key: const Key('gateway-airtime'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('gateway-revoke'),
                onPressed: () => _revoke(context, svc),
                child: Text(l.connectedAppsRevoke),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
