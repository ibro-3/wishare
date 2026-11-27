import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/crypto/certificate_manager.dart';
import '../../core/models/peer.dart';
import '../../core/models/transfer.dart';
import '../../core/network/protocol.dart';
import '../../core/network/transfer_coordinator.dart';
import '../../core/network/wishare_client.dart';
import '../../core/platform/share_intent.dart';
import '../../core/state/providers.dart';
import '../../core/theme/wishare_motion.dart';
import '../../core/theme/wishare_theme.dart';
import '../../shared/format.dart';
import '../../shared/widgets/directional_icon.dart';
import '../../shared/widgets/spring_reveal.dart';

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
  final _pairingIds = <String>{};
  String? _requestedPeerId;
  String? _celebratedPeerId;
  bool _busy = false;
  bool _scanning = false;
  DateTime? _lastScan;
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
    final networkError = ref.watch(networkProvider).value?.error;
    // One list for every known device: paired first, then the peer requested
    // by a share shortcut, then most-recently-seen. Unpaired devices follow
    // with an inline Pair action.
    final devices = peers.toList()
      ..sort((a, b) {
        final pairedOrder = (a.isPaired ? 0 : 1).compareTo(b.isPaired ? 0 : 1);
        if (pairedOrder != 0) return pairedOrder;
        final requestedOrder = (a.id == _requestedPeerId ? 0 : 1).compareTo(
          b.id == _requestedPeerId ? 0 : 1,
        );
        if (requestedOrder != 0) return requestedOrder;
        final seenA = a.lastSeen?.millisecondsSinceEpoch ?? 0;
        final seenB = b.lastSeen?.millisecondsSinceEpoch ?? 0;
        return seenB.compareTo(seenA);
      });
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = _selected.fold<int>(0, (sum, entry) => sum + entry.size);
    // Hero moment (the second of two): the first peer that appears. Once per
    // session, keyed by peer id; disabled under reduced motion.
    _celebratedPeerId ??= devices.isEmpty ? null : devices.first.id;
    final reduceMotion = context.wiReduceMotion;

    return SingleChildScrollView(
      key: const PageStorageKey<String>('send'),
      // Leave room for the navigation bar and the pairing FAB above it.
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              'Tap a device below to send these items',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Send to', style: text.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Scan again',
                icon: _scanning
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar_outlined),
                onPressed: _scanning ? null : _scanAgain,
              ),
            ],
          ),
          if (_scanning)
            Text('Scanning nearby devices…', style: text.bodySmall)
          else if (_lastScan != null)
            Text(
              'Last scan: ${TimeOfDay.fromDateTime(_lastScan!).format(context)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          if (networkError != null && networkError.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Discovery: $networkError',
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            ),
          if (networkError != null && networkError.isNotEmpty)
            const SizedBox(height: 8),
          if (devices.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No devices found yet. Use the Pair button to add one.',
                  style: text.bodySmall,
                ),
              ),
            )
          else
            for (final peer in devices)
              _deviceCard(
                peer,
                scheme: scheme,
                text: text,
                reveal: peer.id == _celebratedPeerId && !reduceMotion,
              ),
        ],
      ),
    );
  }

  Widget _deviceCard(
    Peer peer, {
    required ColorScheme scheme,
    required TextTheme text,
    required bool reveal,
  }) {
    final card = Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: peer.isPaired
              ? scheme.primaryContainer
              : scheme.secondaryContainer,
          foregroundColor: peer.isPaired
              ? scheme.onPrimaryContainer
              : scheme.onSecondaryContainer,
          child: const Icon(Icons.devices_other),
        ),
        title: Text(peer.name, style: text.titleMedium),
        subtitle: Text(peer.endpoint, style: text.bodySmall),
        // Paired rows send on tap; unpaired rows pair inline.
        trailing: peer.isPaired
            ? const WiDirectionalIcon(Icons.send)
            : _pairingIds.contains(peer.id)
            ? OutlinedButton.icon(
                // Waiting on a human at the other end: let the sender bail out.
                onPressed: () => _cancelPair(),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancel'),
              )
            : OutlinedButton(
                // No QR and no PIN: the receiver approves a request in its UI.
                // Only one request at a time, so Cancel has an unambiguous
                // target.
                onPressed: _pairingIds.isNotEmpty
                    ? null
                    : () => _requestPair(peer),
                child: const Text('Pair'),
              ),
        onTap: peer.isPaired && !_busy ? () => _choose(peer) : null,
      ),
    );
    if (!reveal) return card;
    return WiSpringReveal(
      key: ValueKey<String>('peer-reveal-${peer.id}'),
      spatial: WiSpring.fastSpatial,
      effects: WiSpring.fastEffects,
      child: card,
    );
  }

  Future<void> _scanAgain() async {
    setState(() => _scanning = true);
    try {
      await ref.read(networkProvider.notifier).rescan();
      if (!mounted) return;
      setState(() => _lastScan = DateTime.now());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Scan failed: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _cancelPair() {
    ref.read(networkProvider.notifier).cancelPairRequest();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Pairing request cancelled')));
  }

  Future<void> _requestPair(Peer peer) async {
    final fingerprint = peer.certificateFingerprint;
    final messenger = ScaffoldMessenger.of(context);
    if (fingerprint == null || !isValidFingerprint(fingerprint)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No verified fingerprint for this device. Use Pair → scan code '
            'or enter its details manually.',
          ),
        ),
      );
      return;
    }
    setState(() => _pairingIds.add(peer.id));
    try {
      await ref.read(networkProvider.notifier).requestPairWith(peer);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Paired with ${peer.name}')),
      );
    } on PairRequestException catch (error) {
      if (!mounted || error.status == 'cancelled') return;
      messenger.showSnackBar(SnackBar(content: Text('Could not pair: $error')));
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not pair: $error')));
    } finally {
      if (mounted) setState(() => _pairingIds.remove(peer.id));
    }
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
