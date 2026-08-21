import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/android_app_info.dart';

class AndroidAppService {
  static const String localAppsTabId = '__android_local_apps__';
  static const String imagesTabId = '__images_tab__';
  static const String channelName = 'com.schlick7.luteformobile/android_apps';
  static const String configPrefsKey = 'local_android_app_config';

  final MethodChannel _channel;
  List<AndroidAppInfo>? _cachedApps;

  AndroidAppService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  bool get isSupportedPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<List<AndroidAppInfo>> getInstalledApps({
    bool forceRefresh = false,
  }) async {
    if (!isSupportedPlatform) return [];

    if (_cachedApps != null && !forceRefresh) {
      return _cachedApps!;
    }

    try {
      final List<dynamic>? rawApps =
          await _channel.invokeListMethod<dynamic>('getInstalledTextApps');

      if (rawApps == null) {
        _cachedApps = [];
        return [];
      }

      final apps = rawApps.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return AndroidAppInfo.fromJson(map);
      }).toList();

      // Sort alphabetically by label by default
      apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      _cachedApps = apps;
      return apps;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error querying installed text apps: ${e.message}');
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Unexpected error getting text apps: $e');
      }
      return [];
    }
  }

  Future<bool> launchApp(AndroidAppInfo app, String text) async {
    if (!isSupportedPlatform) return false;

    try {
      final result = await _channel.invokeMethod<bool>('launchAppWithText', {
        'packageName': app.packageName,
        'activityName': app.activityName,
        'actionType': app.actionType,
        'text': text,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error launching app ${app.packageName}: ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Unexpected error launching app: $e');
      }
      return false;
    }
  }

  Future<bool> launchAppById(String appId, String text) async {
    final apps = await getInstalledApps();
    final app = apps.where((a) => a.id == appId).firstOrNull;
    if (app == null) return false;
    return launchApp(app, text);
  }

  Future<LocalAppTabConfig> getAppConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(configPrefsKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return const LocalAppTabConfig();
    }

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return LocalAppTabConfig.fromJson(map);
    } catch (e) {
      if (kDebugMode) {
        print('Error reading LocalAppTabConfig: $e');
      }
      return const LocalAppTabConfig();
    }
  }

  Future<void> saveAppConfig(LocalAppTabConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(config.toJson());
    await prefs.setString(configPrefsKey, jsonStr);
  }

  String _tabOrderKey(int languageId, bool isSentence) {
    return 'tab_order_${isSentence ? 'sentences' : 'terms'}_$languageId';
  }

  Future<List<String>> getTabOrder(
    int languageId, {
    bool isSentence = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_tabOrderKey(languageId, isSentence));
    return list ?? [];
  }

  Future<void> saveTabOrder(
    int languageId,
    List<String> tabOrder, {
    bool isSentence = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_tabOrderKey(languageId, isSentence), tabOrder);
  }

  /// Sorts items based on saved tab order, inserting local app / images items if enabled.
  List<T> applyTabOrder<T>({
    required List<T> originalItems,
    required String Function(T) getId,
    required List<String> savedOrder,
    T? localAppItem,
    bool includeLocalApp = true,
    T? imagesItem,
    bool includeImages = true,
    Map<String, T>? extraItems,
  }) {
    final allAvailableMap = <String, T>{};
    for (final item in originalItems) {
      allAvailableMap[getId(item)] = item;
    }

    if (includeLocalApp && localAppItem != null) {
      allAvailableMap[localAppsTabId] = localAppItem;
    }

    if (includeImages && imagesItem != null) {
      allAvailableMap[imagesTabId] = imagesItem;
    }

    if (extraItems != null) {
      allAvailableMap.addAll(extraItems);
    }

    if (savedOrder.isEmpty) {
      // Default: original items followed by extra/special items
      final result = List<T>.from(originalItems);
      if (includeImages && imagesItem != null) {
        result.add(imagesItem);
      }
      if (includeLocalApp && localAppItem != null) {
        result.add(localAppItem);
      }
      if (extraItems != null) {
        for (final entry in extraItems.entries) {
          if (!result.contains(entry.value)) {
            result.add(entry.value);
          }
        }
      }
      return result;
    }

    final result = <T>[];
    final consumedKeys = <String>{};

    for (final key in savedOrder) {
      final item = allAvailableMap[key];
      if (item != null) {
        result.add(item);
        consumedKeys.add(key);
      }
    }

    // Append any items that were not in savedOrder (e.g. newly added dictionaries)
    for (final entry in allAvailableMap.entries) {
      if (!consumedKeys.contains(entry.key)) {
        result.add(entry.value);
      }
    }

    return result;
  }
}
