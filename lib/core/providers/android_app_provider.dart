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

  Future<void> setDefaultApp(String? appId, {bool isSentence = false}) async {
    final updated = isSentence
        ? state.copyWith(
            defaultSentenceAppId: appId,
            clearDefaultSentenceAppId: appId == null,
          )
        : state.copyWith(
            defaultTermAppId: appId,
            clearDefaultTermAppId: appId == null,
          );
    await updateConfig(updated);
  }

  Future<void> setInstantApp(String? appId, {bool isSentence = false}) =>
      setDefaultApp(appId, isSentence: isSentence);

  Future<void> toggleHideApp(String appId, {bool isSentence = false}) async {
    final currentHidden =
        List<String>.from(state.getHiddenAppIds(isSentence: isSentence));
    if (currentHidden.contains(appId)) {
      currentHidden.remove(appId);
    } else {
      currentHidden.add(appId);
      final isDefault =
          state.getDefaultAppId(isSentence: isSentence) == appId;
      if (isDefault) {
        final updated = isSentence
            ? state.copyWith(
                sentenceHiddenAppIds: currentHidden,
                clearDefaultSentenceAppId: true,
              )
            : state.copyWith(
                termHiddenAppIds: currentHidden,
                clearDefaultTermAppId: true,
              );
        await updateConfig(updated);
        return;
      }
    }

    final updated = isSentence
        ? state.copyWith(sentenceHiddenAppIds: currentHidden)
        : state.copyWith(termHiddenAppIds: currentHidden);
    await updateConfig(updated);
  }

  Future<void> setAppOrder(List<String> order, {bool isSentence = false}) async {
    final updated = isSentence
        ? state.copyWith(sentenceAppOrder: order)
        : state.copyWith(termAppOrder: order);
    await updateConfig(updated);
  }

  Future<void> toggleAutoInvoke(bool enabled) async {
    await updateConfig(state.copyWith(autoInvokeDefault: enabled));
  }

  Future<void> setTabTitle(String title) async {
    await updateConfig(state.copyWith(tabTitle: title));
  }

  Future<void> addCustomWidget(CustomAppWidgetConfig customWidget) async {
    final widgets = List<CustomAppWidgetConfig>.from(state.customWidgets)
      ..add(customWidget);
    final termOrder = List<String>.from(state.termAppOrder);
    if (!termOrder.contains(customWidget.id)) {
      termOrder.add(customWidget.id);
    }
    final sentenceOrder = List<String>.from(state.sentenceAppOrder);
    if (!sentenceOrder.contains(customWidget.id)) {
      sentenceOrder.add(customWidget.id);
    }
    await updateConfig(state.copyWith(
      customWidgets: widgets,
      termAppOrder: termOrder,
      sentenceAppOrder: sentenceOrder,
    ));
  }

  Future<void> updateCustomWidget(CustomAppWidgetConfig customWidget) async {
    final widgets = state.customWidgets
        .map((w) => w.id == customWidget.id ? customWidget : w)
        .toList();
    await updateConfig(state.copyWith(customWidgets: widgets));
  }

  Future<void> deleteCustomWidget(String widgetId) async {
    final widgets =
        state.customWidgets.where((w) => w.id != widgetId).toList();
    final termOrder =
        state.termAppOrder.where((id) => id != widgetId).toList();
    final sentenceOrder =
        state.sentenceAppOrder.where((id) => id != widgetId).toList();
    final termHidden =
        state.termHiddenAppIds.where((id) => id != widgetId).toList();
    final sentenceHidden =
        state.sentenceHiddenAppIds.where((id) => id != widgetId).toList();

    final isTermDefault = state.getDefaultAppId(isSentence: false) == widgetId;
    final isSentenceDefault =
        state.getDefaultAppId(isSentence: true) == widgetId;

    await updateConfig(state.copyWith(
      customWidgets: widgets,
      termAppOrder: termOrder,
      sentenceAppOrder: sentenceOrder,
      termHiddenAppIds: termHidden,
      sentenceHiddenAppIds: sentenceHidden,
      clearDefaultTermAppId: isTermDefault,
      clearDefaultSentenceAppId: isSentenceDefault,
    ));
  }
}

final localAppTabConfigProvider =
    NotifierProvider<LocalAppTabConfigNotifier, LocalAppTabConfig>(
      () => LocalAppTabConfigNotifier(),
    );
