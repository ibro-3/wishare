String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Human-readable transfer rate. Returns an empty string until the first
/// progress update, so callers can hide the separator until there is a value.
String formatSpeed(double bytesPerSecond) =>
    bytesPerSecond.isFinite && bytesPerSecond > 0
    ? '${formatSize(bytesPerSecond.toInt())}/s'
    : '';

/// Compact " · phase · rate · ETA" suffix shared by the send progress row and
/// the transfer detail sheet. [leading] is used where byte counts are shown.
String formatProgressDetails({
  required double speed,
  required int remainingBytes,
  String? phase,
  String? leading,
}) {
  final rate = formatSpeed(speed);
  final eta = formatEta(remainingBytes, speed);
  return [
    if (leading != null && leading.isNotEmpty) leading,
    if (phase != null && phase.isNotEmpty) phase,
    if (rate.isNotEmpty) rate,
    if (eta.isNotEmpty) 'ETA $eta',
  ].map((part) => ' · $part').join();
}

/// Estimated time to transfer [remainingBytes] at [bytesPerSecond].
/// Returns an empty string when there is not enough information to estimate.
String formatEta(int remainingBytes, double bytesPerSecond) {
  if (remainingBytes <= 0 || !bytesPerSecond.isFinite || bytesPerSecond <= 0) {
    return '';
  }
  final seconds = (remainingBytes / bytesPerSecond).ceil();
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
