import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/settings.dart';
import '../../core/network/protocol.dart';
import '../../core/state/providers.dart';
import '../../core/theme/wishare_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final identityAsync = ref.watch(identityProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final identity = identityAsync.value;
    Future<void> update(AppSettings Function(AppSettings) change) async {
      final current = ref.read(settingsProvider).value;
      if (current == null) return;
      final next = change(current);
      await ref.read(settingsProvider.notifier).updateSettings((_) => next);
      // Apply to live services without rebuilding the network controller,
      // which would drop transfers already in flight.
      await ref.read(networkProvider.notifier).applySettings(next);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: [
        _section('This device', text),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Device name'),
                subtitle: Text(settings.deviceName),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editName(context, ref, settings),
              ),
              if (identity != null)
                ListTile(
                  title: const Text('Certificate fingerprint'),
                  subtitle: Text(
                    abbreviateFingerprint(identity.fingerprint, edge: 16),
                  ),
                ),
            ],
          ),
        ),
        _section('Appearance', text),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Theme', style: text.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (value) {
                    if (value.isNotEmpty) {
                      update((s) => s.copyWith(themeMode: value.first));
                    }
                  },
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('Dynamic colour'),
                  subtitle: const Text('Use colours from the system theme'),
                  value: settings.dynamicColor,
                  onChanged: (value) =>
                      update((s) => s.copyWith(dynamicColor: value)),
                ),
                const SizedBox(height: 12),
                Text('Contrast', style: text.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<WiContrast>(
                  segments: [
                    for (final level in WiContrast.values)
                      ButtonSegment(value: level, label: Text(level.label)),
                  ],
                  selected: {settings.contrast},
                  onSelectionChanged: (value) {
                    if (value.isNotEmpty) {
                      update((s) => s.copyWith(contrast: value.first));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        _section('Sharing', text),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Download folder'),
                subtitle: Text(settings.downloadDirectory ?? 'Not set'),
                trailing: TextButton(
                  onPressed: () async {
                    final uri = await FilePicker.pickDirectory();
                    final path = uri != null && uri.scheme == 'file'
                        ? uri.toFilePath()
                        : null;
                    if (path != null) {
                      await update((s) => s.copyWith(downloadDirectory: path));
                    }
                  },
                  child: const Text('Change'),
                ),
              ),
              SwitchListTile(
                title: const Text('Device discovery'),
                subtitle: const Text('Find and show nearby devices'),
                value: settings.discoveryEnabled,
                onChanged: (value) =>
                    update((s) => s.copyWith(discoveryEnabled: value)),
              ),
              SwitchListTile(
                title: const Text('Broadcast presence'),
                subtitle: const Text('Let other devices find this one'),
                value: settings.broadcastEnabled,
                onChanged: (value) =>
                    update((s) => s.copyWith(broadcastEnabled: value)),
              ),
              SwitchListTile(
                title: const Text('Notifications'),
                value: settings.notificationsEnabled,
                onChanged: (value) =>
                    update((s) => s.copyWith(notificationsEnabled: value)),
              ),
              SwitchListTile(
                title: const Text('Start minimized (desktop)'),
                value: settings.startMinimized,
                onChanged: (value) =>
                    update((s) => s.copyWith(startMinimized: value)),
              ),
            ],
          ),
        ),
        _section('Connection help', text),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('If devices cannot see each other'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(_connectionAdvice(), style: text.bodySmall),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Wishare 0.1.2 · local network only',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _connectionAdvice() {
    if (Platform.isWindows) {
      return 'Allow Wishare through Windows Defender Firewall on private '
          'networks. Inbound TCP 45821 and UDP 45821/5353 must be permitted. '
          'Both devices must be on the same network.';
    }
    if (Platform.isLinux) {
      return 'Allow UDP 45821 and 5353 and TCP 45821 in your firewall '
          '(for example: sudo ufw allow 45821/udp). If multicast is filtered, '
          'use the QR code or enter the other device’s IP address manually.';
    }
    return 'Keep both devices on the same Wi-Fi network and disable mobile '
        'data during setup. If discovery is filtered, scan the pairing code '
        'or enter the other device’s IP address manually.';
  }

  Widget _section(String title, TextTheme text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(title, style: text.titleMedium),
  );

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final controller = TextEditingController(text: settings.deviceName);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Device name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (saved == true && controller.text.trim().isNotEmpty) {
        await ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(deviceName: controller.text.trim()),
            );
      }
    } finally {
      controller.dispose();
    }
  }
}
