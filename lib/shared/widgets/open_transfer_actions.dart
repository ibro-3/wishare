import 'package:material_ui/material_ui.dart';

import '../../core/models/transfer.dart';
import '../../core/platform/reveal.dart';
import '../../core/theme/wishare_type.dart';

/// Actions for a completed incoming transfer: reveal the saved folder and,
/// when there is exactly one file, open it in the system's default app.
class OpenTransferActions extends StatelessWidget {
  const OpenTransferActions({required this.transfer, super.key});

  final Transfer transfer;

  @override
  Widget build(BuildContext context) {
    final directory = transfer.saveDirectory;
    if (directory == null ||
        directory.isEmpty ||
        transfer.direction != TransferDirection.incoming ||
        transfer.status != TransferStatus.completed) {
      return const SizedBox.shrink();
    }
    final files = transfer.files.where((entry) => !entry.isDirectory).toList();
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _open(
            context,
            () => RevealInFolder.openFolder(directory),
            directory,
          ),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Open folder'),
        ),
        if (files.length == 1)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              textStyle: context.emphasizedText.labelLarge,
            ),
            onPressed: () async {
              final path = await RevealInFolder.resolveSavedFile(
                directory,
                files.first.relativePath,
              );
              if (!context.mounted) return;
              await _open(context, () => RevealInFolder.openFile(path), path);
            },
            icon: const Icon(Icons.open_in_new),
            label: Text('Open file', style: context.emphasizedText.labelLarge),
          ),
      ],
    );
  }

  Future<void> _open(
    BuildContext context,
    Future<bool> Function() action,
    String path,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await action();
    if (!opened && context.mounted) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open $path')));
    }
  }
}
