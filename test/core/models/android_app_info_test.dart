import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/core/models/android_app_info.dart';

void main() {
  group('AndroidAppInfo', () {
    test('fromJson and toJson should round-trip correctly', () {
      final app = AndroidAppInfo(
        packageName: 'com.google.android.apps.translate',
        activityName: 'com.google.android.apps.translate.TranslateActivity',
        label: 'Google Translate',
        iconBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        actionType: 'PROCESS_TEXT',
      );

      final json = app.toJson();
      final fromJson = AndroidAppInfo.fromJson(json);

      expect(fromJson.packageName, equals(app.packageName));
      expect(fromJson.activityName, equals(app.activityName));
      expect(fromJson.label, equals(app.label));
      expect(fromJson.iconBase64, equals(app.iconBase64));
      expect(fromJson.actionType, equals('PROCESS_TEXT'));
      expect(fromJson.id, equals('com.google.android.apps.translate/com.google.android.apps.translate.TranslateActivity'));
      expect(fromJson, equals(app));
    });

    test('copyWith works correctly', () {
      const app = AndroidAppInfo(
        packageName: 'com.eudic.eudic',
        activityName: 'com.eudic.eudic.MainActivity',
        label: 'Eudic',
      );

      final updated = app.copyWith(label: '欧路词典');
      expect(updated.label, equals('欧路词典'));
      expect(updated.packageName, equals('com.eudic.eudic'));
      expect(updated.id, equals('com.eudic.eudic/com.eudic.eudic.MainActivity'));
    });
  });

  group('LocalAppTabConfig', () {
    test('default values are correct', () {
      const config = LocalAppTabConfig();
      expect(config.enabled, isTrue);
      expect(config.defaultAppId, isNull);
      expect(config.autoInvokeDefault, isTrue);
      expect(config.hiddenAppIds, isEmpty);
      expect(config.appOrder, isEmpty);
      expect(config.tabTitle, equals('Apps'));
    });

    test('fromJson and toJson round-trip', () {
      const config = LocalAppTabConfig(
        enabled: true,
        defaultAppId: 'com.eudic.eudic/com.eudic.eudic.MainActivity',
        autoInvokeDefault: false,
        hiddenAppIds: ['com.bad.app/main'],
        appOrder: ['com.eudic.eudic/com.eudic.eudic.MainActivity', 'com.google/main'],
        tabTitle: 'Local Dict',
      );

      final json = config.toJson();
      final fromJson = LocalAppTabConfig.fromJson(json);

      expect(fromJson.enabled, isTrue);
      expect(fromJson.defaultAppId, equals('com.eudic.eudic/com.eudic.eudic.MainActivity'));
      expect(fromJson.autoInvokeDefault, isFalse);
      expect(fromJson.hiddenAppIds, contains('com.bad.app/main'));
      expect(fromJson.appOrder.length, equals(2));
      expect(fromJson.tabTitle, equals('Local Dict'));
      expect(fromJson, equals(config));
    });

    test('copyWith can clear defaultAppId', () {
      const config = LocalAppTabConfig(
        defaultAppId: 'com.eudic.eudic/main',
      );

      final cleared = config.copyWith(clearDefaultAppId: true);
      expect(cleared.defaultAppId, isNull);
    });
  });
}
