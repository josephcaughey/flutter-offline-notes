import 'dart:math';

import 'package:flutter/foundation.dart';

/// A note as the device knows it.
///
/// [localVersion] goes up on every local edit and [syncedVersion] records the
/// last local version the server accepted, so a note is dirty when they
/// differ. [revision] is the server revision this copy is based on, or null
/// if the server has never seen it.
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.deleted = false,
    this.revision,
    this.localVersion = 0,
    this.syncedVersion = 0,
  });

  /// A new note that only exists on this device.
  factory Note.create({
    required DateTime now,
    String title = '',
    String body = '',
  }) => Note(
    id: newId(),
    title: title,
    body: body,
    updatedAt: now,
    localVersion: 1,
  );

  /// The server's copy, with nothing waiting to be pushed.
  factory Note.fromRemote(RemoteNote remote) => Note(
    id: remote.id,
    title: remote.title,
    body: remote.body,
    updatedAt: remote.updatedAt,
    deleted: remote.deleted,
    revision: remote.revision,
  );

  factory Note.fromJson(Map<String, Object?> json) => Note(
    id: json['id']! as String,
    title: json['title']! as String,
    body: json['body']! as String,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    deleted: json['deleted']! as bool,
    revision: json['revision'] as int?,
    localVersion: json['localVersion']! as int,
    syncedVersion: json['syncedVersion']! as int,
  );

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  /// Deleted notes are kept as tombstones so the deletion can be synced.
  final bool deleted;
  final int? revision;
  final int localVersion;
  final int syncedVersion;

  bool get isDirty => localVersion != syncedVersion;

  /// A local change: new content, a fresh timestamp and a bumped version.
  Note edited({
    String? title,
    String? body,
    bool? deleted,
    required DateTime now,
  }) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    updatedAt: now,
    deleted: deleted ?? this.deleted,
    revision: revision,
    localVersion: localVersion + 1,
    syncedVersion: syncedVersion,
  );

  /// Records that the server accepted [version] as [revision].
  Note accepted({required int revision, required int version}) => Note(
    id: id,
    title: title,
    body: body,
    updatedAt: updatedAt,
    deleted: deleted,
    revision: revision,
    localVersion: localVersion,
    syncedVersion: version,
  );

  RemoteNote toRemote() => RemoteNote(
    id: id,
    title: title,
    body: body,
    updatedAt: updatedAt,
    deleted: deleted,
    revision: revision ?? 0,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
    'revision': revision,
    'localVersion': localVersion,
    'syncedVersion': syncedVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted &&
      other.revision == revision &&
      other.localVersion == localVersion &&
      other.syncedVersion == syncedVersion;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    updatedAt,
    deleted,
    revision,
    localVersion,
    syncedVersion,
  );

  @override
  String toString() =>
      'Note($id, "$title", rev $revision, v$localVersion/$syncedVersion'
      '${deleted ? ', deleted' : ''})';
}

/// A note as the server stores it.
@immutable
class RemoteNote {
  const RemoteNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    required this.deleted,
    required this.revision,
  });

  factory RemoteNote.fromJson(Map<String, Object?> json) => RemoteNote(
    id: json['id']! as String,
    title: json['title']! as String,
    body: json['body']! as String,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    deleted: json['deleted']! as bool,
    revision: json['revision']! as int,
  );

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;
  final bool deleted;
  final int revision;

  RemoteNote withRevision(int revision) => RemoteNote(
    id: id,
    title: title,
    body: body,
    updatedAt: updatedAt,
    deleted: deleted,
    revision: revision,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
    'revision': revision,
  };
}

final _random = Random.secure();

/// A random version 4 UUID, generated on the device so notes can be created
/// offline without asking the server for an id.
String newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
