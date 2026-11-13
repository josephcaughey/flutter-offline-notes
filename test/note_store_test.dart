import 'package:flutter_test/flutter_test.dart';
import 'package:offline_notes/src/note.dart';
import 'package:offline_notes/src/note_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  setUp(useMemoryPrefs);

  test('round-trips notes and cursor', () async {
    final store = await memoryStore();
    final note =
        Note.create(
              now: DateTime.utc(2026, 1, 2, 3, 4, 5),
              title: 'T',
              body: 'B',
            )
            .accepted(revision: 4, version: 1)
            .edited(body: 'B2', now: DateTime.utc(2026, 1, 3));
    store
      ..put(note)
      ..cursor = 9;
    await store.save();

    final reloaded = await memoryStore();
    expect(reloaded[note.id], note);
    expect(reloaded.cursor, 9);
    expect(reloaded.loadProblem, isNull);
  });

  test('unreadable data is kept aside rather than overwritten', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(NoteStore.notesKey, '{not json');
    await prefs.setInt(NoteStore.cursorKey, 12);

    final store = await memoryStore();
    expect(store.all, isEmpty);
    expect(store.cursor, 0);
    expect(store.loadProblem, contains(NoteStore.unreadableKey));
    expect(await prefs.getString(NoteStore.unreadableKey), '{not json');

    store.put(Note.create(now: DateTime.utc(2026)));
    await store.save();
    expect(await prefs.getString(NoteStore.unreadableKey), '{not json');
  });

  test('prefixes keep stores apart', () async {
    final a = await memoryStore(prefix: 'a.');
    a.put(Note.create(now: DateTime.utc(2026), title: 'only in a'));
    await a.save();
    expect((await memoryStore(prefix: 'b.')).all, isEmpty);
    expect((await memoryStore(prefix: 'a.')).all.single.title, 'only in a');
  });

  test('ids are version 4 UUIDs', () {
    final ids = List.generate(200, (_) => newId());
    expect(ids.toSet().length, 200);
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });
}
