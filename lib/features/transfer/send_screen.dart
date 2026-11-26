import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/crypto/certificate_manager.dart';
import '../../core/models/peer.dart';
import '../../core/models/transfer.dart';
import '../../core/network/transfer_coordinator.dart';
import '../../core/network/wishare_client.dart';
import '../../core/platform/share_intent.dart';
import '../../core/state/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets/directional_icon.dart';

class SendScreen extends ConsumerStatefulWidget {
  // The router passes this in; looking up GoRouterState.of(context) from
  // initState is illegal (it depends on the modal scope before mount).
  const SendScreen({this.peerId, super.key});

  final String? peerId;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _selected = <SelectedEntry>[];
  String? _requestedPeerId;
  bool _busy = false;
  double _progress = 0;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    // peersProvider is usually still AsyncLoading here, so only remember the
    // requested id and resolve it against the paired list in build().
    _requestedPeerId = widget.peerId;
    for (final path in ShareIntents.takePending()) {
      if (!File(path).existsSync()) continue;
      _selected.add(
        SelectedEntry(
          relativePath: path.split(Platform.pathSeparator).last,
          absolutePath: path,
          size: File(path).lengthSync(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];
    // A device the caller asked for (for example via a share shortcut) is
    // listed first; every paired device is tappable to send the selection.
    final paired = peers.where((peer) => peer.isPaired).toList()
      ..sort(
        (a, b) => (a.id == _requestedPeerId ? 0 : 1).compareTo(
          b.id == _requestedPeerId ? 0 : 1,
        ),
      );
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = _selected.fold<int>(0, (sum, entry) => sum + entry.size);

    final nearby = peers.where((peer) => !peer.isPaired).toList();
    return SingleChildScrollView(
      // Leave room for the navigation bar and the pairing FAB above it.
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send to', style: text.titleMedium),
          const SizedBox(height: 8),
          if (paired.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No paired devices yet. Pair a device first.',
                  style: text.bodySmall,
                ),
              ),
            )
          else
            for (final peer in paired)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: const Icon(Icons.devices_other),
                  ),
                  title: Text(peer.name, style: text.titleMedium),
                  subtitle: Text(peer.endpoint, style: text.bodySmall),
                  // Tapping the device is the send action: no separate button.
                  trailing: const WiDirectionalIcon(Icons.send),
                  onTap: _busy ? null : () => _choose(peer),
                ),
              ),
          if (nearby.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Nearby devices', style: text.titleSmall),
            const SizedBox(height: 8),
            for (final peer in nearby.take(4))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: const Icon(Icons.devices_other),
                ),
                title: Text(peer.name, style: text.bodyMedium),
                subtitle: Text(peer.address, style: text.bodySmall),
                trailing: OutlinedButton(
                  onPressed: () => context.go(
                    '/scan?host=${peer.address}&port=${peer.port}',
                  ),
                  child: const Text('Pair'),
                ),
              ),
          ],
          const SizedBox(height: 24),
          Text('Files and folders', style: text.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Files'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Folder'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selected.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Nothing selected yet',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final entry in _selected.take(12))
                    ListTile(
                      leading: Icon(
                        entry.isDirectory
                            ? Icons.folder
                            : Icons.insert_drive_file_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        entry.relativePath,
                        style: text.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: entry.isDirectory
                          ? null
                          : Text(formatSize(entry.size), style: text.bodySmall),
                    ),
                  if (_selected.length > 12)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '+ ${_selected.length - 12} more',
                        style: text.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text('Total: ${formatSize(total)}', style: text.labelLarge),
          if (_progress > 0) ...[
            const SizedBox(height: 20),
            Semantics(
              label: 'Sending progress',
              value: '${(_progress * 100).round()} percent',
              child: LinearProgressIndicator(value: _progress),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%'
              '${_status == null ? '' : ' · $_status'}',
              style: text.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
          if (_selected.isNotEmpty && !_busy) ...[
            const SizedBox(height: 12),
            Text(
              'Tap a device above to send these items',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty || !mounted) return;
    setState(() {
      for (final file in files) {
        if (file.path == null) continue;
        _selected.add(
          SelectedEntry(
            relativePath: file.name,
            absolutePath: file.path!,
            size: file.lengthSync() ?? 0,
          ),
        );
      }
    });
  }

  Future<void> _pickFolder() async {
    final uri = await FilePicker.pickDirectory();
    final path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : null;
    if (path == null || !mounted) return;
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;
    final coordinator = TransferCoordinator(settings);
    try {
      final entries = await coordinator.collect([path]);
      if (!mounted) return;
      setState(() => _selected.addAll(entries));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not read folder: $error');
    }
  }

  void _choose(Peer peer) {
    if (_selected.isEmpty) {
      setState(
        () => _error = 'Choose files or a folder first, then tap a device.',
      );
      return;
    }
    _send(peer);
  }

  Future<void> _send(Peer peer) async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = 'Connecting';
    });
    Transfer? transfer;
    try {
      final identity = await ref.read(identityProvider.future);
      final settings = await ref.read(settingsProvider.future);
      final coordinator = TransferCoordinator(settings);
      final transferId = const Uuid4().newId();
      final manifest = await coordinator.buildManifest(
        entries: _selected,
        identity: identity,
        transferId: transferId,
      );
      final client = WishareClient(
        host: peer.address,
        port: peer.port,
        expectedFingerprint: peer.certificateFingerprint ?? '',
        senderId: identity.id,
        token: peer.sessionToken ?? '',
      );
      // Keep one Transfer instance so createdAt never churns; every later
      // update is a copyWith of this original object.
      final activeTransfer = Transfer(
        id: transferId,
        direction: TransferDirection.outgoing,
        peerId: peer.id,
        peerName: peer.name,
        files: manifest.entries,
        totalBytes: manifest.totalBytes,
        createdAt: DateTime.now(),
        status: TransferStatus.connecting,
      );
      transfer = activeTransfer;
      await ref.read(transfersProvider.notifier).upsert(activeTransfer);
      await client.sendManifest(manifest);
      if (!mounted) return;
      setState(() => _status = 'Waiting for the receiver');
      await client.waitForAccept(transferId);
      if (!mounted) return;
      setState(() => _status = 'Transferring');
      ref
          .read(transfersProvider.notifier)
          .upsert(activeTransfer.copyWith(status: TransferStatus.transferring));
      await coordinator.send(
        client: client,
        manifest: manifest,
        entries: _selected,
        onProgress: (transferred, speed) {
          if (!mounted) return;
          setState(() {
            _progress = manifest.totalBytes == 0
                ? 1
                : transferred / manifest.totalBytes;
            _status = formatSpeed(speed);
          });
          ref
              .read(transfersProvider.notifier)
              .upsert(
                activeTransfer.copyWith(
                  status: TransferStatus.transferring,
                  transferredBytes: transferred,
                  speedBytesPerSecond: speed,
                ),
              );
        },
      );
      await ref
          .read(transfersProvider.notifier)
          .upsert(
            activeTransfer.copyWith(
              status: TransferStatus.completed,
              transferredBytes: manifest.totalBytes,
              finishedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/receive');
      messenger.showSnackBar(
        const SnackBar(content: Text('Transfer complete')),
      );
    } on Object catch (error) {
      final message = _transferErrorMessage(error);
      final failed = transfer?.copyWith(
        status: TransferStatus.failed,
        error: message,
        finishedAt: DateTime.now(),
      );
      if (failed != null) {
        await ref.read(transfersProvider.notifier).upsert(failed);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Transfer failed: $message';
      });
    }
  }

  String _transferErrorMessage(Object error) {
    if (error is TransferDeclinedException) {
      return error.status == 'cancelled'
          ? 'The receiver cancelled the transfer'
          : 'The receiver declined the transfer';
    }
    return error.toString();
  }
}
