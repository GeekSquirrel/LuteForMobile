import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/core/network/lute_http_client.dart';

void main() {
  group('LuteHttpClient', () {
    test('resolveUrl correctly formats relative and absolute URLs', () {
      final client = LuteHttpClient(baseUrl: 'http://192.168.1.100:5001');

      expect(
        client.resolveUrl('/userimages/1/test.jpg'),
        'http://192.168.1.100:5001/userimages/1/test.jpg',
      );
      expect(
        client.resolveUrl('userimages/1/test.jpg'),
        'http://192.168.1.100:5001/userimages/1/test.jpg',
      );
      expect(
        client.resolveUrl('https://example.com/pic.png'),
        'https://example.com/pic.png',
      );
      expect(
        client.resolveUrl('http://example.com/pic.png'),
        'http://example.com/pic.png',
      );
      expect(client.resolveUrl(''), '');
    });

    test('resolveUrl handles trailing slashes in baseUrl', () {
      final client = LuteHttpClient(baseUrl: 'http://192.168.1.100:5001/');

      expect(
        client.resolveUrl('/read/1/page/1'),
        'http://192.168.1.100:5001/read/1/page/1',
      );
      expect(
        client.resolveUrl('read/1/page/1'),
        'http://192.168.1.100:5001/read/1/page/1',
      );
    });

    test('isLuteServerUri correctly differentiates Lute server from external URIs', () {
      const baseUrl = 'http://192.168.1.100:5001';

      expect(
        LuteHttpClient.isLuteServerUri(Uri.parse('/info'), baseUrl),
        isTrue,
      );
      expect(
        LuteHttpClient.isLuteServerUri(Uri.parse('http://192.168.1.100:5001/info'), baseUrl),
        isTrue,
      );
      expect(
        LuteHttpClient.isLuteServerUri(Uri.parse('https://api.openai.com/v1/chat/completions'), baseUrl),
        isFalse,
      );
      expect(
        LuteHttpClient.isLuteServerUri(Uri.parse('https://tse1.mm.bing.net/image.png'), baseUrl),
        isFalse,
      );
    });

    test('Custom headers are stored and updated in LuteHttpClient', () async {
      final customHeaders = {
        'Authorization': 'Bearer test-token-123',
        'CF-Access-Client-Id': 'client-id-abc',
      };

      final client = LuteHttpClient(
        baseUrl: 'http://127.0.0.1:5001',
        customHeaders: customHeaders,
      );

      // Verify custom headers map is stored
      expect(client.customHeaders['Authorization'], 'Bearer test-token-123');
      expect(client.customHeaders['CF-Access-Client-Id'], 'client-id-abc');
      expect(client.isConfigured, isTrue);

      // Update configuration
      client.updateConfiguration(
        customHeaders: {'X-Custom-Header': 'new-value'},
      );
      expect(client.customHeaders['X-Custom-Header'], 'new-value');
      expect(client.customHeaders.containsKey('Authorization'), isFalse);
    });
  });
}
