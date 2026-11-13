import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_notes/src/note_store.dart';
import 'package:offline_notes/src/notes_controller.dart';
import 'package:offline_notes/src/sync/fake_notes_api.dart';
import 'package:offline_notes/src/sync/notes_api.dart';

import 'support.dart';

void main() {
  late FakeNotesApi server;
  late NoteStore store;

  setUp(() async {
    useMemoryPrefs();
    server = FakeNotesApi();
    store = await memoryStore();
  });

  test('retry delays double up to a minute', () {
    expect(
      [for (var i = 1; i <= 9; i++) retryDelay(i).inSeconds],
      [1, 2, 4, 8, 16, 32, 60, 60, 60],
    );
  });

  test('edits sync after a pause in typing', () {
    fakeAsync((async) {
      final controller = NotesController(store: store, api: server);
      controller.create().then((note) async {
        await controller.edit(note.id, title: 'H');
        await controller.edit(note.id, title: 'He');
        await controller.edit(note.id, title: 'Hello');
      });
      async.elapse(const Duration(milliseconds: 700));
      expect(server.pushCount, 0);
      expect(controller.pendingCount, 1);

      async.elapse(const Duration(milliseconds: 200));
      expect(server.pushCount, 1);
      expect(server.notes.single.title, 'Hello');
      expect(controller.pendingCount, 0);
      expect(controller.status, isA<Synced>());
      controller.dispose();
    });
  });

  test('offline sync backs off, then recovers', () {
    fakeAsync((async) {
      server.offline = true;
      final controller = NotesController(store: store, api: server);
      controller.create();
      async.elapse(const Duration(seconds: 1));
      expect(controller.status, isA<SyncFailed>());
      expect((controller.status as SyncFailed).retryAt, isNotNull);

      // The first attempt is at 0.8 s; retries follow 1, 2, 4 and 8 s
      // after each failure, so the fifth attempt is at 15.8 s.
      async.elapse(const Duration(seconds: 7));
      expect(controller.status, isA<SyncFailed>());

      server.offline = false;
      async.elapse(const Duration(seconds: 7));
      expect(
        controller.status,
        isA<SyncFailed>(),
        reason: 'still waiting out the 8 s backoff',
      );
      async.elapse(const Duration(seconds: 1));
      expect(controller.status, isA<Synced>());
      expect(controller.pendingCount, 0);
      expect(server.notes, hasLength(1));
      controller.dispose();
    });
  });

  test('an edit during a sync gets a sync of its own', () {
    fakeAsync((async) {
      final slow = FakeNotesApi(latency: const Duration(seconds: 2));
      final controller = NotesController(store: store, api: slow);
      late String id;
      controller.create().then((note) => id = note.id);
      async.elapse(const Duration(seconds: 1));
      expect(controller.status, isA<Syncing>());

      controller.edit(id, body: 'mid-sync');
      controller.syncNow();
      async.elapse(const Duration(seconds: 10));
      expect(slow[id]!.body, 'mid-sync');
      expect(controller.pendingCount, 0);
      controller.dispose();
    });
  });

  test('deleted notes disappear from the list but still sync', () {
    fakeAsync((async) {
      final controller = NotesController(store: store, api: server);
      late String id;
      controller.create().then((note) => id = note.id);
      async.elapse(const Duration(seconds: 1));
      controller.delete(id);
      expect(controller.notes, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(server[id]!.deleted, isTrue);
      controller.dispose();
    });
  });

  test('a rejected request is not retried', () {
    fakeAsync((async) {
      final controller = NotesController(store: store, api: _Rejecting());
      controller.syncNow();
      async.flushMicrotasks();
      final status = controller.status as SyncFailed;
      expect(status.retryAt, isNull);
      expect(async.pendingTimers, isEmpty);
      controller.dispose();
    });
  });
}

class _Rejecting extends FakeNotesApi {
  @override
  Future<PullResult> pull({required int cursor}) async =>
      throw const SyncException('The server returned 401.', retryable: false);
}
