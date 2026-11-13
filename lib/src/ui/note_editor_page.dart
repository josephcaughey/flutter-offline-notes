import 'package:flutter/material.dart';

import '../notes_controller.dart';

/// Edits one note. Every keystroke is saved locally, so there's no save
/// button and nothing to lose by leaving.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    required this.controller,
    required this.noteId,
  });

  final NotesController controller;
  final String noteId;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    final note = widget.controller[widget.noteId];
    _title = TextEditingController(text: note?.title ?? '');
    _body = TextEditingController(text: note?.body ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await widget.controller.delete(widget.noteId);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            TextField(
              key: const Key('title'),
              controller: _title,
              autofocus: _title.text.isEmpty,
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
              onChanged: (value) =>
                  widget.controller.edit(widget.noteId, title: value),
            ),
            Expanded(
              child: TextField(
                key: const Key('body'),
                controller: _body,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Write something',
                  border: InputBorder.none,
                ),
                onChanged: (value) =>
                    widget.controller.edit(widget.noteId, body: value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
