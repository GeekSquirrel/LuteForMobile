import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:lute_for_mobile/app.dart';
import 'package:lute_for_mobile/core/network/api_service.dart';
import 'package:lute_for_mobile/core/network/tts_service.dart';
import 'package:lute_for_mobile/core/providers/initial_providers.dart';
import 'package:lute_for_mobile/core/services/backup_service.dart';
import 'package:lute_for_mobile/core/services/display_mode_service.dart';
import 'package:lute_for_mobile/core/services/server_health_service.dart';
import 'package:lute_for_mobile/core/services/termux_service.dart';
import 'package:lute_for_mobile/features/settings/models/settings.dart';
import 'package:lute_for_mobile/hive_registrar.g.dart';
import 'package:lute_for_mobile/shared/providers/server_status_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, String> _loadCustomHeaders(SharedPreferences prefs) {
  final value = prefs.getString('custom_headers');
  if (value == null || value.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return Map<String, String>.fromEntries(
        decoded.entries
            .where((entry) => entry.key is String && entry.value is String)
            .map(
              (entry) => MapEntry(entry.key as String, entry.value as String),
            ),
      );
    }
  } catch (_) {}
  return {};
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 300;

  // Pre-warm the on-device TTS engine on the main thread to prevent a native
  // crash on OnePlus/Oplus devices when TextToSpeech is created during speak().
  if (!kIsWeb) {
    Future.delayed(const Duration(seconds: 3), () {
      OnDeviceTTSService.warmUp();
    });
  }

  try {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('main.dart: SharedPreferences init fallback: $e');
    }

    final localUrl = prefs?.getString('local_url') ?? '';
    final useTermux = prefs?.getBool('use_termux') ?? false;
    final serverUrl = useTermux ? Settings.termuxUrl : localUrl;
    final customHeaders = prefs != null ? _loadCustomHeaders(prefs) : <String, String>{};
    BackupService.setHeaders(customHeaders);

    final enableHighRefreshRate = prefs?.getBool('enable_high_refresh_rate') ?? true;
    unawaited(DisplayModeService.applyDisplayMode(enableHighRefreshRate: enableHighRefreshRate));

    if (kIsWeb) {
      await Hive.initFlutter();
    } else {
      final cacheDir = await getApplicationCacheDirectory();
      await Hive.initFlutter(cacheDir.path);
    }
    Hive.registerAdapters();

    ServerStatusManager.setConnecting();

    unawaited(_performInitialHealthChecks(serverUrl, useTermux, customHeaders));

    runApp(
      ProviderScope(
        overrides: [initialServerUrlProvider.overrideWithValue(serverUrl)],
        child: const App(),
      ),
    );
  } catch (e, stack) {
    debugPrint('main.dart initialization error: $e\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Initialization Error: $e',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _performInitialHealthChecks(
  String serverUrl,
  bool useTermux,
  Map<String, String> customHeaders,
) async {
  try {
    Future<bool>? androidHealthCheck;
    if (useTermux && serverUrl == Settings.termuxUrl) {
      androidHealthCheck = TermuxService.isServerRunning(serverUrl);
    }

    if (androidHealthCheck != null) {
      try {
        final isRunning = await androidHealthCheck.timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        ServerStatusManager.setReachable(isRunning);
      } catch (_) {
        ServerStatusManager.setReachable(false);
      }
    } else if (serverUrl.isNotEmpty) {
      try {
        final isServerReachable = await ServerHealthService.isReachable(
          serverUrl,
          headers: customHeaders,
        ).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        ServerStatusManager.setReachable(isServerReachable);
      } catch (_) {
        ServerStatusManager.setReachable(false);
      }
    } else {
      ServerStatusManager.setReachable(false);
    }
  } catch (e) {
    debugPrint('Health check error: $e');
  } finally {
    ServerStatusManager.setInitialCheckComplete(true);
    if (serverUrl.isNotEmpty) {
      try {
        final apiService = ApiService(
          baseUrl: serverUrl,
          headers: customHeaders,
        );
        apiService.triggerAutoBackup();
      } catch (_) {}
    }
  }
}
