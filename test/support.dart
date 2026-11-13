import 'package:offline_notes/src/note.dart';
import 'package:offline_notes/src/note_store.dart';
import 'package:offline_notes/src/sync/notes_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Points SharedPreferences at a fresh in-memory backend.
void useMemoryPrefs() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
}

Future<NoteStore> memoryStore({String prefix = ''}) =>
    NoteStore.load(SharedPreferencesAsync(), prefix: prefix);

/// A clock that only moves when told to.
class TestClock {
  DateTime value = DateTime.utc(2026, 3, 1, 9);
  DateTime call() => value;
  void advance([Duration by = const Duration(seconds: 1)]) =>
      value = value.add(by);
}

/// Wraps an API to run [beforeReply] while a push is in flight, as if the
/// user kept typing while waiting on the network.
class InterceptingApi implements NotesApi {
  InterceptingApi(this.inner);

  final NotesApi inner;
  void Function(RemoteNote sent)? beforeReply;
  int failAfterPushes = -1;
  int _pushes = 0;

  @override
  Future<PushResult> push(RemoteNote note, {required int? baseRevision}) async {
    if (failAfterPushes >= 0 && _pushes >= failAfterPushes) {
      throw const SyncException('Connection dropped.');
    }
    _pushes++;
    final result = await inner.push(note, baseRevision: baseRevision);
    beforeReply?.call(note);
    return result;
  }

  @override
  Future<PullResult> pull({required int cursor}) => inner.pull(cursor: cursor);
}
