import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/android_app_info.dart';
import '../../../core/providers/android_app_provider.dart';
import '../../../shared/theme/theme_extensions.dart';

abstract class LauncherItem {
  String get id;
  String get label;
  String? get iconBase64;
  bool get isCustomWidget;
}

class AppLauncherItem implements LauncherItem {
  final AndroidAppInfo app;
  const AppLauncherItem(this.app);

  @override
  String get id => app.id;
  @override
  String get label => app.label;
  @override
  String? get iconBase64 => app.iconBase64;
  @override
  bool get isCustomWidget => false;
}

class CustomWidgetLauncherItem implements LauncherItem {
  final CustomAppWidgetConfig widgetConfig;
  const CustomWidgetLauncherItem(this.widgetConfig);

  @override
  String get id => widgetConfig.id;
  @override
  String get label => widgetConfig.name;
  @override
  String? get iconBase64 => widgetConfig.targetAppIconBase64;
  @override
  bool get isCustomWidget => true;
}

class AndroidAppLauncherView extends ConsumerStatefulWidget {
  final String text;
  final bool isSentence;
  final bool isActive;
  final bool isInline;
  final bool autoInvoke;
  final VoidCallback? onAutoInvoked;

  const AndroidAppLauncherView({
    super.key,
    required this.text,
    this.isSentence = false,
    this.isActive = true,
    this.isInline = false,
    this.autoInvoke = true,
    this.onAutoInvoked,
  });

  @override
  ConsumerState<AndroidAppLauncherView> createState() =>
      _AndroidAppLauncherViewState();
}

