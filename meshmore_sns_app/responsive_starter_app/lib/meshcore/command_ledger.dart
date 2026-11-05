// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// The reply a command waits for.
///
/// The companion firmware does not answer every command the same way: a
/// channel text and a raw-data send get a bare `OK`/`ERR`, while an
/// addressed DM and the tool requests get `RESP_CODE_SENT` carrying a tag
/// and an estimated timeout. Neither answer carries a correlation tag, so
/// the only thing that says which command a reply belongs to is the order
/// the commands were sent in.
enum CommandAnswer { ok, sent }

/// One command waiting for its answer.
class CommandEntry {
  const CommandEntry({
    required this.id,
    required this.answer,
    required this.sequence,
  });

  /// Caller's identifier for the command: a message id, or one of the
  /// controller's markers for a command that is not a chat message.
  final String id;

  final CommandAnswer answer;

  /// Registration order. Ordering is the whole mechanism, so it is recorded
  /// rather than inferred from list position.
  final int sequence;
}

/// Who a bare `OK`/`ERR`/`SENT` belongs to.
///
/// The reply kind is the only filter the wire offers: a `SENT` can never
/// answer a channel text, an `OK` can never answer a DM. Within one kind the
/// oldest waiting command is the only candidate, because the radio answers
/// in the order commands reached it. What the earlier bookkeeping lacked was
/// not a stricter order — the kind rule already made a swap impossible
/// across kinds — but an account of replies that matched nothing, which it
/// dropped in silence, and an error path that took the head regardless of
/// what the error was for. Both are fixed here: every reply either claims an
/// entry or is counted as unclaimed, and `RESP_CODE_ERR` takes the head
/// because an error does not say which command it refuses.
class CommandLedger {
  CommandLedger({
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long an entry may wait for its answer. Expired entries are dropped
  /// by [expire] so they cannot hold the head of the queue forever.
  final Duration timeout;

  final DateTime Function() _clock;
  final List<CommandEntry> _entries = <CommandEntry>[];
  final Map<int, DateTime> _deadlines = <int, DateTime>{};
  int _sequence = 0;
  int _unanswered = 0;
  int _unclaimed = 0;

  /// Entries that reached [timeout] without an answer.
  int get unanswered => _unanswered;

  /// Replies that arrived with nothing at the head to take them: an answer
  /// whose command had already timed out or been abandoned, a duplicate, or
  /// an answer to a command this app never registered.
  int get unclaimed => _unclaimed;

  int get pendingCount => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  /// Ids in the order they will be answered.
  List<String> get pendingIds =>
      List<String>.unmodifiable(_entries.map((CommandEntry e) => e.id));

  /// Whether [id] is still waiting.
  bool isPending(String id) => _entries.any((CommandEntry e) => e.id == id);

  /// Register [id] as waiting for [answer]. Duplicate registration is
  /// refused: two entries with one id cannot both be answered.
  CommandEntry register(String id, CommandAnswer answer) {
    if (isPending(id)) {
      throw StateError('command "$id" is already waiting for its answer');
    }
    final CommandEntry entry = CommandEntry(
      id: id,
      answer: answer,
      sequence: _sequence++,
    );
    _entries.add(entry);
    _deadlines[entry.sequence] = _clock().add(timeout);
    return entry;
  }

  /// Give up on [id] deliberately (the caller stopped caring). Not counted
  /// as [unanswered]: this is a decision, not a silence.
  bool drop(String id) {
    final int i = _entries.indexWhere((CommandEntry e) => e.id == id);
    if (i < 0) return false;
    _deadlines.remove(_entries.removeAt(i).sequence);
    return true;
  }

  /// Remove entries older than [timeout] and return their ids, oldest
  /// first, so the owner can fail whatever they stood for.
  List<String> expire() {
    if (_entries.isEmpty) return const <String>[];
    final DateTime now = _clock();
    final List<String> gone = <String>[];
    while (_entries.isNotEmpty) {
      final CommandEntry head = _entries.first;
      final DateTime? deadline = _deadlines[head.sequence];
      if (deadline == null || now.isBefore(deadline)) break;
      _entries.removeAt(0);
      _deadlines.remove(head.sequence);
      _unanswered++;
      gone.add(head.id);
    }
    return gone;
  }

  /// Take the answer for [answer]: the oldest entry waiting for that kind.
  ///
  /// Returns null, and counts an unclaimed reply, when no entry is waiting
  /// for that kind: a duplicate, a late answer to a command that timed out,
  /// or an answer to a command this app never registered. Those used to be
  /// credited to whatever happened to be waiting.
  CommandEntry? claim(CommandAnswer answer) {
    expire();
    final int i = _entries.indexWhere((CommandEntry e) => e.answer == answer);
    if (i < 0) {
      _unclaimed++;
      return null;
    }
    final CommandEntry entry = _entries.removeAt(i);
    _deadlines.remove(entry.sequence);
    return entry;
  }

  /// Take the head whatever kind it waits for.
  ///
  /// For `RESP_CODE_ERR`, which the firmware sends for any refused command:
  /// the error does not name its command either, so the head is the only
  /// candidate. Nothing waiting counts as an unclaimed reply.
  CommandEntry? takeHead() {
    expire();
    if (_entries.isEmpty) {
      _unclaimed++;
      return null;
    }
    final CommandEntry head = _entries.removeAt(0);
    _deadlines.remove(head.sequence);
    return head;
  }

  /// Forget everything (a new link: the radio has no memory of what this
  /// side was waiting for, so neither should the queue).
  void reset() {
    _entries.clear();
    _deadlines.clear();
  }
}
