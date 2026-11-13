import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'note.dart';

/// Every note on the device plus the sync cursor, saved to
/// SharedPreferences so it works the same on mobile and the web.
class NoteStore {
  NoteStore._(
    this._prefs,
    this._prefix,
    this._notes,
    this.cursor,
    this.loadProblem,
  );

  /// Reads the saved notes. Data that can't be decoded is copied to
  /// [unreadableKey] before starting empty, so the next save doesn't
  /// destroy it.
  ///
  /// Keys start with [prefix], which keeps separate stores apart, such as
  /// one per account.
  static Future<NoteStore> load(
    SharedPreferencesAsync prefs, {
    String prefix = '',
  }) async {
    final raw = await prefs.getString('$prefix$notesKey');
    final cursor = await prefs.getInt('$prefix$cursorKey') ?? 0;
    if (raw == null) return NoteStore._(prefs, prefix, {}, 0, null);
    try {
      final list = (jsonDecode(raw) as List<Object?>).map(
        (item) => Note.fromJson(item! as Map<String, Object?>),
      );
      return NoteStore._(
        prefs,
        prefix,
        {for (final note in list) note.id: note},
        cursor,
        null,
      );
    } on Object {
      await prefs.setString('$prefix$unreadableKey', raw);
      await prefs.remove('$prefix$cursorKey');
      return NoteStore._(
        prefs,
        prefix,
        {},
        0,
        'Saved notes could not be read. A copy was kept under "$unreadableKey".',
      );
    }
  }

  static const notesKey = 'notes.v1';
  static const cursorKey = 'notes.cursor';
  static const unreadableKey = 'notes.v1.unreadable';

  final SharedPreferencesAsync _prefs;
  final String _prefix;
  final Map<String, Note> _notes;

  /// Set when saved data had to be set aside on load.
  final String? loadProblem;

  /// The server revision the device has pulled up to.
  int cursor;

  Iterable<Note> get all => _notes.values;

  Note? operator [](String id) => _notes[id];

  void put(Note note) => _notes[note.id] = note;

  Future<void> save() async {
    final encoded = jsonEncode([
      for (final note in _notes.values) note.toJson(),
    ]);
    await _prefs.setString('$_prefix$notesKey', encoded);
    await _prefs.setInt('$_prefix$cursorKey', cursor);
  }
}
