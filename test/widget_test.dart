import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_notes/main.dart';
import 'package:offline_notes/src/notes_controller.dart';
import 'package:offline_notes/src/sync/fake_notes_api.dart';

import 'support.dart';

void main() {
  late FakeNotesApi server;
  late NotesController controller;

  setUp(() async {
    useMemoryPrefs();
    server = FakeNotesApi()
      ..write(
        id: 'w',
        title: 'Welcome',
        body: 'First line\nSecond',
        updatedAt: DateTime.utc(2026),
      );
    controller = NotesController(store: await memoryStore(), api: server);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      NotesApp(controller: controller, demoServer: server),
    );
    await tester.runAsync(controller.syncNow);
    await tester.pump();
  }

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('sync-status'))).data!;

  testWidgets('shows synced notes', (tester) async {
    await pumpApp(tester);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(status(tester), 'All changes synced');
  });

  testWidgets('a new note is saved locally and then synced', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title')), 'Shopping');
    await tester.enterText(find.byKey(const Key('body')), 'milk');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Shopping'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsWidgets);

    await tester.runAsync(controller.syncNow);
    await tester.pump();
    expect(server.notes.map((n) => n.title), contains('Shopping'));
    expect(status(tester), 'All changes synced');
  });

  testWidgets('offline edits are counted and kept', (tester) async {
    await pumpApp(tester);
    server.offline = true;
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title')), 'Welcome back');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.runAsync(controller.syncNow);
    await tester.pump();
    expect(
      status(tester),
      'The network is unavailable. · 1 change waiting · retrying soon',
    );
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('swiping deletes a note', (tester) async {
    await pumpApp(tester);
    await tester.drag(find.text('Welcome'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsNothing);
    expect(find.text('No notes yet. Tap + to write one.'), findsOneWidget);

    await tester.runAsync(controller.syncNow);
    expect(server['w']!.deleted, isTrue);
  });
}
