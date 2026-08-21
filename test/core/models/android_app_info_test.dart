import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/core/models/android_app_info.dart';

void main() {
  group('AndroidAppInfo', () {
    test('fromJson and toJson should round-trip correctly', () {
      final app = AndroidAppInfo(
        packageName: 'com.google.android.apps.translate',
        activityName: 'com.google.android.apps.translate.TranslateActivity',
        label: 'Google Translate',
        iconBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        actionType: 'PROCESS_TEXT',
      );

      final json = app.toJson();
      final fromJson = AndroidAppInfo.fromJson(json);

      expect(fromJson.packageName, equals(app.packageName));
      expect(fromJson.activityName, equals(app.activityName));
      expect(fromJson.label, equals(app.label));
      expect(fromJson.iconBase64, equals(app.iconBase64));
      expect(fromJson.actionType, equals('PROCESS_TEXT'));
      expect(
        fromJson.id,
        equals(
          'com.google.android.apps.translate/com.google.android.apps.translate.TranslateActivity',
        ),
      );
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
      expect(
        updated.id,
        equals('com.eudic.eudic/com.eudic.eudic.MainActivity'),
      );
    });
  });

  group('LocalAppTabConfig', () {
    test('default values are correct', () {
      const config = LocalAppTabConfig();
      expect(config.enabled, isTrue);
      expect(config.defaultTermAppId, isNull);
      expect(config.defaultSentenceAppId, isNull);
      expect(config.defaultAppId, isNull);
      expect(config.getDefaultAppId(isSentence: false), isNull);
      expect(config.getDefaultAppId(isSentence: true), isNull);
      expect(config.autoInvokeDefault, isTrue);
      expect(config.hiddenAppIds, isEmpty);
      expect(config.appOrder, isEmpty);
      expect(config.tabTitle, equals('Apps'));
    });

    test('fromJson and toJson round-trip with separate term and sentence defaults', () {
      const config = LocalAppTabConfig(
        enabled: true,
        defaultTermAppId: 'com.eudic.eudic/com.eudic.eudic.MainActivity',
        defaultSentenceAppId: 'com.google.android.apps.translate/main',
        autoInvokeDefault: false,
        hiddenAppIds: ['com.bad.app/main'],
        appOrder: [
          'com.eudic.eudic/com.eudic.eudic.MainActivity',
          'com.google/main',
        ],
        tabTitle: 'Local Dict',
      );

      final json = config.toJson();
      final fromJson = LocalAppTabConfig.fromJson(json);

      expect(fromJson.enabled, isTrue);
      expect(
        fromJson.defaultTermAppId,
        equals('com.eudic.eudic/com.eudic.eudic.MainActivity'),
      );
      expect(
        fromJson.defaultSentenceAppId,
        equals('com.google.android.apps.translate/main'),
      );
      expect(
        fromJson.getDefaultAppId(isSentence: false),
        equals('com.eudic.eudic/com.eudic.eudic.MainActivity'),
      );
      expect(
        fromJson.getDefaultAppId(isSentence: true),
        equals('com.google.android.apps.translate/main'),
      );
      expect(fromJson.autoInvokeDefault, isFalse);
      expect(fromJson.hiddenAppIds, contains('com.bad.app/main'));
      expect(fromJson.appOrder.length, equals(2));
      expect(fromJson.tabTitle, equals('Local Dict'));
      expect(fromJson, equals(config));
    });

    test('fromJson supports legacy defaultAppId format', () {
      final legacyJson = {
        'enabled': true,
        'defaultAppId': 'com.legacy.app/main',
        'autoInvokeDefault': true,
      };

      final config = LocalAppTabConfig.fromJson(legacyJson);
      expect(config.defaultTermAppId, equals('com.legacy.app/main'));
      expect(config.defaultAppId, equals('com.legacy.app/main'));
      expect(config.getDefaultAppId(isSentence: false), equals('com.legacy.app/main'));
      expect(config.defaultSentenceAppId, isNull);
    });

    test('copyWith can clear defaultTermAppId and defaultSentenceAppId independently', () {
      const config = LocalAppTabConfig(
        defaultTermAppId: 'com.eudic.eudic/main',
        defaultSentenceAppId: 'com.google.translate/main',
      );

      // Clear term default only
      final clearedTerm = config.copyWith(clearDefaultTermAppId: true);
      expect(clearedTerm.defaultTermAppId, isNull);
      expect(clearedTerm.getDefaultAppId(isSentence: false), isNull);
      expect(clearedTerm.defaultSentenceAppId, equals('com.google.translate/main'));

      // Clear sentence default only
      final clearedSentence = config.copyWith(clearDefaultSentenceAppId: true);
      expect(clearedSentence.defaultTermAppId, equals('com.eudic.eudic/main'));
      expect(clearedSentence.defaultSentenceAppId, isNull);
      expect(clearedSentence.getDefaultAppId(isSentence: true), isNull);

      // Update term and sentence defaults
      final updated = config.copyWith(
        defaultTermAppId: 'com.new.term/main',
        defaultSentenceAppId: 'com.new.sentence/main',
      );
      expect(updated.getDefaultAppId(isSentence: false), equals('com.new.term/main'));
      expect(updated.getDefaultAppId(isSentence: true), equals('com.new.sentence/main'));
    });
  });
}
