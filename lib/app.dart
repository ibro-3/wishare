import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/models/pair_request.dart';
import 'core/models/settings.dart';
import 'core/models/transfer.dart';
import 'core/network/protocol.dart';
import 'core/state/providers.dart';
import 'core/state/update_provider.dart';
import 'core/theme/wishare_motion.dart';
import 'core/theme/wishare_theme.dart';
import 'core/theme/wishare_type.dart';
import 'features/devices/pairing_screen.dart';
import 'features/devices/scan_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/transfer/receive_screen.dart';
import 'features/transfer/send_screen.dart';
import 'features/transfer/transfers_screen.dart';
import 'shared/widgets/open_transfer_actions.dart';
import 'shared/widgets/spring_reveal.dart';

final appRouter = GoRouter(
  initialLocation: '/send',
  routes: [
    ShellRoute(
      builder: (context, routerState, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/send',
          pageBuilder: (context, state) => _topLevelPage(
            context,
            SendScreen(peerId: state.uri.queryParameters['peerId']),
            state,
          ),
        ),
        GoRoute(
          path: '/receive',
          pageBuilder: (context, state) =>
              _topLevelPage(context, const ReceiveScreen(), state),
        ),
      ],
    ),
    // Sub-flows are pushed above the shell so system/AppBar back returns to
    // whichever top-level destination the user came from.
    GoRoute(
      path: '/history',
      pageBuilder: (context, state) => _subPage(const HistoryScreen(), state),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _subPage(const SettingsScreen(), state),
    ),
    GoRoute(
      path: '/pair',
      pageBuilder: (context, state) => _subPage(const PairingScreen(), state),
    ),
    GoRoute(
      path: '/scan',
      pageBuilder: (context, state) => _subPage(
        ScanScreen(
          host: state.uri.queryParameters['host'],
          port: state.uri.queryParameters['port'],
        ),
        state,
      ),
    ),
  ],
);

/// Top-level destinations use the M3 "top level" quick fade with published
/// legacy easing/duration tokens (transitions still use that system).
CustomTransitionPage<void> _topLevelPage(
  BuildContext context,
  Widget child,
  GoRouterState state,
) {
  final reduceMotion = context.wiReduceMotion;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: reduceMotion
        ? WiTransition.reducedDuration
        : WiTransition.enterDuration,
    reverseTransitionDuration: reduceMotion
        ? WiTransition.reducedDuration
        : WiTransition.exitDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (context.wiReduceMotion) {
        return FadeTransition(opacity: animation, child: child);
      }
      return WiTopLevelFade(animation: animation, child: child);
    },
  );
}

/// Pushed sub-flows use the platform's forward/backward default page route,
/// which reads [ThemeData.pageTransitionsTheme] from the app theme.
Page<void> _subPage(Widget child, GoRouterState state) =>
    MaterialPage<void>(key: state.pageKey, child: child);

