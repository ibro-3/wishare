import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/shared/format.dart';

void main() {
  group('formatSpeed', () {
    test('empty until a rate is known', () {
      expect(formatSpeed(0), isEmpty);
      expect(formatSpeed(-1), isEmpty);
      expect(formatSpeed(double.infinity), isEmpty);
      expect(formatSpeed(double.nan), isEmpty);
    });

    test('scales bytes, kilobytes and megabytes', () {
      expect(formatSpeed(512), '512 B/s');
      expect(formatSpeed(2048), '2.0 KB/s');
      expect(formatSpeed(5 * 1024 * 1024), '5.0 MB/s');
    });
  });

  group('formatProgressDetails', () {
    test('omits unknown rate and empty pieces', () {
      expect(
        formatProgressDetails(speed: 0, remainingBytes: 1024, phase: 'Sending'),
        ' · Sending',
      );
    });

    test('joins phase, rate and ETA in a stable order', () {
      expect(
        formatProgressDetails(
          speed: 1024,
          remainingBytes: 2048,
          phase: 'Transferring',
          leading: '1.0 KB of 3.0 KB',
        ),
        ' · 1.0 KB of 3.0 KB · Transferring · 1.0 KB/s · ETA 2s',
      );
    });
  });

  group('formatEta', () {
    test('empty without remaining bytes or a rate', () {
      expect(formatEta(0, 1024), isEmpty);
      expect(formatEta(1024, 0), isEmpty);
      expect(formatEta(1024, -1), isEmpty);
      expect(formatEta(1024, double.infinity), isEmpty);
      expect(formatEta(1024, double.nan), isEmpty);
    });

    test('rounds up to the next second', () {
      expect(formatEta(1024, 1000), '2s');
      expect(formatEta(100, 100), '1s');
      expect(formatEta(30, 100), '1s');
    });

    test('formats minutes and hours', () {
      expect(formatEta(60 * 1024, 1024), '1m 0s');
      expect(formatEta(90 * 1024, 1024), '1m 30s');
      expect(formatEta(2 * 3600 * 1024 + 5 * 60 * 1024, 1024), '2h 5m');
    });
  });
}
