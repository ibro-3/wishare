import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/network/protocol.dart';
import '../../core/network/wishare_client.dart';
import '../../core/state/providers.dart';

class ScanScreen extends ConsumerStatefulWidget {
  // Route parameters are passed in rather than looked up in initState:
  // GoRouterState.of(context) depends on the modal scope before mount.
  const ScanScreen({this.host, this.port, super.key});

  final String? host;
  final String? port;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  // mobile_scanner has no Linux/Windows implementation. Default those
  // platforms to manual entry instead of opening a broken camera view.
  static bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool _manual = false;
  bool _busy = false;
  String? _error;
  final _host = TextEditingController();
  final _port = TextEditingController(text: '${WiProtocol.port}');
  final _pin = TextEditingController();
  final _fingerprint = TextEditingController();
  MobileScannerController? _controller;

  /// Created only when the camera view is first needed, so manual-entry mode
  /// never triggers a camera permission prompt.
  MobileScannerController get _scannerController {
    return _controller ??= MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void initState() {
    super.initState();
    _host.text = widget.host ?? '';
    _port.text = widget.port ?? '${WiProtocol.port}';
    _manual = !_cameraSupported || _host.text.isNotEmpty;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    _fingerprint.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan pairing code'),
        actions: [
          if (_cameraSupported)
            IconButton(
              tooltip: _manual ? 'Scan a code' : 'Enter details manually',
              icon: Icon(_manual ? Icons.qr_code_scanner : Icons.keyboard),
              onPressed: () => setState(() => _manual = !_manual),
            ),
          // The generator screen is where the other device displays the code
          // this camera needs. M3 app bars carry up to two trailing buttons.
          IconButton(
            tooltip: 'Show my code',
            icon: const Icon(Icons.qr_code_outlined),
            onPressed: () => context.push('/pair'),
          ),
        ],
      ),
      body: SafeArea(
        child: _manual ? _manualForm(context, scheme, text) : _cameraView(),
      ),
    );
  }

  Widget _cameraView() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Camera unavailable',
                    style: text.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.errorCode.message,
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() => _manual = true),
                    child: const Text('Enter details manually'),
                  ),
                ],
              ),
            ),
          ),
          onDetect: (capture) {
            if (_busy) return;
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value == null) continue;
              try {
                final payload = PairingPayload.fromUri(Uri.parse(value));
                _confirm(payload);
                return;
              } on FormatException {
                continue;
              }
            }
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Point the camera at the pairing code shown on the other device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _manualForm(BuildContext context, ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter pairing details', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            _cameraSupported
                ? 'Read the PIN and fingerprint from the other device’s pairing screen.'
                : 'Camera scanning is unavailable on this platform. Ask the '
                      'receiving device to show its pairing code, then enter its '
                      'IP address, PIN and fingerprint below.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _host,
            decoration: const InputDecoration(labelText: 'IP address'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _port,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            decoration: const InputDecoration(labelText: '6-digit PIN'),
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _fingerprint,
            decoration: const InputDecoration(
              labelText: 'Certificate fingerprint',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _fetchFingerprint,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Fetch fingerprint from device'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _pairManually,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pair'),
          ),
        ],
      ),
    );
  }

  /// Manual pairing is LAN-only: reject addresses that can never belong to a
  /// nearby device before attempting a TLS connection.
  static bool _usableHost(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return false;
      octets.add(octet);
    }
    if (octets.first == 0 || octets.first == 127 || octets.first >= 224) {
      return false;
    }
    return !(octets[0] == 169 && octets[1] == 254);
  }

  Future<void> _fetchFingerprint() async {
    setState(() => _error = null);
    if (!_usableHost(_host.text.trim())) {
      setState(() => _error = 'Enter the other device’s LAN IPv4 address');
      return;
    }
    try {
      final fingerprint = await WishareClient.fetchFingerprint(
        _host.text.trim(),
        int.tryParse(_port.text.trim()) ?? WiProtocol.port,
      );
      if (!mounted) return;
      setState(() => _fingerprint.text = fingerprint);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach device: $error');
    }
  }

  Future<void> _pairManually() async {
    final fingerprint = normaliseFingerprint(_fingerprint.text.trim());
    if (!isValidFingerprint(fingerprint)) {
      setState(
        () => _error = 'Enter a valid 64-character certificate fingerprint',
      );
      return;
    }
    final host = _host.text.trim();
    if (!_usableHost(host)) {
      setState(() => _error = 'Enter the other device’s LAN IPv4 address');
      return;
    }
    final port = int.tryParse(_port.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _error = 'Enter a valid port number');
      return;
    }
    await _confirm(
      PairingPayload(
        host: host,
        port: port,
        name: 'Wishare device',
        fingerprint: fingerprint,
        pin: _pin.text.trim(),
      ),
    );
  }

  Future<void> _confirm(PairingPayload payload) async {
    setState(() => _busy = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect to this device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${payload.name}'),
            Text('Address: ${payload.host}:${payload.port}'),
            const SizedBox(height: 8),
            Text(
              'Certificate ${abbreviateFingerprint(payload.fingerprint)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Only continue if this fingerprint matches the one shown on the '
              'other device.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await ref.read(networkProvider.notifier).pairWith(payload);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Device paired successfully')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Pairing failed: $error';
        _manual = true;
      });
    }
  }
}
