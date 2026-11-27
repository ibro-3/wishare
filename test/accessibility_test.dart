import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/app.dart';
import 'package:wishare/core/models/peer.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/models/transfer.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/core/theme/wishare_theme.dart';
import 'package:wishare/features/transfer/receive_screen.dart';
import 'package:wishare/features/transfer/send_screen.dart';
import 'package:wishare/features/transfer/transfers_screen.dart';

class _FixedSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings.initial('/tmp/wishare');
}

class _PairedPeer extends PeersController {
  @override
  Future<List<Peer>> build() async => [
    const Peer(
      id: 'peer-1',
      name: 'Living room PC',
      address: '192.168.1.20',
      port: 45821,
      colorSeed: 0xFF6750A4,
      sessionToken: 'token',
      trustLevel: TrustLevel.paired,
    ),
  ];
}

class _NoTransfers extends TransfersController {
  @override
  Future<List<Transfer>> build() async => const [];
}

class _PendingTransfer extends TransfersController {
  @override
  Future<List<Transfer>> build() async => [
    Transfer(
      id: 't1',
      direction: TransferDirection.incoming,
      peerId: 'peer-1',
      peerName: 'Phone',
      files: const [TransferFileEntry(relativePath: 'photo.jpg', size: 100)],
      totalBytes: 100,
      transferredBytes: 40,
      createdAt: DateTime(2026),
      status: TransferStatus.transferring,
    ),
  ];
}

ThemeData _theme() => WishareTheme.build(
  WishareTheme.baseline(Brightness.light),
  contrast: WiContrast.standard,
  reduceMotion: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Send tab meets tap target and contrast guidelines', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_FixedSettings.new)],
        child: MaterialApp.router(routerConfig: appRouter, theme: _theme()),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('device rows expose pairing state and address', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FixedSettings.new),
          peersProvider.overrideWith(_PairedPeer.new),
        ],
        child: MaterialApp(home: const SendScreen(), theme: _theme()),
      ),
    );
    await tester.pumpAndSettle();
    final semanticsHandle = await tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp(r'Living room PC, paired device')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Address 192\.168\.1\.20:45821')),
      findsOneWidget,
    );
    semanticsHandle.dispose();
  });

  testWidgets('Receive tab meets guidelines and labels progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transfersProvider.overrideWith(_PendingTransfer.new)],
        child: MaterialApp(
          theme: _theme(),
          home: const Scaffold(body: ReceiveScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final semanticsHandle = await tester.ensureSemantics();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(
      find.bySemanticsLabel(RegExp(r'Receiving from Phone')),
      findsOneWidget,
    );
    semanticsHandle.dispose();
  });

  testWidgets('History meets tap target and contrast guidelines', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transfersProvider.overrideWith(_NoTransfers.new)],
        child: MaterialApp(
          theme: _theme(),
          home: const Scaffold(body: HistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
