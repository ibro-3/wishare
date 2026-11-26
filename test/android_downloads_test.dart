import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/platform/android_downloads.dart';

void main() {
  test('download file name is a safe basename', () {
    expect(
      AndroidDownloads.downloadFileName('wishare-0.4.0-android.apk'),
      'wishare-0.4.0-android.apk',
    );
    expect(
      AndroidDownloads.downloadFileName(
        'https://example.test/a/b/../evil.apk?token=1',
      ),
      'evil.apk_token_1',
    );
    expect(
      AndroidDownloads.downloadFileName(r'C:\Downloads\wishare.apk'),
      'wishare.apk',
    );
    expect(AndroidDownloads.downloadFileName('   '), 'wishare-update.apk');
    expect(AndroidDownloads.downloadFileName('/'), 'wishare-update.apk');
  });

  test('enqueue is a no-op off Android', () async {
    if (AndroidDownloads.isSupported) return;
    expect(
      await AndroidDownloads.enqueue(
        url: 'https://example.test/app.apk',
        fileName: 'app.apk',
        title: 'Wishare update',
      ),
      isNull,
    );
  });
}
