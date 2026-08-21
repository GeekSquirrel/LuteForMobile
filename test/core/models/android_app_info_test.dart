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

  group('CustomAppWidgetConfig', () {
    test('resolveText properly substitutes [LUTE] placeholder', () {
      const widgetWithPlaceholder = CustomAppWidgetConfig(
        id: 'custom_1',
        name: '翻译为中文',
        template: '翻译 [LUTE]',
        targetAppId: 'com.eudic.eudic/main',
        targetAppLabel: '欧路词典',
      );

      expect(
        widgetWithPlaceholder.resolveText('hello'),
        equals('翻译 hello'),
      );

      const widgetWithMultiplePlaceholder = CustomAppWidgetConfig(
        id: 'custom_2',
        name: '多重占位',
        template: '词汇:[LUTE] 含义:[LUTE]',
        targetAppId: 'com.google/main',
        targetAppLabel: 'Google',
      );

      expect(
        widgetWithMultiplePlaceholder.resolveText('apple'),
        equals('词汇:apple 含义:apple'),
      );

      const widgetWithoutPlaceholder = CustomAppWidgetConfig(
        id: 'custom_3',
        name: '无占位符',
        template: 'Define:',
        targetAppId: 'com.google/main',
        targetAppLabel: 'Google',
      );

      expect(
        widgetWithoutPlaceholder.resolveText('apple'),
        equals('Define: apple'),
      );

      const widgetEmptyTemplate = CustomAppWidgetConfig(
        id: 'custom_4',
        name: '空模板',
        template: '',
        targetAppId: 'com.google/main',
        targetAppLabel: 'Google',
      );

      expect(
        widgetEmptyTemplate.resolveText('apple'),
        equals('apple'),
      );
    });

    test('fromJson and toJson round-trip correctly', () {
      const widget = CustomAppWidgetConfig(
        id: 'custom_12345',
        name: '语法分析',
        template: '分析句子语法结构：[LUTE]',
        targetAppId: 'com.chatgpt.app/main',
        targetAppLabel: 'ChatGPT',
        targetAppIconBase64: 'base64icon',
        actionType: 'SEND',
        colorValue: 0xFF123456,
      );

      final json = widget.toJson();
      final fromJson = CustomAppWidgetConfig.fromJson(json);

      expect(fromJson.id, equals('custom_12345'));
      expect(fromJson.name, equals('语法分析'));
      expect(fromJson.template, equals('分析句子语法结构：[LUTE]'));
      expect(fromJson.targetAppId, equals('com.chatgpt.app/main'));
      expect(fromJson.targetAppLabel, equals('ChatGPT'));
      expect(fromJson.targetAppIconBase64, equals('base64icon'));
      expect(fromJson.actionType, equals('SEND'));
      expect(fromJson.colorValue, equals(0xFF123456));
      expect(fromJson, equals(widget));
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
      expect(config.customWidgets, isEmpty);
    });

    test('fromJson and toJson round-trip with customWidgets', () {
      const customWidget = CustomAppWidgetConfig(
        id: 'custom_1',
        name: '翻译为中文',
        template: '翻译 [LUTE]',
        targetAppId: 'com.eudic.eudic/main',
        targetAppLabel: '欧路词典',
      );

      const config = LocalAppTabConfig(
        enabled: true,
        defaultTermAppId: 'custom_1',
        defaultSentenceAppId: 'com.google.android.apps.translate/main',
        autoInvokeDefault: false,
        hiddenAppIds: ['com.bad.app/main'],
        appOrder: [
          'custom_1',
          'com.eudic.eudic/main',
        ],
        tabTitle: 'Local Dict',
        customWidgets: [customWidget],
      );

      final json = config.toJson();
      final fromJson = LocalAppTabConfig.fromJson(json);

      expect(fromJson.enabled, isTrue);
      expect(fromJson.defaultTermAppId, equals('custom_1'));
      expect(
        fromJson.defaultSentenceAppId,
        equals('com.google.android.apps.translate/main'),
      );
      expect(fromJson.getDefaultAppId(isSentence: false), equals('custom_1'));
      expect(
        fromJson.getDefaultAppId(isSentence: true),
        equals('com.google.android.apps.translate/main'),
      );
      expect(fromJson.customWidgets.length, equals(1));
      expect(fromJson.customWidgets.first.name, equals('翻译为中文'));
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
      expect(
        config.getDefaultAppId(isSentence: false),
        equals('com.legacy.app/main'),
      );
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
      expect(
        clearedTerm.defaultSentenceAppId,
        equals('com.google.translate/main'),
      );

      // Clear sentence default only
      final clearedSentence =
          config.copyWith(clearDefaultSentenceAppId: true);
      expect(clearedSentence.defaultTermAppId, equals('com.eudic.eudic/main'));
      expect(clearedSentence.defaultSentenceAppId, isNull);
      expect(clearedSentence.getDefaultAppId(isSentence: true), isNull);

      // Update term and sentence defaults
      final updated = config.copyWith(
        defaultTermAppId: 'com.new.term/main',
        defaultSentenceAppId: 'com.new.sentence/main',
      );
      expect(
        updated.getDefaultAppId(isSentence: false),
        equals('com.new.term/main'),
      );
      expect(
        updated.getDefaultAppId(isSentence: true),
        equals('com.new.sentence/main'),
      );
    });
  });
}
