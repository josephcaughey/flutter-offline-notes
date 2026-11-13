import '../note.dart';
import '../note_store.dart';
import 'notes_api.dart';

class SyncReport {
  const SyncReport({this.pushed = 0, this.pulled = 0, this.conflicts = 0});
  final int pushed;
  final int pulled;
  final int conflicts;
}

/// One round of sync: push local changes, then pull everyone else's.
///
/// Conflicts are resolved without losing text. When the server has moved
/// past the revision a local edit was based on, the server's version keeps
/// the note's place and the local text is saved as a new
/// "(conflict copy)" note, which is pushed on the next round. A local
/// delete that conflicts with a remote edit gives way to the edit.
class SyncEngine {
  SyncEngine({required this.api, required this.store, required this.now});

  final NotesApi api;
  final NoteStore store;
  final DateTime Function() now;

  /// Runs a round. Throws [SyncException] if the server can't be reached;
  /// anything already pushed stays recorded as pushed.
  Future<SyncReport> run() async {
    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;

    final outbox = store.all.where((n) => n.isDirty).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    try {
      for (final sent in outbox) {
        final result = await api.push(
          sent.toRemote(),
          baseRevision: sent.revision,
        );
        // The note may have been edited while the request was in flight.
        final current = store[sent.id] ?? sent;
        switch (result) {
          case Accepted(:final revision):
            store.put(
              current.accepted(revision: revision, version: sent.localVersion),
            );
            pushed++;
          case Conflict(current: final remote):
            conflicts++;
            final differs =
                current.title != remote.title || current.body != remote.body;
            if (!current.deleted && !remote.deleted && differs) {
              store.put(
                Note.create(
                  now: now(),
                  title:
                      '${current.title.isEmpty ? 'Untitled' : current.title} (conflict copy)',
                  body: current.body,
                ),
              );
            }
            store.put(Note.fromRemote(remote));
        }
      }

      final pull = await api.pull(cursor: store.cursor);
      for (final remote in pull.changes) {
        final local = store[remote.id];
        // Unpushed local edits are left alone; the next push will compare
        // them with this revision and resolve any conflict then.
        if (local != null && local.isDirty) continue;
        if (local != null && (local.revision ?? 0) >= remote.revision) continue;
        store.put(Note.fromRemote(remote));
        pulled++;
      }
      store.cursor = pull.cursor;
    } finally {
      await store.save();
    }
    return SyncReport(pushed: pushed, pulled: pulled, conflicts: conflicts);
  }
}
