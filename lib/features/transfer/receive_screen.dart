import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/transfer.dart';
import '../../core/state/providers.dart';
import '../../core/theme/wishare_type.dart';
import '../../shared/format.dart';
import 'transfers_screen.dart' show confirmCancel;

class ReceiveScreen extends ConsumerWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersProvider).value ?? const <Transfer>[];
    final pending = transfers
        .where((transfer) => transfer.status == TransferStatus.offered)
        .toList();
    final active = transfers.where((transfer) {
      return transfer.direction == TransferDirection.incoming &&
          transfer.isActive &&
          transfer.status != TransferStatus.offered;
    }).toList();

    if (pending.isEmpty && active.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Nothing to receive yet',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Incoming transfers from paired devices will appear here. '
                'You decide whether to accept each one.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListView(
      key: const PageStorageKey<String>('receive'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        if (pending.isNotEmpty) ...[
          Text('Waiting for your approval', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final transfer in pending)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.tertiaryContainer,
                          foregroundColor: scheme.onTertiaryContainer,
                          child: const Icon(Icons.download),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'From ${transfer.peerName}',
                            style: text.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${transfer.files.length} items · ${formatSize(transfer.totalBytes)}',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => ref
                              .read(networkProvider.notifier)
                              .declineTransfer(transfer.id),
                          child: const Text('Decline'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            textStyle: context.emphasizedText.labelLarge,
                          ),
                          onPressed: () => ref
                              .read(networkProvider.notifier)
                              .acceptTransfer(
                                transfer.id,
                                ref
                                        .read(settingsProvider)
                                        .value
                                        ?.downloadDirectory ??
                                    '',
                              ),
                          child: const Text('Accept'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (active.isNotEmpty) ...[
          Text('Receiving now', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final transfer in active)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                  child: const Icon(Icons.download),
                ),
                title: Text(transfer.peerName, style: text.titleMedium),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      '${(transfer.progress * 100).toStringAsFixed(0)}% · '
                      '${formatSize(transfer.transferredBytes)} of '
                      '${formatSize(transfer.totalBytes)}',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      label: 'Transfer progress',
                      value: '${(transfer.progress * 100).round()} percent',
                      child: LinearProgressIndicator(value: transfer.progress),
                    ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: 'Cancel transfer',
                  icon: const Icon(Icons.close),
                  onPressed: () => confirmCancel(context, ref, transfer),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
