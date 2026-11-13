import 'package:flutter/material.dart';

import '../note.dart';
import '../notes_controller.dart';
import '../sync/fake_notes_api.dart';
import 'note_editor_page.dart';
import 'sync_banner.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key, required this.controller, this.demoServer});

  final NotesController controller;

  /// Set in the demo build, to offer the offline and conflict switches.
  final FakeNotesApi? demoServer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final notes = controller.notes;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notes'),
            actions: [
              if (demoServer case final server?)
                _DemoMenu(server: server, controller: controller),
            ],
          ),
          body: Column(
            children: [
              SyncBanner(controller: controller),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: controller.syncNow,
                  child: notes.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No notes yet. Tap + to write one.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: notes.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => _NoteTile(
                            note: notes[index],
                            controller: controller,
                          ),
                        ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'New note',
            onPressed: () async {
              final note = await controller.create();
              if (context.mounted) await _open(context, note.id);
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context, String id) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteEditorPage(controller: controller, noteId: id),
        ),
      );
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.controller});

  final Note note;
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final preview = note.body.split('\n').first;
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => controller.delete(note.id),
      child: ListTile(
        title: Text(
          note.title.isEmpty ? 'Untitled' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: preview.isEmpty
            ? null
            : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: note.isDirty
            ? const Icon(
                Icons.cloud_upload_outlined,
                semanticLabel: 'Not synced yet',
              )
            : null,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NoteEditorPage(controller: controller, noteId: note.id),
          ),
        ),
      ),
    );
  }
}

class _DemoMenu extends StatefulWidget {
  const _DemoMenu({required this.server, required this.controller});

  final FakeNotesApi server;
  final NotesController controller;

  @override
  State<_DemoMenu> createState() => _DemoMenuState();
}

class _DemoMenuState extends State<_DemoMenu> {
  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    return PopupMenuButton<String>(
      tooltip: 'Demo controls',
      onSelected: (choice) {
        switch (choice) {
          case 'network':
            setState(() => server.offline = !server.offline);
            if (!server.offline) widget.controller.syncNow();
          case 'remote':
            _editElsewhere();
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'network',
          checked: server.offline,
          child: const Text('Offline'),
        ),
        const PopupMenuItem(
          value: 'remote',
          child: Text('Edit the top note on another device'),
        ),
      ],
    );
  }

  void _editElsewhere() {
    final notes = widget.controller.notes;
    final remote = notes.isEmpty ? null : widget.server[notes.first.id];
    final messenger = ScaffoldMessenger.of(context);
    if (remote == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sync the top note first.')),
      );
      return;
    }
    widget.server.write(
      id: remote.id,
      title: remote.title,
      body: '${remote.body}\nEdited on another device.',
      updatedAt: DateTime.now(),
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Changed on the server. Edit it here too to see a conflict.',
        ),
      ),
    );
  }
}
