import '../note.dart';
import 'notes_api.dart';

/// An in-memory server for tests and the demo build. It follows the same
/// rules a real server would, and can be switched offline or edited "from
/// another device" to show what the sync engine does about it.
class FakeNotesApi implements NotesApi {
  FakeNotesApi({this.latency = Duration.zero});

  final Duration latency;
  final Map<String, RemoteNote> _notes = {};
  int _revision = 0;

  /// While true every call fails as if the network were down.
  bool offline = false;

  int pushCount = 0;

  Iterable<RemoteNote> get notes => _notes.values;

  RemoteNote? operator [](String id) => _notes[id];

  /// Writes a note directly, as another client would.
  RemoteNote write({
    required String id,
    required String title,
    required String body,
    required DateTime updatedAt,
    bool deleted = false,
  }) {
    final note = RemoteNote(
      id: id,
      title: title,
      body: body,
      updatedAt: updatedAt,
      deleted: deleted,
      revision: ++_revision,
    );
    _notes[id] = note;
    return note;
  }

  @override
  Future<PushResult> push(RemoteNote note, {required int? baseRevision}) async {
    await _network();
    pushCount++;
    final existing = _notes[note.id];
    if (existing?.revision != baseRevision) {
      // Either the server has moved on, or the client claims a base for a
      // note that doesn't exist here.
      if (existing != null) return Conflict(existing);
      throw const SyncException('Unknown note.', retryable: false);
    }
    final stored = note.withRevision(++_revision);
    _notes[note.id] = stored;
    return Accepted(stored.revision);
  }

  @override
  Future<PullResult> pull({required int cursor}) async {
    await _network();
    final changes = _notes.values.where((n) => n.revision > cursor).toList()
      ..sort((a, b) => a.revision.compareTo(b.revision));
    return PullResult(changes, _revision);
  }

  Future<void> _network() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (offline) throw const SyncException('The network is unavailable.');
  }
}
