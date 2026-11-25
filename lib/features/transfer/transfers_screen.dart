import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/transfer.dart';
import '../../core/state/providers.dart';
import '../../core/theme/wishare_type.dart';
import '../../shared/format.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(transfersProvider).value ?? const <Transfer>[];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final twoPane = MediaQuery.sizeOf(context).width >= 840;

    Transfer? selected;
    for (final transfer in transfers) {
      if (transfer.id == _selectedId) selected = transfer;
    }
    selected ??= transfers.isEmpty ? null : transfers.first;

    if (twoPane) {
      return Row(
        children: [
          SizedBox(
            width: 360,
            child: _list(context, transfers, text, scheme, ref, (transfer) {
              setState(() => _selectedId = transfer.id);
            }),
          ),
          VerticalDivider(width: 1, color: scheme.outlineVariant),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      'Select a transfer to see its details',
                      style: text.bodySmall,
                    ),
                  )
                : TransferDetail(transfer: selected, ref: ref),
          ),
        ],
      );
    }

    return _list(context, transfers, text, scheme, ref, (transfer) {
      _showDetailSheet(context, transfer);
    });
  }

  Widget _list(
    BuildContext context,
    List<Transfer> transfers,
    TextTheme text,
    ColorScheme scheme,
    WidgetRef ref,
    void Function(Transfer) onSelected,
  ) {
    if (transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No transfers yet', style: text.titleMedium),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: transfers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final transfer = transfers[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: transfer.direction == TransferDirection.incoming
                  ? scheme.tertiaryContainer
                  : scheme.primaryContainer,
              foregroundColor: transfer.direction == TransferDirection.incoming
                  ? scheme.onTertiaryContainer
                  : scheme.onPrimaryContainer,
              child: Icon(
                transfer.direction == TransferDirection.incoming
                    ? Icons.download
                    : Icons.upload,
              ),
            ),
            title: Text(
              transfer.peerName,
              style: text.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${transfer.files.length} items · ${formatSize(transfer.totalBytes)}',
                  style: text.bodySmall,
                ),
                if (transfer.isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      label: 'Transfer progress',
                      value: '${(transfer.progress * 100).round()} percent',
                      child: LinearProgressIndicator(value: transfer.progress),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusChip(context, transfer, scheme, text),
                if (transfer.isActive)
                  IconButton(
                    tooltip: 'Cancel transfer',
                    icon: const Icon(Icons.close),
                    onPressed: () => confirmCancel(context, ref, transfer),
                  ),
              ],
            ),
            onTap: () => onSelected(transfer),
          ),
        );
      },
    );
  }

  Widget _statusChip(
    BuildContext context,
    Transfer transfer,
    ColorScheme scheme,
    TextTheme text,
  ) {
    final (
      String label,
      Color background,
      Color foreground,
    ) = switch (transfer.status) {
      TransferStatus.completed => (
        'Done',
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TransferStatus.failed => (
        'Failed',
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      TransferStatus.declined || TransferStatus.cancelled => (
        'Stopped',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      _ => ('Active', scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Semantics(
        label: 'Status: $label',
        child: Text(
          label,
          style: context.emphasizedText.labelSmall?.copyWith(color: foreground),
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, Transfer transfer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => TransferDetail(
          transfer: transfer,
          ref: ref,
          controller: controller,
        ),
      ),
    );
  }
}

Future<void> confirmCancel(
  BuildContext context,
  WidgetRef ref,
  Transfer transfer,
) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel transfer?'),
      content: Text(
        'The transfer to ${transfer.peerName} will stop and any partially '
        'received files will be discarded.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep going'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Cancel transfer'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await ref.read(networkProvider.notifier).cancelTransfer(transfer);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Transfer cancelled')));
  }
}

class TransferDetail extends StatelessWidget {
  const TransferDetail({
    required this.transfer,
    required this.ref,
    this.controller,
    super.key,
  });

  final Transfer transfer;
  final WidgetRef ref;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Transfer details', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${transfer.peerName} · ${formatSize(transfer.totalBytes)}',
            style: text.bodySmall,
          ),
          if (transfer.isActive) ...[
            const SizedBox(height: 16),
            Semantics(
              label: 'Transfer progress',
              value: '${(transfer.progress * 100).round()} percent',
              child: LinearProgressIndicator(value: transfer.progress),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => confirmCancel(context, ref, transfer),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel transfer'),
            ),
          ],
          if (transfer.error != null) ...[
            const SizedBox(height: 16),
            Text(
              transfer.error!,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          for (final file in transfer.files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                file.isDirectory
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(file.relativePath, style: text.bodyMedium),
              trailing: file.isDirectory
                  ? null
                  : Text(formatSize(file.size), style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}
