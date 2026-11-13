import '../note.dart';

/// The two calls the sync engine needs from a server.
abstract interface class NotesApi {
  /// Stores [note] if the server's copy is still at [baseRevision] (null for
  /// a note the server has never seen). Otherwise reports the server's
  /// current copy.
  Future<PushResult> push(RemoteNote note, {required int? baseRevision});

  /// Every note changed after revision [cursor], with the cursor to use next.
  Future<PullResult> pull({required int cursor});
}

sealed class PushResult {
  const PushResult();
}

final class Accepted extends PushResult {
  const Accepted(this.revision);
  final int revision;
}

final class Conflict extends PushResult {
  const Conflict(this.current);
  final RemoteNote current;
}

class PullResult {
  const PullResult(this.changes, this.cursor);
  final List<RemoteNote> changes;
  final int cursor;
}

/// The server couldn't be reached or failed. [retryable] is false for
/// errors that will fail the same way again, such as a rejected request.
class SyncException implements Exception {
  const SyncException(this.message, {this.retryable = true});
  final String message;
  final bool retryable;

  @override
  String toString() => 'SyncException: $message';
}
