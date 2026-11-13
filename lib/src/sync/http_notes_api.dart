import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../note.dart';
import 'notes_api.dart';

/// [NotesApi] over HTTP. The protocol is described in the README:
///
/// - `GET  {base}/notes?since={cursor}` returns `{"changes": [...], "cursor": n}`
/// - `PUT  {base}/notes/{id}` with the note and `baseRevision` returns
///   `{"revision": n}`, or `409` with `{"current": note}` when the base is stale
class HttpNotesApi implements NotesApi {
  HttpNotesApi(
    this.baseUrl, {
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<PushResult> push(RemoteNote note, {required int? baseRevision}) async {
    final body = {...note.toJson(), 'baseRevision': baseRevision}
      ..remove('revision');
    final response = await _send(
      () => _client.put(
        baseUrl.resolve('notes/${Uri.encodeComponent(note.id)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    final json = _decode(response);
    return switch (response.statusCode) {
      200 || 201 => Accepted(json['revision']! as int),
      409 => Conflict(
        RemoteNote.fromJson(json['current']! as Map<String, Object?>),
      ),
      _ => throw StateError('unreachable'),
    };
  }

  @override
  Future<PullResult> pull({required int cursor}) async {
    final response = await _send(
      () => _client.get(baseUrl.resolve('notes?since=$cursor')),
    );
    final json = _decode(response);
    final changes = (json['changes']! as List<Object?>)
        .map((item) => RemoteNote.fromJson(item! as Map<String, Object?>))
        .toList();
    return PullResult(changes, json['cursor']! as int);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const SyncException('The server took too long to respond.');
    } on http.ClientException catch (e) {
      throw SyncException('Could not reach the server: ${e.message}');
    }
    final status = response.statusCode;
    if (status == 200 || status == 201 || status == 409) return response;
    // Server errors and throttling may clear up; other client errors won't.
    final retryable = status >= 500 || status == 408 || status == 429;
    throw SyncException('The server returned $status.', retryable: retryable);
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, Object?>;
    } on Object {
      throw const SyncException(
        'The server sent a response that is not valid JSON.',
        retryable: false,
      );
    }
  }
}
