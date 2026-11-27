import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wishare/core/models/transfer.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/features/transfer/transfers_screen.dart';

Transfer _transfer(String id, TransferDirection direction, String peerName) =>
    Transfer(
      id: id,
      direction: direction,
      peerId: 'peer-$id',
      peerName: peerName,
      files: const [TransferFileEntry(relativePath: 'file.txt', size: 5)],
      totalBytes: 5,
      createdAt: DateTime(2026),
      status: TransferStatus.completed,
    );

class _TwoTransfers extends TransfersController {
  @override
  Future<List<Transfer>> build() async => [
    _transfer('in', TransferDirection.incoming, 'Laptop'),
    _transfer('out', TransferDirection.outgoing, 'Phone'),
  ];
}

class _NoTransfers extends TransfersController {
  @override
  Future<List<Transfer>> build() async => const [];
}

Widget _screen(TransfersController controller) => ProviderScope(
  overrides: [transfersProvider.overrideWith(() => controller)],
  child: const MaterialApp(home: HistoryScreen()),
);

void main() {
  testWidgets('filters the history list by direction', (tester) async {
    await tester.pumpWidget(_screen(_TwoTransfers()));
    await tester.pumpAndSettle();

    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);

    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Laptop'), findsNothing);
    final sentStyle = tester.widget<Text>(find.text('Sent')).style;
    expect(sentStyle?.fontWeight, FontWeight.w700);

    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Phone'), findsNothing);
  });

  testWidgets('shows a filter-specific empty state', (tester) async {
    await tester.pumpWidget(_screen(_NoTransfers()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();
    expect(find.text('No received transfers yet'), findsOneWidget);
  });
}
