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
import '../../core/theme/wishare_type.dart';
import '../../shared/format.dart';
import '../../shared/widgets/directional_icon.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _selected = <SelectedEntry>[];
  Peer? _peer;
  bool _busy = false;
  double _progress = 0;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    final peerId = GoRouterState.of(context).uri.queryParameters['peerId'];
    final peers = ref.read(peersProvider).value ?? const <Peer>[];
    if (peerId != null) {
      for (final peer in peers) {
        if (peer.id == peerId) _peer = peer;
      }
    }
    _peer ??= _firstPaired(peers);
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

  Peer? _firstPaired(List<Peer> peers) {
    for (final peer in peers) {
      if (peer.isPaired) return peer;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];
    final paired = peers.where((peer) => peer.isPaired).toList();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = _selected.fold<int>(0, (sum, entry) => sum + entry.size);

    final nearby = peers.where((peer) => !peer.isPaired).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
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
            DropdownButtonFormField<Peer>(
              initialValue: _peer != null && paired.contains(_peer)
                  ? _peer
                  : paired.first,
              decoration: const InputDecoration(labelText: 'Device'),
              items: [
                for (final peer in paired)
                  DropdownMenuItem(value: peer, child: Text(peer.name)),
              ],
              onChanged: (peer) => setState(() => _peer = peer),
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
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _busy || _peer == null || _selected.isEmpty
                ? null
                : _send,
            // Emphasized type is the exception: primary action only.
            style: FilledButton.styleFrom(
              textStyle: context.emphasizedText.labelLarge,
            ),
            icon: const WiDirectionalIcon(Icons.send),
            label: Text(_busy ? 'Sending…' : 'Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
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
    if (path == null) return;
    final settings = await ref.read(settingsProvider.future);
    final coordinator = TransferCoordinator(settings);
    try {
      final entries = await coordinator.collect([path]);
      setState(() => _selected.addAll(entries));
    } on Object catch (error) {
      setState(() => _error = 'Could not read folder: $error');
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = 'Connecting';
    });
    try {
      final peer = _peer!;
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
      await ref
          .read(transfersProvider.notifier)
          .upsert(
            Transfer(
              id: transferId,
              direction: TransferDirection.outgoing,
              peerId: peer.id,
              peerName: peer.name,
              files: manifest.entries,
              totalBytes: manifest.totalBytes,
              createdAt: DateTime.now(),
              status: TransferStatus.connecting,
            ),
          );
      await client.sendManifest(manifest);
      if (!mounted) return;
      setState(() => _status = 'Waiting for the receiver');
      await client.waitForAccept(transferId);
      if (!mounted) return;
      setState(() => _status = 'Transferring');
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
                Transfer(
                  id: transferId,
                  direction: TransferDirection.outgoing,
                  peerId: peer.id,
                  peerName: peer.name,
                  files: manifest.entries,
                  totalBytes: manifest.totalBytes,
                  createdAt: DateTime.now(),
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
            Transfer(
              id: transferId,
              direction: TransferDirection.outgoing,
              peerId: peer.id,
              peerName: peer.name,
              files: manifest.entries,
              totalBytes: manifest.totalBytes,
              createdAt: DateTime.now(),
              status: TransferStatus.completed,
              transferredBytes: manifest.totalBytes,
              finishedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      context.go('/receive');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Transfer complete')));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Transfer failed: $error';
      });
    }
  }
}
