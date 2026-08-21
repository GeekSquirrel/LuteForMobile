import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dictionary_service.dart';
import '../../../core/providers/android_app_provider.dart';
import '../../../core/services/android_app_service.dart';
import '../../../shared/theme/theme_extensions.dart';

class TabOrderItem {
  final String id;
  final String name;
  final bool isLocalApp;
  final bool isAI;
  final bool isImages;

  const TabOrderItem({
    required this.id,
    required this.name,
    this.isLocalApp = false,
    this.isAI = false,
    this.isImages = false,
  });
}

class DictionaryTabReorderDialog extends ConsumerStatefulWidget {
  final int languageId;
  final bool isSentence;
  final List<DictionarySource> webviewDictionaries;
  final VoidCallback onOrderChanged;

  const DictionaryTabReorderDialog({
    super.key,
    required this.languageId,
    this.isSentence = false,
    required this.webviewDictionaries,
    required this.onOrderChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required int languageId,
    bool isSentence = false,
    required List<DictionarySource> webviewDictionaries,
    required VoidCallback onOrderChanged,
  }) {
    return showDialog(
      context: context,
      builder: (context) => DictionaryTabReorderDialog(
        languageId: languageId,
        isSentence: isSentence,
        webviewDictionaries: webviewDictionaries,
        onOrderChanged: onOrderChanged,
      ),
    );
  }

  @override
  ConsumerState<DictionaryTabReorderDialog> createState() =>
      _DictionaryTabReorderDialogState();
}

class _DictionaryTabReorderDialogState
    extends ConsumerState<DictionaryTabReorderDialog> {
  List<TabOrderItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTabOrder();
  }

  Future<void> _loadTabOrder() async {
    final appService = ref.read(androidAppServiceProvider);
    final savedOrder = await appService.getTabOrder(
      widget.languageId,
      isSentence: widget.isSentence,
    );

    // Build all available items
    final allItemsMap = <String, TabOrderItem>{};

    for (final dict in widget.webviewDictionaries) {
      if (dict.isAndroidApp || dict.isImages) continue;
      allItemsMap[dict.name] = TabOrderItem(
        id: dict.name,
        name: dict.name,
        isAI: dict.isAI,
      );
    }

    if (!widget.isSentence) {
      allItemsMap[AndroidAppService.imagesTabId] = const TabOrderItem(
        id: AndroidAppService.imagesTabId,
        name: 'Images',
        isImages: true,
      );
    }

    // Add local app tab if on Android or supported
    if (appService.isSupportedPlatform) {
      final config = ref.read(localAppTabConfigProvider);
      allItemsMap[AndroidAppService.localAppsTabId] = TabOrderItem(
        id: AndroidAppService.localAppsTabId,
        name: config.tabTitle.isNotEmpty ? config.tabTitle : 'Local Apps',
        isLocalApp: true,
      );
    }

    final orderedList = <TabOrderItem>[];
    final consumed = <String>{};

    if (savedOrder.isNotEmpty) {
      for (final id in savedOrder) {
        if (allItemsMap.containsKey(id)) {
          orderedList.add(allItemsMap[id]!);
          consumed.add(id);
        }
      }
    }

    // Append any remaining items
    for (final entry in allItemsMap.entries) {
      if (!consumed.contains(entry.key)) {
        orderedList.add(entry.value);
      }
    }

    if (mounted) {
      setState(() {
        _items = orderedList;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTabOrder() async {
    final appService = ref.read(androidAppServiceProvider);
    final orderIds = _items.map((i) => i.id).toList();
    await appService.saveTabOrder(
      widget.languageId,
      orderIds,
      isSentence: widget.isSentence,
    );
    widget.onOrderChanged();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _resetToDefault() {
    final allItems = <TabOrderItem>[];
    for (final dict in widget.webviewDictionaries) {
      if (dict.isAndroidApp || dict.isImages) continue;
      allItems.add(
        TabOrderItem(
          id: dict.name,
          name: dict.name,
          isAI: dict.isAI,
        ),
      );
    }

    if (!widget.isSentence) {
      allItems.add(
        const TabOrderItem(
          id: AndroidAppService.imagesTabId,
          name: 'Images',
          isImages: true,
        ),
      );
    }

    final appService = ref.read(androidAppServiceProvider);
    if (appService.isSupportedPlatform) {
      final config = ref.read(localAppTabConfigProvider);
      allItems.add(
        TabOrderItem(
          id: AndroidAppService.localAppsTabId,
          name: config.tabTitle.isNotEmpty ? config.tabTitle : 'Local Apps',
          isLocalApp: true,
        ),
      );
    }

    setState(() {
      _items = allItems;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.sort, color: context.m3Primary),
          const SizedBox(width: 8),
          Text(
            widget.isSentence
                ? 'Sentence Tab Order'
                : 'Dictionary Tab Order',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              )
            : _items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No tabs available to reorder.'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Drag items up or down to customize the tab order.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          itemCount: _items.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (oldIndex < newIndex) {
                                newIndex -= 1;
                              }
                              final item = _items.removeAt(oldIndex);
                              _items.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final item = _items[index];

                            return ListTile(
                              key: ValueKey(item.id),
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
                                  Icon(
                                    item.isLocalApp
                                        ? Icons.phone_android
                                        : item.isImages
                                            ? Icons.image_search
                                            : item.isAI
                                                ? Icons.auto_awesome
                                                : Icons.language,
                                    color: (item.isLocalApp || item.isImages)
                                        ? context.m3Primary
                                        : null,
                                    size: 20,
                                  ),
                                ],
                              ),
                              title: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: item.isLocalApp
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: (item.isLocalApp || item.isImages)
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.m3Primary.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Local App',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.m3Primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _resetToDefault,
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _items.isEmpty ? null : _saveTabOrder,
          child: const Text('Save Order'),
        ),
      ],
    );
  }
}
