import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/core/widgets/lute_image.dart';

void main() {
  group('LuteImage', () {
    test('resolveImageUrl resolves null and empty values', () {
      expect(LuteImage.resolveImageUrl(null, 'http://127.0.0.1:5001'), isNull);
      expect(LuteImage.resolveImageUrl('', 'http://127.0.0.1:5001'), isNull);
      expect(LuteImage.resolveImageUrl('   ', 'http://127.0.0.1:5001'), isNull);
      expect(LuteImage.resolveImageUrl('/-', 'http://127.0.0.1:5001'), isNull);
      expect(
        LuteImage.resolveImageUrl('/userimages/1/-', 'http://127.0.0.1:5001'),
        isNull,
      );
    });

    test('resolveImageUrl preserves external URLs and data URIs', () {
      expect(
        LuteImage.resolveImageUrl(
          'https://example.com/pic.jpg',
          'http://127.0.0.1:5001',
        ),
        'https://example.com/pic.jpg',
      );
      expect(
        LuteImage.resolveImageUrl(
          'http://example.com/pic.jpg',
          'http://127.0.0.1:5001',
        ),
        'http://example.com/pic.jpg',
      );
      expect(
        LuteImage.resolveImageUrl(
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
          'http://127.0.0.1:5001',
        ),
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
    });

    test('resolveImageUrl resolves relative server paths properly', () {
      expect(
        LuteImage.resolveImageUrl(
          '/userimages/1/sample.png',
          'http://192.168.1.50:5001',
        ),
        'http://192.168.1.50:5001/userimages/1/sample.png',
      );
      expect(
        LuteImage.resolveImageUrl(
          'userimages/1/sample.png',
          'http://192.168.1.50:5001',
        ),
        'http://192.168.1.50:5001/userimages/1/sample.png',
      );
      expect(
        LuteImage.resolveImageUrl(
          '/userimages/1/sample.png',
          'http://192.168.1.50:5001/',
        ),
        'http://192.168.1.50:5001/userimages/1/sample.png',
      );
    });

    test('isLuteServerUrl accurately identifies Lute server vs public URLs', () {
      const serverUrl = 'http://192.168.1.50:5001';

      // Relative path -> true
      expect(LuteImage.isLuteServerUrl('/userimages/1/pic.jpg', serverUrl), isTrue);
      expect(LuteImage.isLuteServerUrl('userimages/1/pic.jpg', serverUrl), isTrue);

      // Same server full URL -> true
      expect(
        LuteImage.isLuteServerUrl('http://192.168.1.50:5001/userimages/1/pic.jpg', serverUrl),
        isTrue,
      );

      // External public URLs (Bing, Google, etc.) -> false
      expect(
        LuteImage.isLuteServerUrl('https://tse1.mm.bing.net/th?id=OIP.123', serverUrl),
        isFalse,
      );
      expect(
        LuteImage.isLuteServerUrl('https://upload.wikimedia.org/wikipedia/commons/test.jpg', serverUrl),
        isFalse,
      );
      expect(
        LuteImage.isLuteServerUrl('http://192.168.1.50:8080/test.jpg', serverUrl),
        isFalse, // Different port
      );
    });
  });
}
