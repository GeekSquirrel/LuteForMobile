import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/core/models/android_app_info.dart';

void main() {
  group('AndroidAppInfo', () {
    test('fromJson and toJson should round-trip correctly', () {
      final json = {
        'packageName': 'com.eudic.eudic',
        'activityName': 'com.eudic.eudic.MainActivity',
        'label': '欧路词典',
        'iconBase64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        'actionType': 'PROCESS_TEXT',
      };

      final app = AndroidAppInfo.fromJson(json);

      expect(app.packageName, equals('com.eudic.eudic'));
      expect(app.activityName, equals('com.eudic.eudic.MainActivity'));
      expect(app.label, equals('欧路词典'));
      expect(app.id, equals('com.eudic.eudic/com.eudic.eudic.MainActivity'));
      expect(app.actionType, equals('PROCESS_TEXT'));
      expect(app.iconBase64, isNotNull);

      final outputJson = app.toJson();
      expect(outputJson['packageName'], equals('com.eudic.eudic'));
      expect(outputJson['activityName'], equals('com.eudic.eudic.MainActivity'));
      expect(outputJson['label'], equals('欧路词典'));
      expect(outputJson['actionType'], equals('PROCESS_TEXT'));
      expect(outputJson['iconBase64'], equals(json['iconBase64']));
    });

    test('copyWith works correctly', () {
      const app = AndroidAppInfo(
        packageName: 'com.test.app',
        activityName: 'com.test.app.MainActivity',
        label: 'Test App',
      );

      final modified = app.copyWith(
        label: 'Updated App',
        actionType: 'SEND',
      );

      expect(modified.packageName, equals('com.test.app'));
      expect(modified.activityName, equals('com.test.app.MainActivity'));
      expect(modified.label, equals('Updated App'));
      expect(modified.actionType, equals('SEND'));
      expect(modified.id, equals('com.test.app/com.test.app.MainActivity'));
    });
  });

  group('CustomAppWidgetConfig', () {
    test('resolveText properly substitutes [LUTE] placeholder', () {
      const widgetWithPlaceholder = CustomAppWidgetConfig(
        id: 'w1',
        name: 'Translate',
        template: '翻译 [LUTE]',
        targetAppId: 'com.test.app/main',
        targetAppLabel: 'Test App',
      );

      expect(
        widgetWithPlaceholder.resolveText('hello'),
        equals('翻译 hello'),
      );

      const widgetMultiplePlaceholders = CustomAppWidgetConfig(
        id: 'w2',
        name: 'Define and Example',
        template: '[LUTE] - 请解释 [LUTE] 的用法',
        targetAppId: 'com.test.app/main',
        targetAppLabel: 'Test App',
      );

      expect(
        widgetMultiplePlaceholders.resolveText('apple'),
        equals('apple - 请解释 apple 的用法'),
      );

      const widgetNoPlaceholder = CustomAppWidgetConfig(
        id: 'w3',
        name: 'Lookup',
        template: '查词',
        targetAppId: 'com.test.app/main',
        targetAppLabel: 'Test App',
      );

      expect(
        widgetNoPlaceholder.resolveText('book'),
        equals('查词 book'),
      );

      const widgetEmptyTemplate = CustomAppWidgetConfig(
        id: 'w4',
        name: 'Empty',
        template: '',
        targetAppId: 'com.test.app/main',
        targetAppLabel: 'Test App',
      );

      expect(
        widgetEmptyTemplate.resolveText('world'),
        equals('world'),
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
      expect(config.getHiddenAppIds(isSentence: false), isEmpty);
      expect(config.getHiddenAppIds(isSentence: true), isEmpty);
      expect(config.getAppOrder(isSentence: false), isEmpty);
      expect(config.getAppOrder(isSentence: true), isEmpty);
      expect(config.tabTitle, equals('Apps'));
      expect(config.customWidgets, isEmpty);
    });

    test('fromJson and toJson round-trip with independent term and sentence config', () {
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
        termHiddenAppIds: ['com.bad.app/main'],
        sentenceHiddenAppIds: ['com.another.bad.app/main'],
        termAppOrder: ['custom_1', 'com.eudic.eudic/main'],
        sentenceAppOrder: ['com.google.android.apps.translate/main', 'custom_1'],
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
      expect(fromJson.getHiddenAppIds(isSentence: false), equals(['com.bad.app/main']));
      expect(fromJson.getHiddenAppIds(isSentence: true), equals(['com.another.bad.app/main']));
      expect(fromJson.getAppOrder(isSentence: false), equals(['custom_1', 'com.eudic.eudic/main']));
      expect(fromJson.getAppOrder(isSentence: true), equals(['com.google.android.apps.translate/main', 'custom_1']));
      expect(fromJson.customWidgets.length, equals(1));
      expect(fromJson.customWidgets.first.name, equals('翻译为中文'));
      expect(fromJson, equals(config));
    });

    test('fromJson supports legacy defaultAppId, hiddenAppIds, and appOrder format', () {
      final legacyJson = {
        'enabled': true,
        'defaultAppId': 'com.legacy.app/main',
        'hiddenAppIds': ['com.legacy.hidden/main'],
        'appOrder': ['com.legacy.app/main', 'com.other.app/main'],
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
      expect(config.getHiddenAppIds(isSentence: false), equals(['com.legacy.hidden/main']));
      expect(config.getHiddenAppIds(isSentence: true), equals(['com.legacy.hidden/main']));
      expect(config.getAppOrder(isSentence: false), equals(['com.legacy.app/main', 'com.other.app/main']));
      expect(config.getAppOrder(isSentence: true), equals(['com.legacy.app/main', 'com.other.app/main']));
    });

    test('copyWith can modify term and sentence hidden & order independently', () {
      const config = LocalAppTabConfig(
        termHiddenAppIds: ['term_hidden_1'],
        sentenceHiddenAppIds: ['sent_hidden_1'],
        termAppOrder: ['term_app_1', 'term_app_2'],
        sentenceAppOrder: ['sent_app_1', 'sent_app_2'],
      );

      final updatedTerm = config.copyWith(
        termHiddenAppIds: ['term_hidden_new'],
        termAppOrder: ['term_app_2', 'term_app_1'],
      );
      expect(updatedTerm.getHiddenAppIds(isSentence: false), equals(['term_hidden_new']));
      expect(updatedTerm.getHiddenAppIds(isSentence: true), equals(['sent_hidden_1']));
      expect(updatedTerm.getAppOrder(isSentence: false), equals(['term_app_2', 'term_app_1']));
      expect(updatedTerm.getAppOrder(isSentence: true), equals(['sent_app_1', 'sent_app_2']));

      final updatedSentence = config.copyWith(
        sentenceHiddenAppIds: ['sent_hidden_new'],
        sentenceAppOrder: ['sent_app_2', 'sent_app_1'],
      );
      expect(updatedSentence.getHiddenAppIds(isSentence: false), equals(['term_hidden_1']));
      expect(updatedSentence.getHiddenAppIds(isSentence: true), equals(['sent_hidden_new']));
      expect(updatedSentence.getAppOrder(isSentence: false), equals(['term_app_1', 'term_app_2']));
      expect(updatedSentence.getAppOrder(isSentence: true), equals(['sent_app_2', 'sent_app_1']));
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
