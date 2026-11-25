import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../crypto/certificate_manager.dart';
import '../models/manifest.dart';
import '../models/settings.dart';
import '../models/transfer.dart';
import 'protocol.dart';
import 'wishare_client.dart';

class SelectedEntry {
  const SelectedEntry({
    required this.relativePath,
    required this.absolutePath,
    required this.size,
    this.isDirectory = false,
  });

  final String relativePath;
  final String absolutePath;
  final int size;
  final bool isDirectory;
}

/// Builds manifests and drives the sender side of a transfer.
class TransferCoordinator {
  const TransferCoordinator(this._settings);

  final AppSettings _settings;

  /// Expand picked files/folders into a flat, path-safe list.
  Future<List<SelectedEntry>> collect(List<String> paths) async {
    final entries = <SelectedEntry>[];
    for (final path in paths) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.file) {
        final file = File(path);
        entries.add(
          SelectedEntry(
            relativePath: p.basename(path),
            absolutePath: path,
            size: file.lengthSync(),
          ),
        );
      } else if (entity == FileSystemEntityType.directory) {
        final root = Directory(path);
        final rootName = p.basename(path);
        entries.add(
          SelectedEntry(
            relativePath: rootName,
            absolutePath: path,
            size: 0,
            isDirectory: true,
          ),
        );
        var count = 0;
        await for (final child in root.list(
          recursive: true,
          followLinks: false,
        )) {
          count++;
          if (count > _settings.maxFiles) {
            throw StateError('Too many files (limit ${_settings.maxFiles})');
          }
          final relative = p.relative(child.path, from: root.parent.path);
          final depth = p.split(relative).length;
          if (depth > _settings.maxFolderDepth) {
            throw StateError(
              'Folder too deep (limit ${_settings.maxFolderDepth})',
            );
          }
          if (child is Directory) {
            entries.add(
              SelectedEntry(
                relativePath: SafePath.sanitise(relative),
                absolutePath: child.path,
                size: 0,
                isDirectory: true,
              ),
            );
          } else if (child is File) {
            entries.add(
              SelectedEntry(
                relativePath: SafePath.sanitise(relative),
                absolutePath: child.path,
                size: child.lengthSync(),
              ),
            );
          }
        }
      }
    }
    return entries;
  }

  Future<TransferManifest> buildManifest({
    required List<SelectedEntry> entries,
    required DeviceIdentity identity,
    required String transferId,
  }) async {
    final manifestEntries = <TransferFileEntry>[];
    var total = 0;
    for (final entry in entries) {
      if (entry.isDirectory) {
        manifestEntries.add(
          TransferFileEntry(
            relativePath: entry.relativePath,
            size: 0,
            isDirectory: true,
          ),
        );
        continue;
      }
      final checksum = await _checksum(File(entry.absolutePath));
      total += entry.size;
      if (total > _settings.maxTransferBytes) {
        throw StateError('Transfer exceeds size limit');
      }
      manifestEntries.add(
        TransferFileEntry(
          relativePath: entry.relativePath,
          size: entry.size,
          checksum: checksum,
        ),
      );
    }
    return TransferManifest(
      transferId: transferId,
      senderId: identity.id,
      senderName: identity.name,
      rootName: entries.length == 1 ? entries.first.relativePath : 'Files',
      entries: manifestEntries,
      totalBytes: total,
    );
  }

  /// Send all files. Emits progress after every chunk; supports resume from
  /// the receiver's last acknowledged offset.
  Future<void> send({
    required WishareClient client,
    required TransferManifest manifest,
    required List<SelectedEntry> entries,
    required void Function(int transferredBytes, double speed) onProgress,
  }) async {
    var transferred = 0;
    final started = DateTime.now();
    for (final entry in entries.where((e) => !e.isDirectory)) {
      final status = await client.status(
        manifest.transferId,
        relativePath: entry.relativePath,
      );
      var offset = status.offset;
      transferred += offset;
      final file = File(entry.absolutePath);
      final stream = file.openRead(offset, WiProtocol.chunkSize);
      await for (final chunk in stream) {
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        final acknowledged = await client.sendChunk(
          transferId: manifest.transferId,
          relativePath: entry.relativePath,
          offset: offset,
          bytes: bytes,
        );
        offset += acknowledged;
        transferred += acknowledged;
        final seconds =
            DateTime.now().difference(started).inMilliseconds / 1000;
        onProgress(transferred, seconds > 0 ? transferred / seconds : 0);
      }
    }
    await client.complete(manifest.transferId);
  }

  Future<String> _checksum(File file) async {
    final digests = StreamController<Digest>();
    final sink = sha256.startChunkedConversion(digests.sink);
    final result = digests.stream.first.then((digest) => digest.toString());
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    await digests.close();
    return result;
  }
}
