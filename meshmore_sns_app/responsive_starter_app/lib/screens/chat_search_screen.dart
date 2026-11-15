// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/block_filter.dart';
import '../meshcore/block_store.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/chat_store.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/message_heat.dart' show parseChannelSenderName;
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';
import '../util/clock_model.dart';
import 'delivery_status_icon.dart';

/// APP-E6 — search over the messages this device stored.
///
/// There is no radio index and no plaintext index beside the sealed history,
/// so this reads the list the controller already holds and never builds one.
/// It runs through the same [BlockFilter] as every other surface, counts the
/// hits a block removed instead of hiding them in silence, and says when
/// retention or the display cap bounded the answer.
///
/// Tapping a hit pops with the message id; the chat screen decides what
/// "open" means there (switch channel, reveal the row, or push the DM thread),
/// because that is where the thread lives.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final TextEditingController _input = TextEditingController();

  /// The filter is built once. A block store that is absent (a harness with
  /// no blocks) filters nothing, which is exactly what an empty list does.
  late final BlockFilter _filter = BlockFilter(
    context.read<BlockStore?>() ?? BlockStore(),
  );

  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Every message the controller holds, one entry per row.
  ///
  /// Messages are bucketed per channel index, and a channel index is created
  /// by the first frame that names it, so walking the known channels reaches
  /// every stored row, direct messages included (they carry the channel that
  /// was active when they arrived).
  List<ChatMessage> _history(MeshcoreController mc) {
    final List<ChatMessage> all = <ChatMessage>[];
    for (final MapEntry<int, String> ch in mc.channels) {
      all.addAll(mc.messagesFor(ch.key));
    }
    return all;
  }

  String _threadName(MeshcoreController mc, ChatMessage m) {
    if (m.peerPubKeyHex != null) {
      return AppLocalizations.of(context).chatSearchDm;
    }
    for (final MapEntry<int, String> ch in mc.channels) {
      if (ch.key == m.channelIdx) return ch.value;
    }
    return 'CH ${m.channelIdx}';
  }

  /// The name a row shows: our own name for a row we sent, the fabric's name
  /// for a keyed DM, and the text's own `name: ` prefix on a channel.
  String _sender(MeshcoreController mc, ChatMessage m) {
    if (m.peerPubKeyHex != null) return _nameForKey(mc, m.peerPubKeyHex!);
    if (m.outgoing) return mc.selfInfo?.name ?? '';
    return parseChannelSenderName(m.text) ?? '';
  }

  /// The fabric's name for a key, by full key or the 12-hex prefix a legacy
  /// frame carries, else the key's own short form so the row is never blank.
  String _nameForKey(MeshcoreController mc, String key) {
    for (final DiscoveredNode n in mc.nodes) {
      if (n.pubKeyHex == key || n.pubKeyHex.startsWith(key)) {
        return n.name.isEmpty ? n.shortId : n.name;
      }
    }
    return key.length >= 12 ? key.substring(0, 12) : key;
  }

  /// The body without the `sender: ` prefix, so a row does not repeat the
  /// name the sender line already carries.
  String _body(ChatMessage m) {
    if (m.outgoing) return m.text;
    final int i = m.text.indexOf(': ');
    if (i <= 0 || i > 32) return m.text;
    return m.text.substring(i + 2);
  }

  void _open(ChatMessage m) => Navigator.of(context).pop<String>(m.id);

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MessageSearchResult r =
        MessageSearch.run(_history(mc), _query, filter: _filter);

    return Scaffold(
      appBar: AppBar(title: Text(l.chatSearchAction)),
      body: MmScaffold(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                skin.space.step(4),
                skin.space.step(3),
                skin.space.step(4),
                skin.space.step(2),
              ),
              child: TextField(
                controller: _input,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (String v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.chatSearchHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            _SearchNotes(result: r, query: _query.trim()),
            Expanded(
              child: r.hits.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(skin.space.step(6)),
                        child: Text(
                          _query.trim().isEmpty
                              ? l.chatSearchPrompt
                              : l.chatSearchNoResults(_query.trim()),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: skin.type.sizeBody,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: r.hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext ctx, int i) {
                        final ChatMessage m = r.hits[i];
                        return _HitRow(
                          message: m,
                          sender: _sender(mc, m),
                          thread: _threadName(mc, m),
                          body: _body(m),
                          onTap: () => _open(m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lines a search owes the reader: what a block hid, whether the display
/// cap cut the list, and whether retention bounds what exists at all.
class _SearchNotes extends StatelessWidget {
  const _SearchNotes({required this.result, required this.query});

  final MessageSearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    // One line above the answer, highest priority first, and the rest behind
    // one info tap: three stacked sentences of meta made the notes louder
    // than the results they described.
    final List<String> lines = <String>[
      if (result.truncated) l.chatSearchTruncated(result.hits.length),
      if (query.isNotEmpty && result.hiddenCount > 0)
        l.chatSearchHidden(result.hiddenCount),
      if (query.isNotEmpty && result.boundedByRetention)
        l.chatSearchRetention(ChatStore.cap),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    final List<String> rest = lines.skip(1).toList();
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: EdgeInsets.symmetric(
        horizontal: skin.space.step(4),
        vertical: skin.space.step(2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              lines.first,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: skin.type.sizeSm,
              ),
            ),
          ),
          if (rest.isNotEmpty)
            Tooltip(
              message: rest.join('\n'),
              child: Icon(Icons.info_outline,
                  size: skin.type.sizeSm, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// One hit: who said it, where, when, and what it said.
class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.message,
    required this.sender,
    required this.thread,
    required this.body,
    required this.onTap,
  });

  final ChatMessage message;
  final String sender;
  final String thread;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MessageDelivery? delivery = message.delivery;
    return ListTile(
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
      title: Text(
        body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: skin.type.sizeBody, color: cs.onSurface),
      ),
      subtitle: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              sender.isEmpty ? thread : '$sender · $thread',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: skin.type.sizeSm,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '  ·  ${clockStamp(l, message.at)}',
            style: TextStyle(
              fontSize: skin.type.sizeSm,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (delivery != null) ...<Widget>[
            SizedBox(width: skin.space.step(1)),
            DeliveryStatusIcon(delivery, size: skin.type.sizeSm),
          ],
        ],
      ),
    );
  }
}