class WishareApp extends ConsumerWidget {
  const WishareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Single startup trigger for the passive update check. It is lazy and
    // gated on the Settings toggle inside the provider.
    ref.watch(startupUpdateCheckProvider);
    final settings =
        ref.watch(settingsProvider).value ?? AppSettings.initial('');
    // Read the platform setting from the view: MaterialApp inserts MediaQuery
    // below itself, so maybeDisableAnimationsOf(context) is always null here.
    final reduceMotion = MediaQueryData.fromView(View.of(context))
        .disableAnimations;

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ColorScheme light = WishareTheme.baseline(Brightness.light);
        ColorScheme dark = WishareTheme.baseline(Brightness.dark);
        if (settings.dynamicColor) {
          light = lightDynamic ?? light;
          dark = darkDynamic ?? dark;
        }
        return MaterialApp.router(
          title: 'Wishare',
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
          theme: WishareTheme.build(
            light,
            contrast: settings.contrast,
            reduceMotion: reduceMotion,
          ),
          darkTheme: WishareTheme.build(
            dark,
            contrast: settings.contrast,
            reduceMotion: reduceMotion,
          ),
          themeMode: settings.themeMode,
        );
      },
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _celebratedFirstCompletion = false;
  bool _pairDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // A request can arrive before the shell mounts (e.g. resuming from the
    // background); ref.listen only reports later changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowPairRequest();
    });
  }

  int get _index =>
      GoRouterState.of(context).uri.path.startsWith('/receive') ? 1 : 0;

  String get _title => _index == 0 ? 'Send' : 'Receive';

  @override
  Widget build(BuildContext context) {
    ref.listen(pairRequestsProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowPairRequest();
      });
    });
    ref.listen(transfersProvider, (previous, next) {
      final transfers = next.value ?? const <Transfer>[];
      final previousById = {
        for (final transfer in previous?.value ?? const <Transfer>[])
          transfer.id: transfer.status,
      };
      for (final transfer in transfers) {
        // Hero moment: only the first finished transfer is celebrated.
        if (transfer.status == TransferStatus.completed &&
            !_celebratedFirstCompletion &&
            previousById[transfer.id] != TransferStatus.completed) {
          _celebratedFirstCompletion = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showCompletion(transfer);
          });
        }
      }
    });

    final pendingCount =
        (ref.watch(transfersProvider).value ?? const <Transfer>[])
            .where((transfer) => transfer.status == TransferStatus.offered)
            .length;
    // From M3: a small badge marks an unread notification on a destination.
    // Here it signals a newer release without interrupting the user at startup.
    final updateAvailable = ref.watch(updateProvider).value?.showBadge ?? false;

    final shell = Scaffold(
      appBar: AppBar(
        // M3 app bars carry up to two trailing icon buttons; the primary
        // pairing action lives in the extended FAB instead of the bar.
        title: Text(_title, style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Transfer history',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            tooltip: updateAvailable
                ? 'Settings, update available'
                : 'Settings',
            icon: Badge(
              isLabelVisible: updateAvailable,
              child: const Icon(Icons.settings_outlined),
            ),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      // From M3: navigation belongs at the bottom for reachability. Two
      // destinations is a deliberate deviation from the 3–5 nav bar guidance.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) =>
            context.go(index == 0 ? '/send' : '/receive'),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.send_outlined),
            selectedIcon: const Icon(Icons.send),
            label: 'Send',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text(pendingCount > 9 ? '9+' : '$pendingCount'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text(pendingCount > 9 ? '9+' : '$pendingCount'),
              child: const Icon(Icons.inbox),
            ),
            label: 'Receive',
          ),
        ],
      ),
      body: SafeArea(child: widget.child),
      // From M3: use an extended FAB when the icon alone is ambiguous. The
      // label makes pairing discoverable; title medium is the small extended
      // FAB's type style. Anchored bottom-trailing, mirrored in RTL.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wishare-pair-fab',
        onPressed: () => context.push('/scan'),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Pair'),
        extendedTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            context.go('/send'),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            context.go('/send'),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            context.go('/send'),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            context.go('/receive'),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            context.push('/history'),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            context.push('/settings'),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            context.push('/settings'),
      },
      child: shell,
    );
  }

  /// Show one pairing prompt at a time, then move to the next queued request.
  void _maybeShowPairRequest() {
    if (_pairDialogOpen || !mounted) return;
    final requests =
        ref.read(pairRequestsProvider).value ?? const <PairRequest>[];
    if (requests.isEmpty) return;
    _pairDialogOpen = true;
    _showPairRequest(requests.first).whenComplete(() {
      _pairDialogOpen = false;
      if (mounted) _maybeShowPairRequest();
    });
  }

  Future<void> _showPairRequest(PairRequest request) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final dialogText = Theme.of(dialogContext).textTheme;
        return AlertDialog(
          // No spring reveal: this is a decision prompt, not a hero moment.
          icon: CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.link, size: 32, color: scheme.onPrimaryContainer),
          ),
          title: const Text('Pairing request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${request.name} wants to pair with this device.',
                style: dialogText.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Certificate ${abbreviateFingerprint(request.fingerprint, edge: 16)}',
                style: dialogText.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Only approve if this matches the certificate fingerprint in '
                'the sender’s Settings.',
                style: dialogText.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Decline'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                textStyle: dialogContext.emphasizedText.labelLarge,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    if (approved == true) {
      await ref.read(networkProvider.notifier).approvePairRequest(request.id);
    } else {
      await ref.read(networkProvider.notifier).declinePairRequest(request.id);
    }
    if (mounted) {
      ref.read(pairRequestsProvider.notifier).remove(request.id);
    }
  }

  void _showCompletion(Transfer transfer) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: WiSpringReveal(
          enabled:
              !(Theme.of(dialogContext)
                      .extension<WiMotionExtension>()
                      ?.reduceMotion ??
                  false),
          spatial: WiSpring.fastSpatial,
          effects: WiSpring.fastEffects,
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Theme.of(dialogContext)
                .colorScheme
                .primaryContainer,
            child: Icon(
              Icons.check,
              size: 32,
              color: Theme.of(dialogContext).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: const Text('Transfer complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${transfer.files.length} items sent to ${transfer.peerName}.',
            ),
            if (transfer.saveDirectory != null) ...[
              const SizedBox(height: 16),
              OpenTransferActions(transfer: transfer),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
