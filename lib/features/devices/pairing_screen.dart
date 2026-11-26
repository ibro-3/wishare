import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/protocol.dart';
import '../../core/state/providers.dart';
import '../../core/theme/wishare_type.dart';
import '../../shared/widgets/loading_indicator.dart';

class PairingScreen extends ConsumerWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pair a device')),
      body: network.when(
        loading: () => const WiLoadingIndicator(),
        error: (error, _) => Center(child: Text('Network error: $error')),
        data: (state) {
          final payload = state.qrPayload;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Scan this code on the other device',
                      style: text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The code contains this device’s certificate fingerprint, '
                      'so the connection can be verified automatically.',
                      style: text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (payload == null)
                      FilledButton(
                        onPressed: () => ref
                            .read(networkProvider.notifier)
                            .generatePairingCode(),
                        child: const Text('Generate pairing code'),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: payload.toQrUri(),
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: scheme.surfaceContainerLow,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Or enter this PIN',
                        style: text.labelLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        payload.pin,
                        style: context.emphasizedText.headlineLarge?.copyWith(
                          letterSpacing: 8,
                          color: scheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Certificate ${abbreviateFingerprint(payload.fingerprint)}',
                        style: text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(networkProvider.notifier)
                            .generatePairingCode(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('New code'),
                      ),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Done'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
