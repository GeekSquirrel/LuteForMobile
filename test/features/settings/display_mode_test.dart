import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/features/settings/models/settings.dart';

void main() {
  group('High Refresh Rate Settings', () {
    test('defaultSettings enables high refresh rate by default', () {
      final settings = Settings.defaultSettings();
      expect(settings.enableHighRefreshRate, isTrue);
    });

    test('copyWith updates enableHighRefreshRate correctly', () {
      final settings = Settings.defaultSettings();
      final updated = settings.copyWith(enableHighRefreshRate: false);
      expect(updated.enableHighRefreshRate, isFalse);

      final reEnabled = updated.copyWith(enableHighRefreshRate: true);
      expect(reEnabled.enableHighRefreshRate, isTrue);
    });
  });
}
