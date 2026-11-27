import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/models/transfer.dart';
import 'package:wishare/core/platform/reveal.dart';
import 'package:wishare/shared/widgets/open_transfer_actions.dart';

void main() {
  group('resolveSavedFile', () {
    late Directory root;

    setUp(() async => root = await Directory.systemTemp.createTemp('wishare-'));
    tearDown(() async => root.delete(recursive: true));

    test('uses the manifest path when the file exists', () async {
      final file = File('${root.path}/report.txt');
      await file.writeAsString('hello');
      expect(
        await RevealInFolder.resolveSavedFile(root.path, 'report.txt'),
        file.path,
      );
    });

    test('finds a receiver-added timestamp suffix', () async {
      final file = File('${root.path}/report-123456.txt');
      await file.writeAsString('hello');
      expect(
        await RevealInFolder.resolveSavedFile(root.path, 'report.txt'),
        file.path,
      );
    });

    test('returns the manifest path when nothing is saved', () async {
      expect(
        await RevealInFolder.resolveSavedFile(root.path, 'missing.txt'),
        '${root.path}/missing.txt',
      );
    });
  });

  testWidgets('open actions only appear for completed incoming transfers', (
    tester,
  ) async {
    final incoming = Transfer(
      id: 't1',
      direction: TransferDirection.incoming,
      peerId: 'p1',
      peerName: 'Laptop',
      files: const [TransferFileEntry(relativePath: 'report.txt', size: 5)],
      totalBytes: 5,
      createdAt: DateTime(2026),
      status: TransferStatus.completed,
      saveDirectory: '/tmp/wishare',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpenTransferActions(transfer: incoming)),
      ),
    );
    expect(find.text('Open folder'), findsOneWidget);
    expect(find.text('Open file'), findsOneWidget);

    final outgoing = Transfer(
      id: 't2',
      direction: TransferDirection.outgoing,
      peerId: 'p1',
      peerName: 'Laptop',
      files: incoming.files,
      totalBytes: 5,
      createdAt: DateTime(2026),
      status: TransferStatus.completed,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpenTransferActions(transfer: outgoing)),
      ),
    );
    expect(find.text('Open folder'), findsNothing);
    expect(find.text('Open file'), findsNothing);
  });
}
