import 'transfer.dart';

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
    final entries = (json['entries'] as List<dynamic>)
        .map((e) => TransferFileEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return TransferManifest(
      transferId: json['transferId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      rootName: json['rootName'] as String,
      entries: entries,
      totalBytes: json['totalBytes'] as int,
    );
  }
}
