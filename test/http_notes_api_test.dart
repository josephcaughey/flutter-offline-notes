import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_notes/src/note.dart';
import 'package:offline_notes/src/sync/http_notes_api.dart';
import 'package:offline_notes/src/sync/notes_api.dart';

void main() {
  final base = Uri.parse('https://notes.example/api/');
  final note = RemoteNote(
    id: 'a b',
    title: 'Title',
    body: 'Body',
    updatedAt: DateTime.utc(2026, 5, 1),
    deleted: false,
    revision: 0,
  );
  final serverCopy = {...note.toJson(), 'title': 'Theirs', 'revision': 8};

  HttpNotesApi api(Future<http.Response> Function(http.Request) handler) =>
      HttpNotesApi(
        base,
        client: MockClient(handler),
        timeout: const Duration(milliseconds: 50),
      );

  test('push sends the note with its base revision', () async {
    late http.Request seen;
    final result = await api((request) async {
      seen = request;
      return http.Response(jsonEncode({'revision': 7}), 200);
    }).push(note, baseRevision: 3);

    expect(seen.method, 'PUT');
    expect(seen.url.toString(), 'https://notes.example/api/notes/a%20b');
    expect(seen.headers['Content-Type'], startsWith('application/json'));
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect(body['baseRevision'], 3);
    expect(body.containsKey('revision'), isFalse);
    expect(body['title'], 'Title');
    expect((result as Accepted).revision, 7);
  });

  test('a 409 is a conflict carrying the server copy', () async {
    final result = await api(
      (_) async => http.Response(jsonEncode({'current': serverCopy}), 409),
    ).push(note, baseRevision: null);
    final conflict = result as Conflict;
    expect(conflict.current.title, 'Theirs');
    expect(conflict.current.revision, 8);
  });

  test('pull asks for changes since the cursor', () async {
    late Uri url;
    final result = await api((request) async {
      url = request.url;
      return http.Response(
        jsonEncode({
          'changes': [serverCopy],
          'cursor': 8,
        }),
        200,
      );
    }).pull(cursor: 5);
    expect(url.toString(), 'https://notes.example/api/notes?since=5');
    expect(result.cursor, 8);
    expect(result.changes.single.id, 'a b');
  });

  test('server errors and timeouts can be retried', () async {
    for (final status in [500, 503, 429, 408]) {
      final error = await _error(
        api((_) async => http.Response('', status)).pull(cursor: 0),
      );
      expect(error.retryable, isTrue, reason: '$status');
    }
    final slow = api((_) => Completer<http.Response>().future);
    expect((await _error(slow.pull(cursor: 0))).retryable, isTrue);
    final unreachable = api(
      (_) async => throw http.ClientException('connection refused'),
    );
    expect(
      (await _error(unreachable.pull(cursor: 0))).message,
      contains('connection refused'),
    );
  });

  test('client errors and bad JSON are not retried', () async {
    expect(
      (await _error(
        api((_) async => http.Response('', 400)).pull(cursor: 0),
      )).retryable,
      isFalse,
    );
    expect(
      (await _error(
        api((_) async => http.Response('', 401)).pull(cursor: 0),
      )).retryable,
      isFalse,
    );
    expect(
      (await _error(
        api((_) async => http.Response('<html>', 200)).pull(cursor: 0),
      )).retryable,
      isFalse,
    );
  });
}

Future<SyncException> _error(Future<Object?> call) async {
  try {
    await call;
  } on SyncException catch (e) {
    return e;
  }
  fail('expected a SyncException');
}
