import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/android_app_info.dart';
import '../../../core/providers/android_app_provider.dart';
import '../../../shared/theme/theme_extensions.dart';

class AndroidAppLauncherView extends ConsumerStatefulWidget {
  final String text;
  final bool isSentence;
  final bool isActive;
  final VoidCallback? onOpenTabReorder;

  const AndroidAppLauncherView({
    super.key,
    required this.text,
    this.isSentence = false,
    this.isActive = true,
    this.onOpenTabReorder,
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
      // Switched TO this tab!
      _hasAutoInvokedForCurrentActivation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoInvoke();
      });
    } else if (widget.isActive && oldWidget.text != widget.text) {
      // Current tab, but search text changed!
      _hasAutoInvokedForCurrentActivation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoInvoke();
      });
    }
  }

  Future<void> _checkAndAutoInvoke() async {
    if (!mounted || !widget.isActive) return;
    if (widget.text.trim().isEmpty) return;
    if (_hasAutoInvokedForCurrentActivation) return;

    final currentCount = ++_invokeCounter;

    final service = ref.read(androidAppServiceProvider);
    final config = await service.getAppConfig();
    if (!mounted || !widget.isActive || currentCount != _invokeCounter) return;

    final defaultAppId = config.getDefaultAppId(isSentence: widget.isSentence);
    if (!config.autoInvokeDefault || defaultAppId == null) {
      return;
    }

    final apps = await service.getInstalledApps();
    if (!mounted || !widget.isActive || currentCount != _invokeCounter) return;

    final defaultApp =
        apps.where((a) => a.id == defaultAppId).firstOrNull;
    if (defaultApp != null && !config.hiddenAppIds.contains(defaultApp.id)) {
      if (_hasAutoInvokedForCurrentActivation) return;
      _hasAutoInvokedForCurrentActivation = true;
      await service.launchApp(defaultApp, widget.text);
    }
  }

  List<AndroidAppInfo> _getSortedVisibleApps(
    List<AndroidAppInfo> allApps,
    LocalAppTabConfig config,
  ) {
    final visible =
        allApps.where((a) => !config.hiddenAppIds.contains(a.id)).toList();

    if (config.appOrder.isNotEmpty) {
      final orderMap = <String, int>{};
      for (int i = 0; i < config.appOrder.length; i++) {
        orderMap[config.appOrder[i]] = i;
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
          next.autoInvokeDefault &&
          nextDefault != null &&
          (prevDefault != nextDefault ||
              prev?.autoInvokeDefault != next.autoInvokeDefault)) {
        _hasAutoInvokedForCurrentActivation = false;
        _checkAndAutoInvoke();
      }
    });

    return Column(
      children: [
        _buildToolbar(context, config),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: appsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => _buildErrorState(context, err.toString()),
            data: (allApps) {
              if (allApps.isEmpty) {
                return _buildEmptyState(context);
              }

              // Also trigger if apps just finished loading while tab is active
              if (widget.isActive && !_hasAutoInvokedForCurrentActivation) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkAndAutoInvoke();
                });
              }

              final visibleApps = _getSortedVisibleApps(allApps, config);
              if (visibleApps.isEmpty) {
                return _buildAllHiddenState(context, allApps);
              }

              return _buildAppGrid(context, visibleApps, config);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, LocalAppTabConfig config) {
    final appsAsync = ref.watch(installedAppsProvider);
    final currentDefaultId =
        config.getDefaultAppId(isSentence: widget.isSentence);
    String? defaultAppLabel;
    if (currentDefaultId != null) {
      appsAsync.whenData((apps) {
        final app = apps.where((a) => a.id == currentDefaultId).firstOrNull;
        if (app != null) {
          defaultAppLabel = app.label;
        }
      });
    }

    final defaultText = defaultAppLabel != null
        ? (widget.isSentence
            ? 'Default (Sentence): $defaultAppLabel'
            : 'Default (Term): $defaultAppLabel')
        : 'Tap app to launch';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: context.appColorScheme.background.surfaceContainerHighest.withValues(
        alpha: 0.4,
      ),
      child: Row(
        children: [
          Icon(
            Icons.phone_android,
            size: 18,
            color: context.m3Primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              defaultText,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.appColorScheme.text.primary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: config.autoInvokeDefault
                ? 'Auto-launch on tab switch: ON'
                : 'Auto-launch on tab switch: OFF',
            child: IconButton(
              icon: Icon(
                config.autoInvokeDefault
                    ? Icons.bolt
                    : Icons.bolt_outlined,
                size: 20,
                color: config.autoInvokeDefault
                    ? context.m3Primary
                    : context.appColorScheme.text.primary.withValues(alpha: 0.4),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: () {
                ref
                    .read(localAppTabConfigProvider.notifier)
                    .toggleAutoInvoke(!config.autoInvokeDefault);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      !config.autoInvokeDefault
                          ? 'Auto-launch enabled when switching to this tab'
                          : 'Auto-launch disabled',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          Tooltip(
            message: 'Manage & Reorder Apps',
            child: IconButton(
              icon: const Icon(Icons.tune, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: () => _showManageAppsSheet(context),
            ),
          ),
          if (widget.onOpenTabReorder != null)
            Tooltip(
              message: 'Reorder Tabs',
              child: IconButton(
                icon: const Icon(Icons.sort, size: 20),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: widget.onOpenTabReorder,
              ),
            ),
          Tooltip(
            message: 'Refresh App List',
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: () {
                ref.invalidate(installedAppsProvider);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppGrid(
    BuildContext context,
    List<AndroidAppInfo> visibleApps,
    LocalAppTabConfig config,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 96).clamp(3, 8).toInt();
        final currentDefaultId =
            config.getDefaultAppId(isSentence: widget.isSentence);

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: visibleApps.length,
          itemBuilder: (context, index) {
            final app = visibleApps[index];
            final isDefault = app.id == currentDefaultId;

            return _buildAppItem(context, app, isDefault, config);
          },
        );
      },
    );
  }

  Widget _buildAppItem(
    BuildContext context,
    AndroidAppInfo app,
    bool isDefault,
    LocalAppTabConfig config,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(androidAppServiceProvider).launchApp(app, widget.text);
        },
        onLongPress: () => _showAppOptionsSheet(context, app, config),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDefault
                  ? context.m3Primary
                  : context.appColorScheme.border.dividerColor.withValues(
                      alpha: 0.4,
                    ),
              width: isDefault ? 2 : 1,
            ),
            color: isDefault
                ? context.m3Primary.withValues(alpha: 0.08)
                : context.appColorScheme.background.surfaceContainerHighest
                    .withValues(alpha: 0.25),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildAppIcon(app.iconBase64),
                  if (isDefault)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: context.m3Primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                app.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

  Widget _buildAppIcon(String? iconBase64) {
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(iconBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
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
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: context.m3Primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.open_in_new, size: 22, color: context.m3Primary),
    );
  }

  void _showAppOptionsSheet(
    BuildContext context,
    AndroidAppInfo app,
    LocalAppTabConfig config,
  ) {
    final isTermDefault =
        app.id == config.getDefaultAppId(isSentence: false);
    final isSentenceDefault =
        app.id == config.getDefaultAppId(isSentence: true);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final termTile = ListTile(
          leading: Icon(
            isTermDefault ? Icons.star : Icons.star_border,
            color: isTermDefault ? Colors.amber : null,
          ),
          title: Text(
            isTermDefault
                ? 'Clear Default for Terms'
                : 'Set as Default for Terms',
          ),
          subtitle: Text(
            isTermDefault
                ? 'Currently auto-invoked when looking up terms'
                : 'Auto-invoke this app when looking up terms',
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
                      ? 'Cleared default app for terms'
                      : 'Set ${app.label} as default app for terms',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );

        final sentenceTile = ListTile(
          leading: Icon(
            isSentenceDefault ? Icons.star : Icons.star_border,
            color: isSentenceDefault ? Colors.amber : null,
          ),
          title: Text(
            isSentenceDefault
                ? 'Clear Default for Sentences'
                : 'Set as Default for Sentences',
          ),
          subtitle: Text(
            isSentenceDefault
                ? 'Currently auto-invoked when looking up sentences'
                : 'Auto-invoke this app when looking up sentences',
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
                      ? 'Cleared default app for sentences'
                      : 'Set ${app.label} as default app for sentences',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );

        return SafeArea(
          child: Padding(
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
                        .toggleHideApp(app.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hidden ${app.label}'),
                        duration: const Duration(seconds: 1),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            ref
                                .read(localAppTabConfigProvider.notifier)
                                .toggleHideApp(app.id);
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
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (allApps) {
                        final appMap = {for (var a in allApps) a.id: a};

                        // Current order of all apps
                        final orderedIds = List<String>.from(
                          config.appOrder.where((id) => appMap.containsKey(id)),
                        );
                        for (final app in allApps) {
                          if (!orderedIds.contains(app.id)) {
                            orderedIds.add(app.id);
                          }
                        }

                        final visibleIds = orderedIds
                            .where((id) => !config.hiddenAppIds.contains(id))
                            .toList();
                        final hiddenIds = orderedIds
                            .where((id) => config.hiddenAppIds.contains(id))
                            .toList();

                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.tune),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Manage & Reorder Apps',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => Navigator.pop(sheetContext),
                                    child: const Text('Done'),
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
                                    ? 'Configuring Sentence defaults. Drag to reorder. Tap ⭐ to set default app for sentences.'
                                    : 'Configuring Term defaults. Drag to reorder. Tap ⭐ to set default app for terms.',
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
                                        'Visible Apps (${visibleIds.length})',
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
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: visibleIds.length,
                                      onReorder: (oldIndex, newIndex) {
                                        if (oldIndex < newIndex) {
                                          newIndex -= 1;
                                        }
                                        final item = visibleIds.removeAt(oldIndex);
                                        visibleIds.insert(newIndex, item);

                                        final fullNewOrder = [
                                          ...visibleIds,
                                          ...hiddenIds,
                                        ];
                                        ref
                                            .read(localAppTabConfigProvider.notifier)
                                            .setAppOrder(fullNewOrder);
                                      },
                                      itemBuilder: (context, index) {
                                        final appId = visibleIds[index];
                                        final app = appMap[appId]!;
                                        final isTermDef = app.id ==
                                            config.getDefaultAppId(
                                              isSentence: false,
                                            );
                                        final isSentenceDef = app.id ==
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
                                              '⭐ Default for Terms & Sentences';
                                        } else if (isTermDef) {
                                          defaultBadge =
                                              '⭐ Default for Terms';
                                        } else if (isSentenceDef) {
                                          defaultBadge =
                                              '⭐ Default for Sentences';
                                        }

                                        return ListTile(
                                          key: ValueKey(app.id),
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
                                              _buildAppIcon(app.iconBase64),
                                            ],
                                          ),
                                          title: Text(
                                            app.label,
                                            style: TextStyle(
                                              fontWeight: isCurrentTargetDef
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: defaultBadge != null
                                              ? Text(
                                                  defaultBadge,
                                                  style: TextStyle(
                                                    color: context.m3Primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                )
                                              : null,
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  isCurrentTargetDef
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color: isCurrentTargetDef
                                                      ? Colors.amber
                                                      : null,
                                                ),
                                                tooltip: isCurrentTargetDef
                                                    ? (targetIsSentence
                                                        ? 'Clear default for sentences'
                                                        : 'Clear default for terms')
                                                    : (targetIsSentence
                                                        ? 'Set as default for sentences'
                                                        : 'Set as default for terms'),
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        localAppTabConfigProvider
                                                            .notifier,
                                                      )
                                                      .setDefaultApp(
                                                        isCurrentTargetDef
                                                            ? null
                                                            : app.id,
                                                        isSentence:
                                                            targetIsSentence,
                                                      );
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.visibility_outlined,
                                                ),
                                                tooltip: 'Hide app',
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        localAppTabConfigProvider
                                                            .notifier,
                                                      )
                                                      .toggleHideApp(app.id);
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
                                        'Hidden Apps (${hiddenIds.length})',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                      ),
                                    ),
                                    ...hiddenIds.map((appId) {
                                      final app = appMap[appId]!;
                                      return ListTile(
                                        leading: Opacity(
                                          opacity: 0.5,
                                          child: _buildAppIcon(app.iconBase64),
                                        ),
                                        title: Text(
                                          app.label,
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
                                                .toggleHideApp(app.id);
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
              'All Apps are Hidden',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Manage Apps'),
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
