import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../shared/providers/server_status_provider.dart';

/// Unified base HTTP client for all communications with the Lute server.
/// Manages base URL, default headers, custom headers injection, logging,
/// retry logic, and server status updates.
class LuteHttpClient {
  final Dio dio;
  String _baseUrl;
  Map<String, String> _customHeaders;
  static bool enableLogging = kDebugMode;

  LuteHttpClient({
    required String baseUrl,
    Map<String, String> customHeaders = const {},
    Dio? customDio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 10),
  })  : _baseUrl = baseUrl,
        _customHeaders = Map<String, String>.unmodifiable(customHeaders),
        dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: connectTimeout,
                receiveTimeout: receiveTimeout,
                sendTimeout: sendTimeout,
                headers: {'Content-Type': 'text/html'},
                followRedirects: false,
                validateStatus: (status) => status != null && status < 400,
              ),
            ) {
    _setupInterceptors();
  }

  String get baseUrl => _baseUrl;
  Map<String, String> get customHeaders => _customHeaders;
  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  void updateConfiguration({
    String? baseUrl,
    Map<String, String>? customHeaders,
  }) {
    if (baseUrl != null) {
      _baseUrl = baseUrl;
      dio.options.baseUrl = baseUrl;
    }
    if (customHeaders != null) {
      _customHeaders = Map<String, String>.unmodifiable(customHeaders);
    }
  }

  void _setupInterceptors() {
    // 1. Custom Headers Interceptor: Injects latest custom_headers only into requests targeting the Lute server
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (isLuteServerUri(options.uri, _baseUrl) &&
              _customHeaders.isNotEmpty) {
            for (final entry in _customHeaders.entries) {
              if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
                options.headers[entry.key] = entry.value;
              }
            }
          }
          return handler.next(options);
        },
      ),
    );

    // 2. Status tracking Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          ServerStatusManager.markSuccess();
          return handler.next(response);
        },
        onError: (error, handler) {
          ServerStatusManager.markError();
          return handler.next(error);
        },
      ),
    );

    // 3. Retry Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (_shouldRetry(error)) {
            final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
            if (retryCount < 1) {
              error.requestOptions.extra['retryCount'] = retryCount + 1;
              await Future.delayed(const Duration(milliseconds: 200));
              try {
                final response = await dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } catch (e) {
                return handler.next(error);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );

    // 4. Logging Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (enableLogging) {
            debugPrint('LUTE HTTP REQ: [${options.method}] ${options.uri}');
            if (options.data != null) {
              debugPrint('  Data: ${options.data}');
            }
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (enableLogging) {
            debugPrint(
              'LUTE HTTP RESP: [${response.requestOptions.method}] ${response.requestOptions.uri} - ${response.statusCode}',
            );
          }
          return handler.next(response);
        },
        onError: (error, handler) {
          if (enableLogging) {
            debugPrint(
              'LUTE HTTP ERR: [${error.requestOptions.method}] ${error.requestOptions.uri} - ${error.type} ${error.message}',
            );
          }
          return handler.next(error);
        },
      ),
    );
  }

  bool _shouldRetry(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    if (error.type == DioExceptionType.connectionError) {
      return true;
    }
    if (error.type == DioExceptionType.badResponse) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null &&
          (statusCode == 502 || statusCode == 503 || statusCode == 504)) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether a given [uri] targets the Lute [baseUrl].
  static bool isLuteServerUri(Uri uri, String baseUrl) {
    if (baseUrl.trim().isEmpty) return false;
    try {
      final baseUri = Uri.parse(baseUrl.trim());
      if (!uri.hasScheme || uri.host.isEmpty) return true;

      final isSameHost = uri.host.toLowerCase() == baseUri.host.toLowerCase();
      final uriPort =
          uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final basePort =
          baseUri.hasPort ? baseUri.port : (baseUri.scheme == 'https' ? 443 : 80);

      return isSameHost && uriPort == basePort;
    } catch (_) {
      return false;
    }
  }

  /// Resolves a path (relative or absolute) to a full URL against [baseUrl].
  String resolveUrl(String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final cleanBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$cleanBase$cleanPath';
  }

  // --- Base HTTP Methods ---

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response<T>> head<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.head<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> request<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return dio.request<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
