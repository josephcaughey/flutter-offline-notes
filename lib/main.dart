import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/note_store.dart';
import 'src/notes_controller.dart';
import 'src/sync/fake_notes_api.dart';
import 'src/sync/http_notes_api.dart';
import 'src/sync/notes_api.dart';
import 'src/ui/notes_page.dart';

/// Base URL of a server that speaks the protocol in the README. Without one
/// the app runs against an in-memory server with demo controls.
const _apiUrl = String.fromEnvironment('NOTES_API');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await NoteStore.load(SharedPreferencesAsync());

  FakeNotesApi? demoServer;
  final NotesApi api;
  if (_apiUrl.isEmpty) {
    demoServer = FakeNotesApi(latency: const Duration(milliseconds: 400));
    _seed(demoServer);
    api = demoServer;
  } else {
    api = HttpNotesApi(
      Uri.parse(_apiUrl.endsWith('/') ? _apiUrl : '$_apiUrl/'),
    );
  }

  final controller = NotesController(store: store, api: api);
  unawaited(controller.syncNow());
  runApp(NotesApp(controller: controller, demoServer: demoServer));
}

void _seed(FakeNotesApi server) {
  final now = DateTime.now();
  server
    ..write(
      id: 'welcome',
      title: 'Welcome',
      body: 'Notes are saved on the device first and synced in the background.',
      updatedAt: now,
    )
    ..write(
      id: 'try-offline',
      title: 'Try going offline',
      body: 'Use the menu to go offline, edit a few notes, then come back online.',
      updatedAt: now.subtract(const Duration(minutes: 1)),
    );
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key, required this.controller, this.demoServer});

  final NotesController controller;
  final FakeNotesApi? demoServer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Notes',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: NotesPage(controller: controller, demoServer: demoServer),
    );
  }
}
