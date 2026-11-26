import 'transfer.dart';
import 'parse_helpers.dart';

/// Transfer manifest: a flat list of relative paths, including explicit
/// directory entries so empty folders survive the round trip.
class TransferManifest {
  const TransferManifest({
    required this.transferId,
    required this.senderId,
    required this.senderName,
    required this.rootName,
    required this.entries,
    required this.totalBytes,
  });

  final String transferId;
  final String senderId;
  final String senderName;
  final String rootName;
  final List<TransferFileEntry> entries;
  final int totalBytes;

  int get fileCount => entries.where((e) => !e.isDirectory).length;

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'senderId': senderId,
    'senderName': senderName,
    'rootName': rootName,
    'entries': entries.map((e) => e.toJson()).toList(),
    'totalBytes': totalBytes,
  };

  factory TransferManifest.fromJson(Map<String, dynamic> json) {
    final entries = (list(json['entries']) ?? const <dynamic>[])
        .map(
          (entry) => object(entry) == null
              ? null
              : TransferFileEntry.fromJson(object(entry)!),
        )
        .whereType<TransferFileEntry>()
        .toList();
    return TransferManifest(
      transferId: text(json['transferId']) ?? '',
      senderId: text(json['senderId']) ?? '',
      senderName: text(json['senderName']) ?? 'Wishare device',
      rootName: text(json['rootName']) ?? 'Files',
      entries: entries,
      totalBytes: integer(json['totalBytes'], 0),
    );
  }
}
