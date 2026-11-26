import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../update/update_service.dart';
import 'providers.dart';

enum UpdateStatus { idle, checking, available, upToDate, error }

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.checkedAt,
    this.error,
    this.dismissed = false,
  });

  final UpdateStatus status;
  final UpdateInfo? info;
  final DateTime? checkedAt;
  final String? error;
  final bool dismissed;

  /// "Later" hides the app-bar badge without hiding the update in Settings.
  bool get showBadge => status == UpdateStatus.available && !dismissed;

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    DateTime? checkedAt,
    String? error,
    bool? dismissed,
  }) => UpdateState(
    status: status ?? this.status,
    info: info ?? this.info,
    checkedAt: checkedAt ?? this.checkedAt,
    error: error ?? this.error,
    dismissed: dismissed ?? this.dismissed,
  );
}

/// Overridable in tests so no widget test performs a real network request.
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final updateProvider = AsyncNotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);

class UpdateController extends AsyncNotifier<UpdateState> {
  /// My design decision (not in M3): passive checks are cached for 15 minutes
  /// so startup does not hit the network on every fast restart. Manual checks
  /// always force a fresh request.
  static const cacheDuration = Duration(minutes: 15);

  bool _inFlight = false;
  DateTime? _lastAttempt;

  @override
  Future<UpdateState> build() async => const UpdateState();

  Future<void> checkSilently() async {
    if (ref.read(settingsProvider).value?.autoUpdateCheck != true) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < cacheDuration) {
      return;
    }
    await _check(silent: true);
  }

  Future<void> checkNow() => _check(silent: false);

  Future<void> _check({required bool silent}) async {
    if (_inFlight) return;
    _inFlight = true;
    _lastAttempt = DateTime.now();
    final previous = state.value ?? const UpdateState();
    state = AsyncData(previous.copyWith(status: UpdateStatus.checking));
    try {
      final info = await ref.read(updateServiceProvider).checkLatest();
      state = AsyncData(
        UpdateState(
          status: info == null ? UpdateStatus.upToDate : UpdateStatus.available,
          info: info,
          checkedAt: DateTime.now(),
        ),
      );
    } on Object catch (error) {
      // A background failure must not interrupt the user; a manual failure
      // gets a snackbar with a Retry action.
      state = AsyncData(
        silent
            ? previous.copyWith(status: UpdateStatus.idle)
            : UpdateState(
                status: UpdateStatus.error,
                error: error is UpdateException
                    ? error.message
                    : 'Unexpected error',
                checkedAt: DateTime.now(),
              ),
      );
    } finally {
      _inFlight = false;
    }
  }

  void dismiss() {
    final current = state.value;
    if (current == null || current.info == null) return;
    state = AsyncData(current.copyWith(dismissed: true));
  }
}

/// Watched once by [WishareApp]; Riverpod providers are lazy, so this is the
/// single startup trigger. It waits for settings before checking the toggle.
final startupUpdateCheckProvider = FutureProvider<void>((ref) async {
  await ref.read(settingsProvider.future);
  await ref.read(updateProvider.notifier).checkSilently();
});