class _AndroidAppLauncherViewState
    extends ConsumerState<AndroidAppLauncherView> {
  bool _hasAutoInvokedForCurrentActivation = false;
  int _invokeCounter = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoInvoke();
      });
    }
  }

  @override
  void didUpdateWidget(AndroidAppLauncherView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _hasAutoInvokedForCurrentActivation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoInvoke();
      });
    } else if (widget.isActive && oldWidget.text != widget.text) {
      _hasAutoInvokedForCurrentActivation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoInvoke();
      });
    }
  }

  Future<void> _checkAndAutoInvoke() async {
    if (!mounted || !widget.isActive || !widget.autoInvoke) return;
    if (widget.text.trim().isEmpty) return;
    if (_hasAutoInvokedForCurrentActivation) return;

    final currentCount = ++_invokeCounter;

    final service = ref.read(androidAppServiceProvider);
    final config = await service.getAppConfig();
    if (!mounted || !widget.isActive || !widget.autoInvoke || currentCount != _invokeCounter) return;

    final defaultAppId = config.getDefaultAppId(isSentence: widget.isSentence);
    if (defaultAppId == null) {
      return;
    }

    final apps = await service.getInstalledApps();
    if (!mounted || !widget.isActive || !widget.autoInvoke || currentCount != _invokeCounter) return;

    final hiddenIds = config.getHiddenAppIds(isSentence: widget.isSentence);
    // Check if default is a custom widget
    final customWidget = config.customWidgets
        .where((w) => w.id == defaultAppId)
        .firstOrNull;
    if (customWidget != null) {
      if (hiddenIds.contains(customWidget.id)) return;
      if (_hasAutoInvokedForCurrentActivation) return;
      _hasAutoInvokedForCurrentActivation = true;
      widget.onAutoInvoked?.call();
      await _launchCustomWidget(customWidget, apps);
      return;
    }

    // Otherwise check regular app
    final defaultApp = apps.where((a) => a.id == defaultAppId).firstOrNull;
    if (defaultApp != null && !hiddenIds.contains(defaultApp.id)) {
      if (_hasAutoInvokedForCurrentActivation) return;
      _hasAutoInvokedForCurrentActivation = true;
      widget.onAutoInvoked?.call();
      await service.launchApp(defaultApp, widget.text);
    }
  }

  Future<void> _launchCustomWidget(
    CustomAppWidgetConfig customWidget,
    List<AndroidAppInfo> allApps,
  ) async {
    final service = ref.read(androidAppServiceProvider);
    final resolvedText = customWidget.resolveText(widget.text);
    final targetApp =
        allApps.where((a) => a.id == customWidget.targetAppId).firstOrNull;
    if (targetApp != null) {
      await service.launchApp(targetApp, resolvedText);
    } else {
      final parts = customWidget.targetAppId.split('/');
      final pkg = parts.first;
      final act = parts.length > 1 ? parts.sublist(1).join('/') : null;
      final fallbackApp = AndroidAppInfo(
        packageName: pkg,
        activityName: act ?? '',
        label: customWidget.targetAppLabel,
        actionType: customWidget.actionType,
      );
      await service.launchApp(fallbackApp, resolvedText);
    }
  }

  List<LauncherItem> _getSortedVisibleItems(
    List<AndroidAppInfo> allApps,
    LocalAppTabConfig config,
  ) {
    final appItems = allApps.map((a) => AppLauncherItem(a));
    final customItems =
        config.customWidgets.map((w) => CustomWidgetLauncherItem(w));
    final allItems = <LauncherItem>[...appItems, ...customItems];

    final hiddenIds = config.getHiddenAppIds(isSentence: widget.isSentence);
    final visible =
        allItems.where((i) => !hiddenIds.contains(i.id)).toList();

    final appOrder = config.getAppOrder(isSentence: widget.isSentence);
    if (appOrder.isNotEmpty) {
      final orderMap = <String, int>{};
      for (int i = 0; i < appOrder.length; i++) {
        orderMap[appOrder[i]] = i;
      }

      visible.sort((a, b) {
        final orderA = orderMap[a.id] ?? 9999;
        final orderB = orderMap[b.id] ?? 9999;
        if (orderA != orderB) {
          return orderA.compareTo(orderB);
        }
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    }

    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(installedAppsProvider);
    final config = ref.watch(localAppTabConfigProvider);

    ref.listen<LocalAppTabConfig>(localAppTabConfigProvider, (prev, next) {
      final prevDefault = prev?.getDefaultAppId(isSentence: widget.isSentence);
      final nextDefault = next.getDefaultAppId(isSentence: widget.isSentence);
      if (widget.isActive &&
          widget.autoInvoke &&
          nextDefault != null &&
          prevDefault != nextDefault) {
        _hasAutoInvokedForCurrentActivation = false;
        _checkAndAutoInvoke();
      }
    });

    final currentDefaultId =
        config.getDefaultAppId(isSentence: widget.isSentence);
    String? defaultItemLabel;
    if (currentDefaultId != null) {
      final customWidget = config.customWidgets
          .where((w) => w.id == currentDefaultId)
          .firstOrNull;
      if (customWidget != null) {
        defaultItemLabel = customWidget.name;
      } else {
        appsAsync.whenData((apps) {
          final app = apps.where((a) => a.id == currentDefaultId).firstOrNull;
          if (app != null) {
            defaultItemLabel = app.label;
          }
        });
      }
    }

    if (widget.isInline) {
      return _buildInlineView(context, appsAsync, config);
    }

    return Column(
      children: [
        if (defaultItemLabel != null) ...[
          _buildDefaultAppBanner(context, defaultItemLabel!),
          const Divider(height: 1, thickness: 1),
        ],
        Expanded(
          child: appsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => _buildErrorState(context, err.toString()),
            data: (allApps) {
              if (allApps.isEmpty && config.customWidgets.isEmpty) {
                return _buildEmptyState(context);
              }

              if (widget.isActive && !_hasAutoInvokedForCurrentActivation) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkAndAutoInvoke();
                });
              }

              final visibleItems = _getSortedVisibleItems(allApps, config);
              if (visibleItems.isEmpty) {
                return _buildAllHiddenState(context, allApps);
              }

              return _buildAppGrid(context, visibleItems, allApps, config);
            },
          ),
        ),
        _buildBottomTabBar(context, config, appsAsync),
      ],
    );
  }

  Widget _buildInlineView(
    BuildContext context,
    AsyncValue<List<AndroidAppInfo>> appsAsync,
    LocalAppTabConfig config,
  ) {
    final currentDefaultId =
        config.getDefaultAppId(isSentence: widget.isSentence);
    String? defaultItemLabel;
    if (currentDefaultId != null) {
      final customWidget = config.customWidgets
          .where((w) => w.id == currentDefaultId)
          .firstOrNull;
      if (customWidget != null) {
        defaultItemLabel = customWidget.name;
      } else {
        appsAsync.whenData((apps) {
          final app = apps.where((a) => a.id == currentDefaultId).firstOrNull;
          if (app != null) {
            defaultItemLabel = app.label;
          }
        });
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: context.appColorScheme.background.surfaceContainerHighest
            .withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.appColorScheme.border.dividerColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              if (defaultItemLabel != null) ...[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.m3Primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt,
                          size: 13,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            defaultItemLabel!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.m3Primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Tooltip(
                message: 'Add Custom Widget',
                child: InkWell(
                  onTap: () {
                    appsAsync.whenData((allApps) {
                      _showCustomWidgetDialog(context, allApps: allApps);
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.add_circle_outline, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Manage Apps & Widgets',
                child: InkWell(
                  onTap: () => _showManageAppsSheet(context),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.tune, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Refresh Apps',
                child: InkWell(
                  onTap: () => ref.invalidate(installedAppsProvider),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.refresh, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          appsAsync.when(
            loading: () => const SizedBox(
              height: 64,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, _) => SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  'Failed to load apps: $e',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.error),
                ),
              ),
            ),
            data: (allApps) {
              if (allApps.isEmpty && config.customWidgets.isEmpty) {
                return SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(
                      'No text processing apps found',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.appColorScheme.text.primary
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  ),
                );
              }

              if (widget.isActive && !_hasAutoInvokedForCurrentActivation) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkAndAutoInvoke();
                });
              }

              final visibleItems = _getSortedVisibleItems(allApps, config);
              if (visibleItems.isEmpty) {
                return SizedBox(
                  height: 40,
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () => _showManageAppsSheet(context),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('All apps & widgets hidden. Tap to manage'),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: visibleItems.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    final isDefault = item.id == currentDefaultId;

                    if (item.isCustomWidget) {
                      return _buildInlineCustomWidgetItem(
                        context,
                        (item as CustomWidgetLauncherItem).widgetConfig,
                        isDefault,
                        config,
                        allApps,
                      );
                    }
                    return _buildInlineAppItem(
                      context,
                      (item as AppLauncherItem).app,
                      isDefault,
                      config,
                      allApps,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInlineAppItem(
    BuildContext context,
    AndroidAppInfo app,
    bool isDefault,
    LocalAppTabConfig config,
    List<AndroidAppInfo> allApps,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(androidAppServiceProvider).launchApp(app, widget.text);
        },
        onLongPress: () => _showAppOptionsSheet(context, app, config, allApps),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDefault
                  ? context.m3Primary
                  : context.appColorScheme.border.dividerColor
                      .withValues(alpha: 0.3),
              width: isDefault ? 1.5 : 1,
            ),
            color: isDefault
                ? context.m3Primary.withValues(alpha: 0.1)
                : context.appColorScheme.background.surface
                    .withValues(alpha: 0.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildInlineAppIcon(app.iconBase64),
                  if (isDefault)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bolt,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                app.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight:
                          isDefault ? FontWeight.bold : FontWeight.w500,
                      color: isDefault
                          ? context.m3Primary
                          : context.appColorScheme.text.primary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineCustomWidgetItem(
    BuildContext context,
    CustomAppWidgetConfig customWidget,
    bool isDefault,
    LocalAppTabConfig config,
    List<AndroidAppInfo> allApps,
  ) {
    // Each custom widget spans 2 apps wide (60*2 + 8 spacing = 128)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchCustomWidget(customWidget, allApps),
        onLongPress: () =>
            _showCustomWidgetOptionsSheet(context, customWidget, config, allApps),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 128,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDefault
                  ? [
                      context.m3Primary.withValues(alpha: 0.18),
                      context.m3Primary.withValues(alpha: 0.08),
                    ]
                  : [
                      context.appColorScheme.background.surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      context.appColorScheme.background.surface
                          .withValues(alpha: 0.4),
                    ],
            ),
            border: Border.all(
              color: isDefault
                  ? context.m3Primary
                  : context.m3Primary.withValues(alpha: 0.35),
              width: isDefault ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  _buildSmallAppIcon(customWidget.targetAppIconBase64, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      customWidget.targetAppLabel,
                      style: TextStyle(
                        fontSize: 9,
                        color: context.m3Primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDefault)
                    Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bolt,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                customWidget.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.appColorScheme.text.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                customWidget.template,
                style: TextStyle(
                  fontSize: 8.5,
                  color: context.appColorScheme.text.primary.withValues(alpha: 0.55),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineAppIcon(String? iconBase64) {
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        final bytes = getOrDecodeAppIconBytes(iconBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) =>
                _buildInlineFallbackIcon(),
          ),
        );
      } catch (_) {
        return _buildInlineFallbackIcon();
      }
    }
    return _buildInlineFallbackIcon();
  }

  Widget _buildSmallAppIcon(String? iconBase64, {double size = 20}) {
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        final bytes = getOrDecodeAppIconBytes(iconBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.widgets, size: size, color: context.m3Primary),
          ),
        );
      } catch (_) {
        return Icon(Icons.widgets, size: size, color: context.m3Primary);
      }
    }
    return Icon(Icons.widgets, size: size, color: context.m3Primary);
  }

  Widget _buildInlineFallbackIcon() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: context.m3Primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.open_in_new, size: 18, color: context.m3Primary),
    );
  }

  Widget _buildDefaultAppBanner(BuildContext context, String defaultItemLabel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: context.appColorScheme.background.surfaceContainerHighest.withValues(
        alpha: 0.3,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: context.m3Primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt,
                  size: 13,
                  color: Colors.amber,
                ),
                const SizedBox(width: 4),
                Text(
                  'Instant: $defaultItemLabel',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.m3Primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTabBar(
    BuildContext context,
    LocalAppTabConfig config,
    AsyncValue<List<AndroidAppInfo>> appsAsync,
  ) {
    final dividerColor = context.appColorScheme.border.dividerColor;
    final textColor =
        context.appColorScheme.text.primary.withValues(alpha: 0.85);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: context.appColorScheme.background.surfaceContainerHighest
            .withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(
            color: dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Segment 1: Add Custom Widget
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  appsAsync.whenData((allApps) {
                    _showCustomWidgetDialog(context, allApps: allApps);
                  });
                },
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline, size: 16, color: context.m3Primary),
                      const SizedBox(width: 5),
                      Text(
                        'Add Widget',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              fontSize: 11.5,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 18,
            width: 1,
            color: dividerColor.withValues(alpha: 0.6),
          ),
          // Segment 2: Manage / Sort Apps & Widgets
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showManageAppsSheet(context),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune, size: 16, color: context.m3Primary),
                      const SizedBox(width: 5),
                      Text(
                        'Manage & Sort',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              fontSize: 11.5,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 18,
            width: 1,
            color: dividerColor.withValues(alpha: 0.6),
          ),
          // Segment 3: Refresh App List
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.invalidate(installedAppsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshed app list'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 16, color: context.m3Primary),
                      const SizedBox(width: 5),
                      Text(
                        'Refresh',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              fontSize: 11.5,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppGrid(
    BuildContext context,
    List<LauncherItem> visibleItems,
    List<AndroidAppInfo> allApps,
    LocalAppTabConfig config,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double padding = 8.0;
        final double spacing = 6.0;
        final double availableWidth = constraints.maxWidth - (padding * 2);

        // 4 columns layout
        final int columns = 4;
        final double unitWidth =
            ((availableWidth - ((columns - 1) * spacing)) / columns)
                .floorToDouble();
        final double doubleWidth = (unitWidth * 2) + spacing;
        final double itemHeight = (unitWidth / 0.85).roundToDouble();

        final currentDefaultId =
            config.getDefaultAppId(isSentence: widget.isSentence);

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: visibleItems.map((item) {
              final isDefault = item.id == currentDefaultId;
              final width = item.isCustomWidget ? doubleWidth : unitWidth;

              return SizedBox(
                width: width,
                height: itemHeight,
                child: item.isCustomWidget
                    ? _buildCustomWidgetItem(
                        context,
                        (item as CustomWidgetLauncherItem).widgetConfig,
                        isDefault,
                        config,
                        allApps,
                      )
                    : _buildAppItem(
                        context,
                        (item as AppLauncherItem).app,
                        isDefault,
                        config,
                        allApps,
                      ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildAppItem(
    BuildContext context,
    AndroidAppInfo app,
    bool isDefault,
    LocalAppTabConfig config,
    List<AndroidAppInfo> allApps,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(androidAppServiceProvider).launchApp(app, widget.text);
        },
        onLongPress: () => _showAppOptionsSheet(context, app, config, allApps),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDefault
                  ? context.m3Primary
                  : context.appColorScheme.border.dividerColor.withValues(
                      alpha: 0.35,
                    ),
              width: isDefault ? 1.5 : 1,
            ),
            color: isDefault
                ? context.m3Primary.withValues(alpha: 0.08)
                : context.appColorScheme.background.surfaceContainerHighest
                    .withValues(alpha: 0.25),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildAppIcon(app.iconBase64),
                  if (isDefault)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bolt,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                app.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight:
                          isDefault ? FontWeight.bold : FontWeight.w500,
                      color: isDefault
                          ? context.m3Primary
                          : context.appColorScheme.text.primary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomWidgetItem(
    BuildContext context,
    CustomAppWidgetConfig customWidget,
    bool isDefault,
    LocalAppTabConfig config,
    List<AndroidAppInfo> allApps,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchCustomWidget(customWidget, allApps),
        onLongPress: () =>
            _showCustomWidgetOptionsSheet(context, customWidget, config, allApps),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDefault
                  ? [
                      context.m3Primary.withValues(alpha: 0.18),
                      context.m3Primary.withValues(alpha: 0.08),
                    ]
                  : [
                      context.appColorScheme.background.surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      context.appColorScheme.background.surface
                          .withValues(alpha: 0.45),
                    ],
            ),
            border: Border.all(
              color: isDefault
                  ? context.m3Primary
                  : context.m3Primary.withValues(alpha: 0.35),
              width: isDefault ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildSmallAppIcon(customWidget.targetAppIconBase64, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      customWidget.targetAppLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.m3Primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDefault)
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bolt,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  customWidget.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: context.appColorScheme.text.primary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '模板: ${customWidget.template}',
                style: TextStyle(
                  fontSize: 9.5,
                  color: context.appColorScheme.text.primary
                      .withValues(alpha: 0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(String? iconBase64) {
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        final Uint8List bytes = getOrDecodeAppIconBytes(iconBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.memory(
            bytes,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) =>
                _buildFallbackIcon(),
          ),
        );
      } catch (_) {
        return _buildFallbackIcon();
      }
    }
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: context.m3Primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(Icons.open_in_new, size: 18, color: context.m3Primary),
    );
  }

  void _showAppOptionsSheet(
    BuildContext context,
    AndroidAppInfo app,
    LocalAppTabConfig config,
    List<AndroidAppInfo> allApps,
  ) {
    final isTermDefault =
        app.id == config.getDefaultAppId(isSentence: false);
    final isSentenceDefault =
        app.id == config.getDefaultAppId(isSentence: true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final termTile = ListTile(
          leading: Icon(
            isTermDefault ? Icons.bolt : Icons.bolt_outlined,
            color: isTermDefault ? Colors.amber : null,
          ),
          title: Text(
            isTermDefault
                ? 'Remove Instant App for Terms'
                : 'Set as Instant App for Terms',
          ),
          subtitle: Text(
            isTermDefault
                ? 'Currently auto-launched when looking up terms'
                : 'Auto-launch this app when looking up terms',
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            ref
                .read(localAppTabConfigProvider.notifier)
                .setDefaultApp(isTermDefault ? null : app.id, isSentence: false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isTermDefault
                      ? 'Removed instant app for terms'
                      : 'Set ${app.label} as instant app for terms',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );

        final sentenceTile = ListTile(
          leading: Icon(
            isSentenceDefault ? Icons.bolt : Icons.bolt_outlined,
            color: isSentenceDefault ? Colors.amber : null,
          ),
          title: Text(
            isSentenceDefault
                ? 'Remove Instant App for Sentences'
                : 'Set as Instant App for Sentences',
          ),
          subtitle: Text(
            isSentenceDefault
                ? 'Currently auto-launched when looking up sentences'
                : 'Auto-launch this app when looking up sentences',
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            ref
                .read(localAppTabConfigProvider.notifier)
                .setDefaultApp(isSentenceDefault ? null : app.id, isSentence: true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isSentenceDefault
                      ? 'Removed instant app for sentences'
                      : 'Set ${app.label} as instant app for sentences',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: _buildAppIcon(app.iconBase64),
                  title: Text(
                    app.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(app.packageName),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('Launch App'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref
                        .read(androidAppServiceProvider)
                        .launchApp(app, widget.text);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Create Custom Widget with this App'),
                  subtitle: const Text('Add a quick launcher widget with custom text template'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showCustomWidgetDialog(
                      context,
                      allApps: allApps,
                      initialTargetApp: app,
                    );
                  },
                ),
                if (!widget.isSentence) ...[
                  termTile,
                  sentenceTile,
                ] else ...[
                  sentenceTile,
                  termTile,
                ],
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Hide this App'),
                  subtitle: const Text('Hide from launcher (can be unhidden in Manage Apps)'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref
                        .read(localAppTabConfigProvider.notifier)
                        .toggleHideApp(app.id, isSentence: widget.isSentence);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hidden ${app.label}'),
                        duration: const Duration(seconds: 1),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            ref
                                .read(localAppTabConfigProvider.notifier)
                                .toggleHideApp(app.id, isSentence: widget.isSentence);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomWidgetOptionsSheet(
    BuildContext context,
    CustomAppWidgetConfig customWidget,
    LocalAppTabConfig config,
    List<AndroidAppInfo> allApps,
  ) {
    final isTermDefault =
        customWidget.id == config.getDefaultAppId(isSentence: false);
    final isSentenceDefault =
        customWidget.id == config.getDefaultAppId(isSentence: true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final termTile = ListTile(
          leading: Icon(
            isTermDefault ? Icons.bolt : Icons.bolt_outlined,
            color: isTermDefault ? Colors.amber : null,
          ),
          title: Text(
            isTermDefault
                ? 'Remove Instant Widget for Terms'
                : 'Set as Instant Widget for Terms',
          ),
          subtitle: Text(
            isTermDefault
                ? 'Currently auto-launched with template for terms'
                : 'Auto-launch this widget when looking up terms',
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            ref
                .read(localAppTabConfigProvider.notifier)
                .setDefaultApp(
                  isTermDefault ? null : customWidget.id,
                  isSentence: false,
                );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isTermDefault
                      ? 'Removed instant widget for terms'
                      : 'Set ${customWidget.name} as instant widget for terms',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );

        final sentenceTile = ListTile(
          leading: Icon(
            isSentenceDefault ? Icons.bolt : Icons.bolt_outlined,
            color: isSentenceDefault ? Colors.amber : null,
          ),
          title: Text(
            isSentenceDefault
                ? 'Remove Instant Widget for Sentences'
                : 'Set as Instant Widget for Sentences',
          ),
          subtitle: Text(
            isSentenceDefault
                ? 'Currently auto-launched with template for sentences'
                : 'Auto-launch this widget when looking up sentences',
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            ref
                .read(localAppTabConfigProvider.notifier)
                .setDefaultApp(
                  isSentenceDefault ? null : customWidget.id,
                  isSentence: true,
                );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isSentenceDefault
                      ? 'Removed instant widget for sentences'
                      : 'Set ${customWidget.name} as instant widget for sentences',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: _buildSmallAppIcon(customWidget.targetAppIconBase64, size: 28),
                  title: Text(
                    customWidget.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Target: ${customWidget.targetAppLabel} | Template: ${customWidget.template}',
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('Execute Custom Widget'),
                  subtitle: Text('Sends: "${customWidget.resolveText(widget.text)}"'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _launchCustomWidget(customWidget, allApps);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Custom Widget'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showCustomWidgetDialog(
                      context,
                      allApps: allApps,
                      existingWidget: customWidget,
                    );
                  },
                ),
                if (!widget.isSentence) ...[
                  termTile,
                  sentenceTile,
                ] else ...[
                  sentenceTile,
                  termTile,
                ],
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Hide this Widget'),
                  subtitle: const Text('Hide from launcher (can be unhidden in Manage Apps)'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref
                        .read(localAppTabConfigProvider.notifier)
                        .toggleHideApp(customWidget.id, isSentence: widget.isSentence);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hidden ${customWidget.name}'),
                        duration: const Duration(seconds: 1),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            ref
                                .read(localAppTabConfigProvider.notifier)
                                .toggleHideApp(customWidget.id, isSentence: widget.isSentence);
                          },
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text(
                    'Delete Custom Widget',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDeleteCustomWidget(context, customWidget);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteCustomWidget(
    BuildContext context,
    CustomAppWidgetConfig customWidget,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Custom Widget'),
          content: Text('Are you sure you want to delete "${customWidget.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(dialogContext);
                ref
                    .read(localAppTabConfigProvider.notifier)
                    .deleteCustomWidget(customWidget.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${customWidget.name}"'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showCustomWidgetDialog(
    BuildContext context, {
    required List<AndroidAppInfo> allApps,
    CustomAppWidgetConfig? existingWidget,
    AndroidAppInfo? initialTargetApp,
  }) {
    if (allApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No installed text apps available to target.'),
        ),
      );
      return;
    }

    final isEditing = existingWidget != null;
    final nameController = TextEditingController(
      text: existingWidget?.name ??
          (initialTargetApp != null ? '翻译到 ${initialTargetApp.label}' : ''),
    );
    final templateController = TextEditingController(
      text: existingWidget?.template ?? '翻译 [Text]',
    );

    AndroidAppInfo selectedApp = initialTargetApp ??
        (existingWidget != null
            ? allApps
                    .where((a) => a.id == existingWidget.targetAppId)
                    .firstOrNull ??
                allApps.first
            : allApps.first);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasPlaceholder = templateController.text.contains('[Text]') ||
                templateController.text.contains('[LUTE]');
            final previewText = hasPlaceholder
                ? templateController.text
                    .replaceAll(
                      '[Text]',
                      widget.text.isNotEmpty ? widget.text : '示例内容',
                    )
                    .replaceAll(
                      '[LUTE]',
                      widget.text.isNotEmpty ? widget.text : '示例内容',
                    )
                : (templateController.text.trim().isEmpty
                    ? (widget.text.isNotEmpty ? widget.text : '示例内容')
                    : '${templateController.text} ${widget.text.isNotEmpty ? widget.text : "示例内容"}');

            return AlertDialog(
              title: Text(isEditing ? 'Edit Custom Widget' : 'Add Custom Widget'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Widget Name (组件名称) *',
                          hintText: 'e.g. 翻译为中文, 语法解析',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: templateController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Template (模板内容) *',
                          hintText: 'e.g. 翻译 [Text]',
                          helperText: '[Text] is the placeholder for selected text',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'Insert [Text]',
                            onPressed: () {
                              final text = templateController.text;
                              final selection = templateController.selection;
                              if (selection.isValid &&
                                  selection.start >= 0 &&
                                  selection.end >= 0) {
                                final newText = text.replaceRange(
                                  selection.start,
                                  selection.end,
                                  '[Text]',
                                );
                                templateController.value = TextEditingValue(
                                  text: newText,
                                  selection: TextSelection.collapsed(
                                    offset: selection.start + 6,
                                  ),
                                );
                              } else {
                                templateController.text = '$text [Text]'.trim();
                              }
                              setDialogState(() {});
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Preset template chips
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildPresetChip(
                            label: '翻译 [Text]',
                            onTap: () {
                              templateController.text = '翻译 [Text]';
                              setDialogState(() {});
                            },
                          ),
                          _buildPresetChip(
                            label: 'Define: [Text]',
                            onTap: () {
                              templateController.text = 'Define: [Text]';
                              setDialogState(() {});
                            },
                          ),
                          _buildPresetChip(
                            label: '解释词汇：[Text]',
                            onTap: () {
                              templateController.text = '解释词汇：[Text]';
                              setDialogState(() {});
                            },
                          ),
                          _buildPresetChip(
                            label: '[Text]',
                            onTap: () {
                              templateController.text = '[Text]';
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Live Preview box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.m3Primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.m3Primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.preview, size: 14, color: context.m3Primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Live Output Preview:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: context.m3Primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              previewText,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Target App (传入应用) *',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<AndroidAppInfo>(
                        initialValue: selectedApp,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        items: allApps.map((app) {
                          return DropdownMenuItem<AndroidAppInfo>(
                            value: app,
                            child: Row(
                              children: [
                                _buildSmallAppIcon(app.iconBase64, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    app.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedApp = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final template = templateController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Widget Name cannot be empty'),
                        ),
                      );
                      return;
                    }

                    final widgetId = existingWidget?.id ??
                        'custom_${DateTime.now().millisecondsSinceEpoch}';
                    final newWidget = CustomAppWidgetConfig(
                      id: widgetId,
                      name: name,
                      template: template.isNotEmpty ? template : '[Text]',
                      targetAppId: selectedApp.id,
                      targetAppLabel: selectedApp.label,
                      targetAppIconBase64: selectedApp.iconBase64,
                      actionType: selectedApp.actionType,
                    );

                    final notifier =
                        ref.read(localAppTabConfigProvider.notifier);
                    if (isEditing) {
                      notifier.updateCustomWidget(newWidget);
                    } else {
                      notifier.addCustomWidget(newWidget);
                    }

                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing
                              ? 'Updated widget "$name"'
                              : 'Created custom widget "$name"',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPresetChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }

  void _showManageAppsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        bool targetIsSentence = widget.isSentence;

        return StatefulBuilder(
          builder: (sheetInnerContext, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Consumer(
                  builder: (context, ref, _) {
                    final appsAsync = ref.watch(installedAppsProvider);
                    final config = ref.watch(localAppTabConfigProvider);

                    return appsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (allApps) {
                        final appMap = {for (var a in allApps) a.id: a};
                        final customWidgetMap = {
                          for (var w in config.customWidgets) w.id: w
                        };

                        final allAvailableIds = [
                          ...allApps.map((a) => a.id),
                          ...config.customWidgets.map((w) => w.id),
                        ];

                        final targetOrder =
                            config.getAppOrder(isSentence: targetIsSentence);
                        final targetHidden =
                            config.getHiddenAppIds(isSentence: targetIsSentence);

                        final orderedIds = List<String>.from(
                          targetOrder
                              .where((id) => allAvailableIds.contains(id)),
                        );
                        for (final id in allAvailableIds) {
                          if (!orderedIds.contains(id)) {
                            orderedIds.add(id);
                          }
                        }

                        final visibleIds = orderedIds
                            .where((id) => !targetHidden.contains(id))
                            .toList();
                        final hiddenIds = orderedIds
                            .where((id) => targetHidden.contains(id))
                            .toList();

                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.tune, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Manage Apps & Widgets',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Add Custom Widget',
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 22,
                                      ),
                                      constraints:
                                          const BoxConstraints.tightFor(
                                        width: 36,
                                        height: 36,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        _showCustomWidgetDialog(
                                          context,
                                          allApps: allApps,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: 'Done',
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        size: 22,
                                      ),
                                      constraints:
                                          const BoxConstraints.tightFor(
                                        width: 36,
                                        height: 36,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () =>
                                          Navigator.pop(sheetContext),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Terms (词汇)'),
                                    icon: Icon(Icons.translate, size: 16),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Sentences (句子)'),
                                    icon: Icon(Icons.notes, size: 16),
                                  ),
                                ],
                                selected: {targetIsSentence},
                                onSelectionChanged: (Set<bool> newSelection) {
                                  setSheetState(() {
                                    targetIsSentence = newSelection.first;
                                  });
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Text(
                                targetIsSentence
                                    ? 'Drag to reorder. Tap ⚡ to set instant app/widget for sentences.'
                                    : 'Drag to reorder. Tap ⚡ to set instant app/widget for terms.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.7),
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                children: [
                                  if (visibleIds.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        'Visible Apps & Widgets (${visibleIds.length})',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: context.m3Primary,
                                            ),
                                      ),
                                    ),
                                    ReorderableListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: visibleIds.length,
                                      onReorder: (oldIndex, newIndex) {
                                        if (oldIndex < newIndex) {
                                          newIndex -= 1;
                                        }
                                        final item =
                                            visibleIds.removeAt(oldIndex);
                                        visibleIds.insert(newIndex, item);

                                        final fullNewOrder = [
                                          ...visibleIds,
                                          ...hiddenIds,
                                        ];
                                        ref
                                            .read(
                                              localAppTabConfigProvider
                                                  .notifier,
                                            )
                                            .setAppOrder(
                                              fullNewOrder,
                                              isSentence: targetIsSentence,
                                            );
                                      },
                                      itemBuilder: (context, index) {
                                        final itemId = visibleIds[index];
                                        final isCustom =
                                            customWidgetMap.containsKey(itemId);
                                        final customWidget =
                                            customWidgetMap[itemId];
                                        final app = appMap[itemId];

                                        final label = isCustom
                                            ? customWidget!.name
                                            : app?.label ?? itemId;
                                        final iconBase64 = isCustom
                                            ? customWidget!.targetAppIconBase64
                                            : app?.iconBase64;

                                        final isTermDef = itemId ==
                                            config.getDefaultAppId(
                                              isSentence: false,
                                            );
                                        final isSentenceDef = itemId ==
                                            config.getDefaultAppId(
                                              isSentence: true,
                                            );
                                        final isCurrentTargetDef =
                                            targetIsSentence
                                                ? isSentenceDef
                                                : isTermDef;

                                        String? defaultBadge;
                                        if (isTermDef && isSentenceDef) {
                                          defaultBadge =
                                              '⚡ Instant for Terms & Sentences';
                                        } else if (isTermDef) {
                                          defaultBadge =
                                              '⚡ Instant for Terms';
                                        } else if (isSentenceDef) {
                                          defaultBadge =
                                              '⚡ Instant for Sentences';
                                        }

                                        return ListTile(
                                          key: ValueKey(itemId),
                                          leading: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ReorderableDragStartListener(
                                                index: index,
                                                child: const Icon(
                                                  Icons.drag_handle,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _buildSmallAppIcon(iconBase64, size: 28),
                                            ],
                                          ),
                                          title: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  label,
                                                  style: TextStyle(
                                                    fontWeight: isCurrentTargetDef
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                              if (isCustom) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1.5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: context.m3Primary
                                                        .withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Widget',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: context.m3Primary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          subtitle: defaultBadge != null
                                              ? Text(
                                                  defaultBadge,
                                                  style: TextStyle(
                                                    color: context.m3Primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                )
                                              : (isCustom
                                                  ? Text(
                                                      'Template: ${customWidget!.template} -> ${customWidget.targetAppLabel}',
                                                      style: const TextStyle(
                                                          fontSize: 11),
                                                    )
                                                  : null),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isCustom)
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                  ),
                                                  tooltip: 'Edit widget',
                                                  onPressed: () {
                                                    _showCustomWidgetDialog(
                                                      context,
                                                      allApps: allApps,
                                                      existingWidget:
                                                          customWidget,
                                                    );
                                                  },
                                                ),
                                              IconButton(
                                                icon: Icon(
                                                  isCurrentTargetDef
                                                      ? Icons.bolt
                                                      : Icons.bolt_outlined,
                                                  color: isCurrentTargetDef
                                                      ? Colors.amber
                                                      : null,
                                                ),
                                                tooltip: isCurrentTargetDef
                                                    ? (targetIsSentence
                                                        ? 'Remove instant app for sentences'
                                                        : 'Remove instant app for terms')
                                                    : (targetIsSentence
                                                        ? 'Set as instant app for sentences'
                                                        : 'Set as instant app for terms'),
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        localAppTabConfigProvider
                                                            .notifier,
                                                      )
                                                      .setDefaultApp(
                                                        isCurrentTargetDef
                                                            ? null
                                                            : itemId,
                                                        isSentence:
                                                            targetIsSentence,
                                                      );
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.visibility_outlined,
                                                ),
                                                tooltip: 'Hide',
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        localAppTabConfigProvider
                                                            .notifier,
                                                      )
                                                      .toggleHideApp(
                                                        itemId,
                                                        isSentence:
                                                            targetIsSentence,
                                                      );
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  if (hiddenIds.isNotEmpty) ...[
                                    const Divider(height: 24),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        'Hidden (${hiddenIds.length})',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                      ),
                                    ),
                                    ...hiddenIds.map((itemId) {
                                      final isCustom =
                                          customWidgetMap.containsKey(itemId);
                                      final customWidget =
                                          customWidgetMap[itemId];
                                      final app = appMap[itemId];
                                      final label = isCustom
                                          ? customWidget!.name
                                          : app?.label ?? itemId;
                                      final iconBase64 = isCustom
                                          ? customWidget!.targetAppIconBase64
                                          : app?.iconBase64;

                                      return ListTile(
                                        leading: Opacity(
                                          opacity: 0.5,
                                          child: _buildSmallAppIcon(
                                              iconBase64,
                                              size: 28),
                                        ),
                                        title: Text(
                                          label,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),
                                        trailing: TextButton.icon(
                                          icon: const Icon(
                                            Icons.visibility,
                                            size: 16,
                                          ),
                                          label: const Text('Unhide'),
                                          onPressed: () {
                                            ref
                                                .read(
                                                  localAppTabConfigProvider
                                                      .notifier,
                                                )
                                                .toggleHideApp(
                                                  itemId,
                                                  isSentence: targetIsSentence,
                                                );
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.apps_outlined,
              size: 48,
              color: context.appColorScheme.text.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No Text Processing Apps Found',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Install dictionary or translation apps like Google Translate, Pleco, GoldenDict, or Eudic on your Android device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColorScheme.text.primary.withValues(
                      alpha: 0.6,
                    ),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: () => ref.invalidate(installedAppsProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllHiddenState(
    BuildContext context,
    List<AndroidAppInfo> allApps,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 48,
              color: context.appColorScheme.text.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'All Apps & Widgets are Hidden',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Manage Apps & Widgets'),
              onPressed: () => _showManageAppsSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 44, color: context.error),
            const SizedBox(height: 8),
            Text('Failed to load apps: $error'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () => ref.invalidate(installedAppsProvider),
            ),
          ],
        ),
      ),
    );
  }
}
