import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/models/settings.dart';
import 'core/models/transfer.dart';
import 'core/state/providers.dart';
import 'core/theme/wishare_motion.dart';
import 'core/theme/wishare_theme.dart';
import 'features/devices/pairing_screen.dart';
import 'features/devices/scan_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/transfer/receive_screen.dart';
import 'features/transfer/send_screen.dart';
import 'features/transfer/transfers_screen.dart';
import 'shared/widgets/directional_icon.dart';
import 'shared/widgets/spring_reveal.dart';

final appRouter = GoRouter(
  initialLocation: '/send',
  routes: [
    ShellRoute(
      builder: (context, routerState, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/send',
          pageBuilder: (context, state) => _fadePage(const SendScreen(), state),
        ),
        GoRoute(
          path: '/receive',
          pageBuilder: (context, state) =>
              _fadePage(const ReceiveScreen(), state),
        ),
      ],
    ),
    GoRoute(
      path: '/history',
      pageBuilder: (context, state) => _fadePage(const HistoryScreen(), state),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _fadePage(
        Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: const SettingsScreen(),
        ),
        state,
      ),
    ),
    GoRoute(
      path: '/pair',
      pageBuilder: (context, state) => _fadePage(const PairingScreen(), state),
    ),
    GoRoute(
      path: '/scan',
      pageBuilder: (context, state) => _fadePage(const ScanScreen(), state),
    ),
  ],
);

/// Top-level routes use the M3 "top level" quick-fade transition with legacy
/// emphasized easing/duration tokens (transitions still use that system).
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.05, 0.7, 0.1, 1),
        reverseCurve: const Cubic(0.3, 0, 0.8, 0.15),
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class WishareApp extends ConsumerWidget {
  const WishareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value ?? AppSettings.initial('');
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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

  int get _index =>
      GoRouterState.of(context).uri.path.startsWith('/receive') ? 1 : 0;

  String get _title => _index == 0 ? 'Send' : 'Receive';

  @override
  Widget build(BuildContext context) {
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

    final shell = Scaffold(
      appBar: AppBar(
        // Two leading icon buttons need more than the default 56dp slot.
        leadingWidth: 112,
        // My design decision: History sits immediately left of Settings in
        // the leading area; M3 normally uses one leading menu/back button.
        leading: Row(
          children: [
            IconButton(
              tooltip: 'Transfer history',
              icon: const Icon(Icons.history),
              onPressed: () => context.go('/history'),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
        title: Text(_title, style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Pair a device',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => context.go('/scan'),
          ),
        ],
        bottom: TabBar(
          tabs: [
            const Tab(text: 'Send'),
            if (pendingCount > 0)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Receive'),
                    const SizedBox(width: 4),
                    Badge(
                      label: Text(pendingCount > 9 ? '9+' : '$pendingCount'),
                    ),
                  ],
                ),
              )
            else
              const Tab(text: 'Receive'),
          ],
          onTap: (index) => context.go(index == 0 ? '/send' : '/receive'),
        ),
      ),
      body: SafeArea(child: widget.child),
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
            context.go('/history'),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            context.go('/settings'),
      },
      child: shell,
    );
  }

  void _showCompletion(Transfer transfer) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: WiSpringReveal(
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
        content: Text(
          '${transfer.files.length} items sent to ${transfer.peerName}.',
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

// Kept exported so feature screens can reuse the mirrored send icon.
typedef WiSendIcon = WiDirectionalIcon;
