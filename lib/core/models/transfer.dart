enum TransferDirection { incoming, outgoing }

enum TransferStatus {
  offered,
  queued,
  connecting,
  transferring,
  verifying,
  completed,
  failed,
  cancelled,
  declined,
}

class TransferFileEntry {
  const TransferFileEntry({
    required this.relativePath,
    required this.size,
    this.isDirectory = false,
    this.checksum,
    this.status = TransferStatus.queued,
  });

  final String relativePath;
  final int size;
  final bool isDirectory;
  final String? checksum;
  final TransferStatus status;

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'size': size,
    'isDirectory': isDirectory,
    'checksum': checksum,
    'status': status.name,
  };

  factory TransferFileEntry.fromJson(Map<String, dynamic> json) =>
      TransferFileEntry(
        relativePath: json['relativePath'] as String,
        size: json['size'] as int,
        isDirectory: json['isDirectory'] as bool? ?? false,
        checksum: json['checksum'] as String?,
        status: json['status'] == null
            ? TransferStatus.queued
            : TransferStatus.values.byName(json['status'] as String),
      );
}

class Transfer {
  const Transfer({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.peerName,
    required this.files,
    required this.totalBytes,
    required this.createdAt,
    this.status = TransferStatus.offered,
    this.transferredBytes = 0,
    this.speedBytesPerSecond = 0,
    this.finishedAt,
    this.checksum,
    this.error,
    this.saveDirectory,
  });

  final String id;
  final TransferDirection direction;
  final String peerId;
  final String peerName;
  final List<TransferFileEntry> files;
  final int totalBytes;
  final DateTime createdAt;
  final TransferStatus status;
  final int transferredBytes;
  final double speedBytesPerSecond;
  final DateTime? finishedAt;
  final String? checksum;
  final String? error;
  final String? saveDirectory;

  double get progress =>
      totalBytes == 0 ? 0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);

  bool get isActive => const {
    TransferStatus.offered,
    TransferStatus.queued,
    TransferStatus.connecting,
    TransferStatus.transferring,
    TransferStatus.verifying,
  }.contains(status);

  Transfer copyWith({
    TransferStatus? status,
    int? transferredBytes,
    double? speedBytesPerSecond,
    DateTime? finishedAt,
    String? checksum,
    String? error,
    String? saveDirectory,
  }) {
    return Transfer(
      id: id,
      direction: direction,
      peerId: peerId,
      peerName: peerName,
      files: files,
      totalBytes: totalBytes,
      createdAt: createdAt,
      status: status ?? this.status,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      finishedAt: finishedAt ?? this.finishedAt,
      checksum: checksum ?? this.checksum,
      error: error ?? this.error,
      saveDirectory: saveDirectory ?? this.saveDirectory,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction.name,
    'peerId': peerId,
    'peerName': peerName,
    'files': files.map((f) => f.toJson()).toList(),
    'totalBytes': totalBytes,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'transferredBytes': transferredBytes,
    'speedBytesPerSecond': speedBytesPerSecond,
    'finishedAt': finishedAt?.toIso8601String(),
    'checksum': checksum,
    'error': error,
    'saveDirectory': saveDirectory,
  };

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
    id: json['id'] as String,
    direction: TransferDirection.values.byName(json['direction'] as String),
    peerId: json['peerId'] as String,
    peerName: json['peerName'] as String,
    files: (json['files'] as List<dynamic>)
        .map((e) => TransferFileEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalBytes: json['totalBytes'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: TransferStatus.values.byName(json['status'] as String),
    transferredBytes: json['transferredBytes'] as int? ?? 0,
    speedBytesPerSecond: (json['speedBytesPerSecond'] as num?)?.toDouble() ?? 0,
    finishedAt: json['finishedAt'] == null
        ? null
        : DateTime.parse(json['finishedAt'] as String),
    checksum: json['checksum'] as String?,
    error: json['error'] as String?,
    saveDirectory: json['saveDirectory'] as String?,
  );
}
