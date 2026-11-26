import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/settings.dart';
import '../../core/network/protocol.dart';
import '../../core/state/providers.dart';
import '../../core/state/update_provider.dart';
import '../../core/theme/wishare_theme.dart';
import '../../core/theme/wishare_type.dart';
import '../../core/update/update_service.dart';
import '../../core/version.dart';
import '../../shared/widgets/loading_indicator.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final identityAsync = ref.watch(identityProvider);
    final updateState = ref.watch(updateProvider).value ?? const UpdateState();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (settings == null) {
      // Keep the app bar (and its back button) while settings load.
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: WiLoadingIndicator()),
      );
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

    String updateSubtitle() {
      final checked = updateState.checkedAt;
      final time = checked == null
          ? ''
          : ' · ${checked.hour.toString().padLeft(2, '0')}:'
                '${checked.minute.toString().padLeft(2, '0')}';
      return switch (updateState.status) {
        UpdateStatus.checking => 'Checking for updates…',
        UpdateStatus.available =>
          'Version ${updateState.info?.version ?? '?'} is available$time',
        UpdateStatus.upToDate => 'Up to date · Wishare $WiVersion.current$time',
        UpdateStatus.error =>
          'Couldn’t check · ${updateState.error ?? 'try again'}',
        UpdateStatus.idle => 'Wishare $WiVersion.current',
      };
    }

    Future<void> openDownload(UpdateInfo info) async {
      final uri = Uri.tryParse(info.downloadUrl);
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download link is unavailable')),
        );
        return;
      }
      try {
        final canOpen = await canLaunchUrl(uri);
        final launched =
            canOpen &&
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn’t open the download page')),
          );
        }
      } on Object {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn’t open the download page')),
          );
        }
      }
    }

    void showUpdateDialog(UpdateInfo info) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final dialogScheme = Theme.of(dialogContext).colorScheme;
          final dialogText = Theme.of(dialogContext).textTheme;
          final notes = info.releaseNotes.isEmpty
              ? 'A new version of Wishare is ready to download.'
              : info.releaseNotes;
          return AlertDialog(
            // Not a hero moment: the product already has two, and M3 says one
            // or two per product. This is a plain status icon, not a reveal.
            icon: CircleAvatar(
              radius: 28,
              backgroundColor: dialogScheme.primaryContainer,
              child: Icon(
                Icons.system_update,
                size: 32,
                color: dialogScheme.onPrimaryContainer,
              ),
            ),
            title: Text('Update available · ${info.version}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Text(notes, style: dialogText.bodyMedium),
              ),
            ),
            actions: [
              // From M3: the lower-emphasis text button sits left of the
              // higher-emphasis filled button in a two-button row.
              TextButton(
                onPressed: () {
                  ref.read(updateProvider.notifier).dismiss();
                  Navigator.pop(dialogContext);
                },
                child: const Text('Later'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  textStyle: dialogContext.emphasizedText.labelLarge,
                ),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  openDownload(info);
                },
                icon: const Icon(Icons.open_in_new, size: 20),
                label: Text(
                  info.downloadLabel,
                  style: dialogContext.emphasizedText.labelLarge,
                ),
              ),
            ],
          );
        },
      );
    }

    Future<void> checkForUpdates() async {
      await ref.read(updateProvider.notifier).checkNow();
      if (!context.mounted) return;
      final state = ref.read(updateProvider).value;
      if (state == null) return;
      switch (state.status) {
        case UpdateStatus.available:
          if (state.info != null) showUpdateDialog(state.info!);
        case UpdateStatus.upToDate:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You’re on the latest version')),
          );
        case UpdateStatus.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Couldn’t check for updates'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => checkForUpdates(),
              ),
            ),
          );
        case UpdateStatus.checking:
        case UpdateStatus.idle:
          break;
      }
    }

    Widget updatesCard() => Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              Icons.system_update_outlined,
              color: scheme.onSurfaceVariant,
            ),
            title: const Text('Software update'),
            subtitle: Text(updateSubtitle()),
            trailing: updateState.status == UpdateStatus.available
                ? const Icon(Icons.chevron_right)
                : null,
            onTap:
                updateState.status == UpdateStatus.available &&
                    updateState.info != null
                ? () => showUpdateDialog(updateState.info!)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                if (updateState.status == UpdateStatus.checking)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: WiLoadingIndicator(size: 24),
                  )
                else
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      textStyle: context.emphasizedText.labelLarge,
                    ),
                    onPressed: checkForUpdates,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: Text(
                      'Check now',
                      style: context.emphasizedText.labelLarge,
                    ),
                  ),
                const SizedBox(width: 8),
                if (updateState.status == UpdateStatus.available &&
                    updateState.info != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      textStyle: context.emphasizedText.labelLarge,
                    ),
                    onPressed: () => openDownload(updateState.info!),
                    icon: const Icon(Icons.download, size: 20),
                    label: Text(
                      updateState.info!.downloadLabel,
                      style: context.emphasizedText.labelLarge,
                    ),
                  ),
              ],
            ),
          ),
          Divider(indent: 16, endIndent: 16, color: scheme.outlineVariant),
          SwitchListTile(
            title: const Text('Check on startup'),
            subtitle: const Text('Contacts GitHub for new releases'),
            value: settings.autoUpdateCheck,
            onChanged: (value) =>
                update((s) => s.copyWith(autoUpdateCheck: value)),
          ),
        ],
      ),
    );

    final view = ListView(
      key: const PageStorageKey<String>('settings'),
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
        _section('Updates', text),
        updatesCard(),
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
          'Wishare ${WiVersion.current} · local network only',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(child: view),
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
