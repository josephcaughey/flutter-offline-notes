import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_notes/src/note.dart';
import 'package:offline_notes/src/note_store.dart';
import 'package:offline_notes/src/sync/fake_notes_api.dart';
import 'package:offline_notes/src/sync/notes_api.dart';
import 'package:offline_notes/src/sync/sync_engine.dart';

import 'support.dart';

void main() {
  late FakeNotesApi server;
  late NoteStore store;
  late SyncEngine engine;
  final clock = TestClock();

  setUp(() async {
    useMemoryPrefs();
    server = FakeNotesApi();
    store = await memoryStore();
    engine = SyncEngine(api: server, store: store, now: clock.call);
  });

  Note add(String title, [String body = '']) {
    final note = Note.create(now: clock(), title: title, body: body);
    store.put(note);
    clock.advance();
    return note;
  }

  void edit(String id, {String? title, String? body, bool? deleted}) {
    store.put(
      store[id]!.edited(
        title: title,
        body: body,
        deleted: deleted,
        now: clock(),
      ),
    );
    clock.advance();
  }

  test('pushes new notes once and records their revisions', () async {
    final a = add('Groceries', 'eggs');
    final b = add('Ideas');

    final report = await engine.run();
    expect(report.pushed, 2);
    expect(store[a.id]!.isDirty, isFalse);
    expect(store[a.id]!.revision, server[a.id]!.revision);
    expect(server[b.id]!.title, 'Ideas');

    final again = await engine.run();
    expect(again.pushed, 0);
    expect(server.pushCount, 2);
  });

  test('pulls notes written by other devices', () async {
    server.write(id: 'x', title: 'From laptop', body: 'hi', updatedAt: clock());
    final report = await engine.run();
    expect(report.pulled, 1);
    expect(store['x']!.title, 'From laptop');
    expect(store['x']!.isDirty, isFalse);
    expect(store.cursor, server['x']!.revision);
  });

  test('does not pull back its own pushes', () async {
    add('Mine');
    final report = await engine.run();
    expect(report.pulled, 0);
  });

  test('an edit made while its push is in flight stays dirty', () async {
    final note = add('Draft');
    final api = InterceptingApi(server)
      ..beforeReply = (_) => edit(note.id, body: 'typed during the request');
    engine = SyncEngine(api: api, store: store, now: clock.call);

    await engine.run();
    expect(store[note.id]!.isDirty, isTrue);
    expect(store[note.id]!.body, 'typed during the request');

    api.beforeReply = null;
    await engine.run();
    expect(store[note.id]!.isDirty, isFalse);
    expect(server[note.id]!.body, 'typed during the request');
  });

  test('a conflicting edit keeps both versions', () async {
    final note = add('Plan', 'v1');
    await engine.run();

    server.write(
      id: note.id,
      title: 'Plan',
      body: 'edited on phone',
      updatedAt: clock(),
    );
    edit(note.id, body: 'edited on laptop');

    final report = await engine.run();
    expect(report.conflicts, 1);
    expect(store[note.id]!.body, 'edited on phone');
    expect(store[note.id]!.isDirty, isFalse);

    final copy = store.all.singleWhere(
      (n) => n.title == 'Plan (conflict copy)',
    );
    expect(copy.body, 'edited on laptop');
    expect(copy.isDirty, isTrue);

    await engine.run();
    expect(server[copy.id]!.body, 'edited on laptop');
  });

  test('identical concurrent edits do not make a copy', () async {
    final note = add('Same');
    await engine.run();
    server.write(id: note.id, title: 'Same', body: 'x', updatedAt: clock());
    edit(note.id, body: 'x');

    await engine.run();
    expect(store.all.length, 1);
  });

  test('a remote edit beats a local delete', () async {
    final note = add('Keep me', 'v1');
    await engine.run();
    server.write(id: note.id, title: 'Keep me', body: 'v2', updatedAt: clock());
    edit(note.id, deleted: true);

    await engine.run();
    expect(store[note.id]!.deleted, isFalse);
    expect(store[note.id]!.body, 'v2');
    expect(store.all.length, 1);
  });

  test('deletes travel both ways as tombstones', () async {
    final mine = add('Delete here');
    server.write(
      id: 'theirs',
      title: 'Delete there',
      body: '',
      updatedAt: clock(),
    );
    await engine.run();

    edit(mine.id, deleted: true);
    final theirs = server['theirs']!;
    server.write(
      id: theirs.id,
      title: theirs.title,
      body: theirs.body,
      updatedAt: clock(),
      deleted: true,
    );
    await engine.run();

    expect(server[mine.id]!.deleted, isTrue);
    expect(store['theirs']!.deleted, isTrue);
  });

  test('unpushed local edits are not overwritten by a pull', () async {
    final note = add('Local');
    await engine.run();
    final api = InterceptingApi(server)..failAfterPushes = 0;
    engine = SyncEngine(api: api, store: store, now: clock.call);
    edit(note.id, body: 'offline edit');

    await expectLater(engine.run(), throwsA(isA<SyncException>()));
    expect(store[note.id]!.body, 'offline edit');
    expect(store[note.id]!.isDirty, isTrue);
  });

  test('a dropped connection keeps what was already pushed', () async {
    final first = add('One');
    final second = add('Two');
    final api = InterceptingApi(server)..failAfterPushes = 1;
    engine = SyncEngine(api: api, store: store, now: clock.call);

    await expectLater(engine.run(), throwsA(isA<SyncException>()));
    expect(store[first.id]!.isDirty, isFalse);
    expect(store[second.id]!.isDirty, isTrue);

    final reloaded = await memoryStore();
    expect(
      reloaded[first.id]!.isDirty,
      isFalse,
      reason: 'progress is saved even when a round fails',
    );
  });

  test('notes and cursor survive a restart', () async {
    add('Persisted', 'body');
    server.write(id: 'remote', title: 'R', body: '', updatedAt: clock());
    await engine.run();

    final reloaded = await memoryStore();
    expect(reloaded.all.map((n) => n.title).toSet(), {'Persisted', 'R'});
    expect(reloaded.cursor, store.cursor);
  });

  test('two devices editing at random converge on the same notes', () async {
    final random = Random(7);
    final phone = await memoryStore(prefix: 'phone.');
    final laptop = await memoryStore(prefix: 'laptop.');
    final devices = [phone, laptop];
    final engines = [
      for (final device in devices)
        SyncEngine(api: server, store: device, now: clock.call),
    ];

    for (var step = 0; step < 300; step++) {
      final d = random.nextInt(2);
      final device = devices[d];
      final live = device.all.where((n) => !n.deleted).toList();
      switch (random.nextInt(10)) {
        case 0 || 1:
          device.put(
            Note.create(now: clock(), title: 'note $step', body: '$d'),
          );
        case 2 when live.isNotEmpty:
          final note = live[random.nextInt(live.length)];
          device.put(note.edited(deleted: true, now: clock()));
        case 3 || 4 || 5 when live.isNotEmpty:
          final note = live[random.nextInt(live.length)];
          device.put(note.edited(body: '${note.body} +$d', now: clock()));
        default:
          await engines[d].run();
      }
      clock.advance();
    }

    // Settle: each device syncs until neither has anything left to push.
    for (var round = 0; round < 4; round++) {
      for (final engine in engines) {
        await engine.run();
      }
    }

    Map<String, String> visible(
      Iterable<({String id, String title, String body, bool deleted})> notes,
    ) => {
      for (final n in notes.where((n) => !n.deleted))
        n.id: '${n.title}|${n.body}',
    };
    final expected = visible(
      server.notes.map(
        (n) => (id: n.id, title: n.title, body: n.body, deleted: n.deleted),
      ),
    );
    for (final device in devices) {
      expect(device.all.where((n) => n.isDirty), isEmpty);
      expect(
        visible(
          device.all.map(
            (n) => (id: n.id, title: n.title, body: n.body, deleted: n.deleted),
          ),
        ),
        expected,
      );
    }
    expect(expected.keys.length, greaterThan(10));
  });
}
