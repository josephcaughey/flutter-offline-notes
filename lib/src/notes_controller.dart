import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'note.dart';
import 'note_store.dart';
import 'sync/notes_api.dart';
import 'sync/sync_engine.dart';

sealed class SyncStatus {
  const SyncStatus();
}

final class NeverSynced extends SyncStatus {
  const NeverSynced();
}

final class Syncing extends SyncStatus {
  const Syncing();
}

final class Synced extends SyncStatus {
  const Synced(this.at);
  final DateTime at;
}

final class SyncFailed extends SyncStatus {
  const SyncFailed(this.message, {this.retryAt});
  final String message;

  /// When the next automatic attempt is due, or null if it won't retry.
  final DateTime? retryAt;
}

/// How long to wait before retry number [attempt]: 1 s, 2 s, 4 s and so on,
/// capped at a minute.
Duration retryDelay(int attempt) =>
    Duration(seconds: min(60, 1 << min(attempt - 1, 6)));

/// Everything the UI needs: the notes, edits that save immediately, and
/// sync that runs shortly after each edit and retries with backoff when the
/// server can't be reached.
class NotesController extends ChangeNotifier {
  NotesController({
    required NoteStore store,
    required NotesApi api,
    DateTime Function()? now,
    this.debounce = const Duration(milliseconds: 800),
  }) : _store = store,
       _now = now ?? DateTime.now {
    _engine = SyncEngine(api: api, store: store, now: _now);
  }

  final NoteStore _store;
  final DateTime Function() _now;
  final Duration debounce;
  late final SyncEngine _engine;

  SyncStatus _status = const NeverSynced();
  Timer? _timer;
  int _failures = 0;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  SyncStatus get status => _status;

  /// Problem with saved data found on startup, if any.
  String? get loadProblem => _store.loadProblem;

  /// Visible notes, most recently edited first.
  List<Note> get notes =>
      _store.all.where((n) => !n.deleted).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  int get pendingCount => _store.all.where((n) => n.isDirty).length;

  Note? operator [](String id) => _store[id];

  Future<Note> create() async {
    final note = Note.create(now: _now());
    await _change(note);
    return note;
  }

  Future<void> edit(String id, {String? title, String? body}) async {
    final note = _store[id];
    if (note == null ||
        (note.title == (title ?? note.title) &&
            note.body == (body ?? note.body))) {
      return;
    }
    await _change(note.edited(title: title, body: body, now: _now()));
  }

  Future<void> delete(String id) async {
    final note = _store[id];
    if (note == null || note.deleted) return;
    await _change(note.edited(deleted: true, now: _now()));
  }

  /// Syncs now. If a round is already running, another follows it, so an
  /// edit made mid-sync is never left behind.
  Future<void> syncNow() async {
    _timer?.cancel();
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _setStatus(const Syncing());
    try {
      await _engine.run();
      _failures = 0;
      _setStatus(Synced(_now()));
    } on SyncException catch (e) {
      if (e.retryable) {
        _failures++;
        final delay = retryDelay(_failures);
        _setStatus(SyncFailed(e.message, retryAt: _now().add(delay)));
        _schedule(delay);
      } else {
        _setStatus(SyncFailed(e.message));
      }
    } finally {
      _running = false;
    }
    if (_again && !_disposed) {
      _again = false;
      await syncNow();
    }
  }

  Future<void> _change(Note note) async {
    _store.put(note);
    notifyListeners();
    await _store.save();
    // Replaces any pending retry. Typing resets the timer, so an offline
    // device tries once per pause rather than once per keystroke.
    _schedule(debounce);
  }

  void _schedule(Duration delay) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(syncNow()));
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
