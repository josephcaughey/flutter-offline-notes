import 'package:flutter/material.dart';

import '../notes_controller.dart';

/// One line saying whether the notes on this device are safely on the
/// server.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.controller});

  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = controller.pendingCount;
    final waiting = pending == 0
        ? ''
        : ' · $pending ${pending == 1 ? 'change' : 'changes'} waiting';

    final (icon, text, color) = switch (controller.status) {
      NeverSynced() => (
        Icons.cloud_queue,
        'Not synced yet$waiting',
        scheme.surfaceContainerHighest,
      ),
      Syncing() => (Icons.sync, 'Syncing…', scheme.surfaceContainerHighest),
      Synced() when pending > 0 => (
        Icons.cloud_upload_outlined,
        'Saved on this device$waiting',
        scheme.surfaceContainerHighest,
      ),
      Synced() => (
        Icons.cloud_done_outlined,
        'All changes synced',
        scheme.surfaceContainerHighest,
      ),
      SyncFailed(:final message, :final retryAt) => (
        Icons.cloud_off,
        '$message$waiting${retryAt == null ? '' : ' · retrying soon'}',
        scheme.errorContainer,
      ),
    };

    final loadProblem = controller.loadProblem;
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(text, key: const Key('sync-status'))),
              ],
            ),
            if (loadProblem != null)
              Text(loadProblem, style: TextStyle(color: scheme.error)),
          ],
        ),
      ),
    );
  }
}
