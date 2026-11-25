import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/certificate_manager.dart';
import '../models/peer.dart';
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
    return AppSettings.fromJson(
      json.decode(raw) as Map<String, dynamic>,
      fallback,
    );
  }

  Future<void> saveSettings(AppSettings settings) =>
      _prefs.setString(_settingsKey, json.encode(settings.toJson()));

  List<Peer> loadPeers() {
    final raw = _prefs.getString(_peersKey);
    if (raw == null) return const [];
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => Peer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> savePeers(List<Peer> peers) => _prefs.setString(
    _peersKey,
    json.encode(peers.map((p) => p.toJson()).toList()),
  );

  List<Transfer> loadTransfers() {
    final raw = _prefs.getString(_transfersKey);
    if (raw == null) return const [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => Transfer.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveTransfers(List<Transfer> transfers) => _prefs.setString(
    _transfersKey,
    json.encode(transfers.take(200).map((t) => t.toJson()).toList()),
  );
}
