import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/certificate_manager.dart';
import '../models/peer.dart';
import '../models/parse_helpers.dart';
import '../models/settings.dart';
import '../models/transfer.dart';

/// Local persistence. My design decision: SharedPreferences + JSON is enough
/// for v0.1; the interface is intentionally repository-shaped so it can be
/// swapped for drift/SQLite without touching feature code.
class AppStore {
  AppStore(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'settings';
  static const _peersKey = 'peers';
  static const _transfersKey = 'transfers';

  static Future<AppStore> create() async =>
      AppStore(await SharedPreferences.getInstance());

  CertificateManager get certificates => CertificateManager(_prefs);

  Future<AppSettings> loadSettings() async {
    final raw = _prefs.getString(_settingsKey);
    final fallback = await AppSettings.defaultDownloadDirectory();
    if (raw == null) return AppSettings.initial(fallback);
    try {
      final decoded = json.decode(raw);
      final map = object(decoded);
      if (map == null) return AppSettings.initial(fallback);
      return AppSettings.fromJson(map, fallback);
    } on Object {
      // Corrupt preferences must never prevent the app from starting.
      return AppSettings.initial(fallback);
    }
  }

  Future<void> saveSettings(AppSettings settings) =>
      _prefs.setString(_settingsKey, json.encode(settings.toJson()));

  List<Peer> loadPeers() {
    final raw = _prefs.getString(_peersKey);
    if (raw == null) return const <Peer>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const <Peer>[];
      return decoded
          .map((entry) {
            final map = object(entry);
            if (map == null) return null;
            final peer = Peer.fromJson(map);
            // Skip unusable records instead of letting them poison the list.
            if (peer.id.isEmpty || peer.address.isEmpty || peer.port < 1) {
              return null;
            }
            return peer;
          })
          .whereType<Peer>()
          .toList();
    } on Object {
      return const <Peer>[];
    }
  }

  Future<void> savePeers(List<Peer> peers) => _prefs.setString(
    _peersKey,
    json.encode(peers.map((p) => p.toJson()).toList()),
  );

  List<Transfer> loadTransfers() {
    final raw = _prefs.getString(_transfersKey);
    if (raw == null) return const <Transfer>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const <Transfer>[];
      return decoded
          .map((entry) {
            final map = object(entry);
            if (map == null) return null;
            final transfer = Transfer.fromJson(map);
            return transfer.id.isEmpty ? null : transfer;
          })
          .whereType<Transfer>()
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on Object {
      return const <Transfer>[];
    }
  }

  Future<void> saveTransfers(List<Transfer> transfers) => _prefs.setString(
    _transfersKey,
    json.encode(transfers.take(200).map((t) => t.toJson()).toList()),
  );
}
