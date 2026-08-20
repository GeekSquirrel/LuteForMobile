import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/core/network/dictionary_service.dart';
import 'package:lute_for_mobile/core/services/android_app_service.dart';

void main() {
  group('AndroidAppService applyTabOrder', () {
    late AndroidAppService service;

    setUp(() {
      service = AndroidAppService();
    });

    test('default tab order appends local app item at end when no saved order', () {
      final webviews = [
        const DictionarySource(name: 'Dict A', urlTemplate: 'http://a.com'),
        const DictionarySource(name: 'Dict B', urlTemplate: 'http://b.com'),
      ];
      const localApp = DictionarySource(
        name: 'Apps',
        urlTemplate: '',
        isAndroidApp: true,
      );

      final result = service.applyTabOrder<DictionarySource>(
        originalItems: webviews,
        getId: (d) => d.name,
        savedOrder: [],
        localAppItem: localApp,
        includeLocalApp: true,
      );

      expect(result.length, equals(3));
      expect(result[0].name, equals('Dict A'));
      expect(result[1].name, equals('Dict B'));
      expect(result[2].name, equals('Apps'));
      expect(result[2].isAndroidApp, isTrue);
    });

    test('custom saved tab order places local app tab first if configured', () {
      final webviews = [
        const DictionarySource(name: 'Dict A', urlTemplate: 'http://a.com'),
        const DictionarySource(name: 'Dict B', urlTemplate: 'http://b.com'),
      ];
      const localApp = DictionarySource(
        name: 'Apps',
        urlTemplate: '',
        isAndroidApp: true,
      );

      final result = service.applyTabOrder<DictionarySource>(
        originalItems: webviews,
        getId: (d) => d.name,
        savedOrder: [AndroidAppService.localAppsTabId, 'Dict B', 'Dict A'],
        localAppItem: localApp,
        includeLocalApp: true,
      );

      expect(result.length, equals(3));
      expect(result[0].name, equals('Apps'));
      expect(result[0].isAndroidApp, isTrue);
      expect(result[1].name, equals('Dict B'));
      expect(result[2].name, equals('Dict A'));
    });

    test('newly added webviews are appended if not in saved order', () {
      final webviews = [
        const DictionarySource(name: 'Dict A', urlTemplate: 'http://a.com'),
        const DictionarySource(name: 'Dict B', urlTemplate: 'http://b.com'),
        const DictionarySource(name: 'Dict C (New)', urlTemplate: 'http://c.com'),
      ];
      const localApp = DictionarySource(
        name: 'Apps',
        urlTemplate: '',
        isAndroidApp: true,
      );

      final result = service.applyTabOrder<DictionarySource>(
        originalItems: webviews,
        getId: (d) => d.name,
        savedOrder: ['Dict B', AndroidAppService.localAppsTabId],
        localAppItem: localApp,
        includeLocalApp: true,
      );

      expect(result.length, equals(4));
      expect(result[0].name, equals('Dict B'));
      expect(result[1].name, equals('Apps'));
      expect(result[2].name, equals('Dict A'));
      expect(result[3].name, equals('Dict C (New)'));
    });
  });
}
