import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/android_app_info.dart';
import '../services/android_app_service.dart';

final androidAppServiceProvider = Provider<AndroidAppService>((ref) {
  return AndroidAppService();
});

final installedAppsProvider =
    FutureProvider.autoDispose<List<AndroidAppInfo>>((ref) async {
      final service = ref.watch(androidAppServiceProvider);
      return service.getInstalledApps();
    });

class LocalAppTabConfigNotifier extends Notifier<LocalAppTabConfig> {
  @override
  LocalAppTabConfig build() {
    // Initial async load
    _loadConfig();
    return const LocalAppTabConfig();
  }

  Future<void> _loadConfig() async {
    final service = ref.read(androidAppServiceProvider);
    final config = await service.getAppConfig();
    state = config;
  }

  Future<void> updateConfig(LocalAppTabConfig newConfig) async {
    state = newConfig;
    final service = ref.read(androidAppServiceProvider);
    await service.saveAppConfig(newConfig);
  }

  Future<void> setDefaultApp(String? appId) async {
    final updated = state.copyWith(
      defaultAppId: appId,
      clearDefaultAppId: appId == null,
    );
    await updateConfig(updated);
  }

  Future<void> toggleHideApp(String appId) async {
    final hidden = List<String>.from(state.hiddenAppIds);
    if (hidden.contains(appId)) {
      hidden.remove(appId);
    } else {
      hidden.add(appId);
      // If we just hid the default app, clear default
      if (state.defaultAppId == appId) {
        final updated = state.copyWith(
          hiddenAppIds: hidden,
          clearDefaultAppId: true,
        );
        await updateConfig(updated);
        return;
      }
    }
    await updateConfig(state.copyWith(hiddenAppIds: hidden));
  }

  Future<void> setAppOrder(List<String> order) async {
    await updateConfig(state.copyWith(appOrder: order));
  }

  Future<void> toggleAutoInvoke(bool enabled) async {
    await updateConfig(state.copyWith(autoInvokeDefault: enabled));
  }

  Future<void> setTabTitle(String title) async {
    await updateConfig(state.copyWith(tabTitle: title));
  }
}

final localAppTabConfigProvider =
    NotifierProvider<LocalAppTabConfigNotifier, LocalAppTabConfig>(
      () => LocalAppTabConfigNotifier(),
    );
