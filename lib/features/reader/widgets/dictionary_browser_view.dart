import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dictionary_service.dart';
import '../../../core/providers/ai_provider.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../providers/current_book_provider.dart';
import 'android_app_launcher_view.dart';

class DictionaryBrowserView extends ConsumerStatefulWidget {
  final List<DictionarySource> dictionaries;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final String searchText;
  final String? sentence;
  final int languageId;
  final bool isSentence;
  final DictionaryService dictionaryService;
  final VoidCallback onOpenSettings;
  final Widget? Function(
          BuildContext context, DictionarySource dict, int index)?
      customTabBuilder;
  final ValueChanged<String>? onAddAITranslationToField;

  const DictionaryBrowserView({
    super.key,
    required this.dictionaries,
    this.initialPage = 0,
    this.onPageChanged,
    required this.searchText,
    this.sentence,
    required this.languageId,
    required this.isSentence,
    required this.dictionaryService,
    required this.onOpenSettings,
    this.customTabBuilder,
    this.onAddAITranslationToField,
  });

  @override
  ConsumerState<DictionaryBrowserView> createState() =>
      DictionaryBrowserViewState();
}

class DictionaryBrowserViewState extends ConsumerState<DictionaryBrowserView> {
  late PageController _pageController;
  late ScrollController _tabScrollController;
  int _currentPage = 0;
  final Map<int, InAppWebViewController> _webviewControllers = {};
  final Map<int, Uint8List> _tabFavicons = {};
  final Map<int, String> _tabFaviconUrls = {};
  final Map<int, String> _tabTitles = {};
  final Map<int, GlobalKey> _tabKeys = {};
  final Set<int> _preloadedPages = {};
  bool _isPreloading = false;
  bool _hasAutoInvokedLocalApp = false;

  // AI Tab state
  bool _isLoadingAITab = false;
  String? _aiTabTranslation;
  String? _aiTabErrorMessage;
  bool _hasFetchedAITab = false;
  bool _isLoadingVirtualDict = false;
  String? _virtualDictionaryContent;
  String? _virtualDictionaryError;
  bool _hasFetchedVirtualDict = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(
      0,
      widget.dictionaries.isEmpty ? 0 : widget.dictionaries.length - 1,
    );
    _pageController = PageController(initialPage: _currentPage);
    _tabScrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToTab(_currentPage);
      _loadCurrentPageContent();
    });
  }

  @override
  void didUpdateWidget(DictionaryBrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchText != widget.searchText) {
      _hasAutoInvokedLocalApp = false;
      _hasFetchedAITab = false;
      _hasFetchedVirtualDict = false;
      _aiTabTranslation = null;
      _virtualDictionaryContent = null;
      _webviewControllers.clear();
      _tabTitles.clear();
      _tabFavicons.clear();
      _tabFaviconUrls.clear();
      _preloadedPages.clear();
    }

    if (oldWidget.dictionaries != widget.dictionaries) {
      final safePage = widget.initialPage.clamp(
        0,
        widget.dictionaries.isEmpty ? 0 : widget.dictionaries.length - 1,
      );
      if (_currentPage != safePage) {
        _currentPage = safePage;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(safePage);
        }
      }
    }

    if (oldWidget.initialPage != widget.initialPage &&
        widget.initialPage != _currentPage &&
        _pageController.hasClients) {
      _animateToPage(widget.initialPage);
    }
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void animateToTab(int index) {
    _animateToPage(index);
  }

  void _animateToPage(int index) {
    if (index < 0 || index >= widget.dictionaries.length) return;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    _scrollToTab(index);
  }

  void _scrollToTab(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _tabKeys[index];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _loadCurrentPageContent() {
    if (widget.dictionaries.isEmpty ||
        _currentPage >= widget.dictionaries.length) {
      return;
    }
    final currentDict = widget.dictionaries[_currentPage];
    if (currentDict.isAI) {
      if (currentDict.aiType == AIType.virtualDictionary) {
        _fetchVirtualDictionary();
      } else {
        _fetchAITranslationTab();
      }
    }
  }

  Future<void> _preloadAdjacentPages() async {
    if (_isPreloading || !mounted || widget.dictionaries.isEmpty) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;

    _isPreloading = true;

    final pagesToPreload = <int>[];

    if (_currentPage > 0 &&
        !_preloadedPages.contains(_currentPage - 1) &&
        _currentPage - 1 < widget.dictionaries.length &&
        !widget.dictionaries[_currentPage - 1].isAndroidApp &&
        !widget.dictionaries[_currentPage - 1].isImages &&
        !widget.dictionaries[_currentPage - 1].isAI) {
      pagesToPreload.add(_currentPage - 1);
    }

    if (_currentPage < widget.dictionaries.length - 1 &&
        !_preloadedPages.contains(_currentPage + 1) &&
        !widget.dictionaries[_currentPage + 1].isAndroidApp &&
        !widget.dictionaries[_currentPage + 1].isImages &&
        !widget.dictionaries[_currentPage + 1].isAI) {
      pagesToPreload.add(_currentPage + 1);
    }

    if (pagesToPreload.isEmpty) {
      _isPreloading = false;
      return;
    }

    for (final pageIndex in pagesToPreload) {
      if (!mounted) break;

      try {
        _pageController.jumpToPage(pageIndex);
        _preloadedPages.add(pageIndex);

        if (!mounted) break;

        _pageController.jumpToPage(_currentPage);
      } catch (e) {
        if (kDebugMode) {
          print('Error preloading page $pageIndex: $e');
        }
      }
    }

    _isPreloading = false;
  }

  Future<void> _fetchAITranslationTab() async {
    if (_isLoadingAITab || _hasFetchedAITab) return;

    setState(() {
      _isLoadingAITab = true;
      _aiTabTranslation = null;
      _aiTabErrorMessage = null;
    });

    try {
      final aiService = ref.read(aiServiceProvider);
      final currentBookState = ref.read(currentBookProvider);
      final language =
          currentBookState.languageName ??
          currentBookState.book?.language ??
          'Unknown';

      final translation = widget.isSentence
          ? await aiService.translateSentence(
              widget.searchText,
              language,
            )
          : await aiService.translateTerm(
              widget.searchText,
              language,
              sentence: widget.sentence,
            );

      if (mounted) {
        setState(() {
          _isLoadingAITab = false;
          _aiTabTranslation = translation;
          _hasFetchedAITab = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAITab = false;
          _aiTabErrorMessage = e.toString();
          _hasFetchedAITab = true;
        });
      }
    }
  }

  Future<void> _fetchVirtualDictionary() async {
    if (_isLoadingVirtualDict || _hasFetchedVirtualDict) return;

    setState(() {
      _isLoadingVirtualDict = true;
      _virtualDictionaryContent = null;
      _virtualDictionaryError = null;
    });

    try {
      final aiService = ref.read(aiServiceProvider);
      final currentBookState = ref.read(currentBookProvider);
      final language = currentBookState.languageName ?? 'Unknown';

      final content = widget.isSentence
          ? await aiService.getVirtualDictionaryEntry(
              widget.searchText,
              language,
            )
          : await aiService.getTermExplanation(
              widget.searchText,
              language,
              sentence: widget.sentence,
            );

      if (mounted) {
        setState(() {
          _isLoadingVirtualDict = false;
          _virtualDictionaryContent = content;
          _hasFetchedVirtualDict = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingVirtualDict = false;
          _virtualDictionaryError = e.toString();
          _hasFetchedVirtualDict = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dictionaries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          Expanded(child: _buildEmptyState(context)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.appColorScheme.background.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.appColorScheme.border.dividerColor
                    .withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildDictionaryContent(context),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.3,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'No Dictionaries Configured',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Configure dictionaries in language settings.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (widget.dictionaries.isEmpty) {
      return Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.appColorScheme.background.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.appColorScheme.border.dividerColor
                .withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'No Dictionaries',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: widget.onOpenSettings,
              tooltip: 'Settings',
            ),
          ],
        ),
      );
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: context.appColorScheme.background.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.appColorScheme.border.dividerColor
              .withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _tabScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                children: List.generate(widget.dictionaries.length, (index) {
                  final dict = widget.dictionaries[index];
                  final isSelected = _currentPage == index;
                  return _buildTabItem(context, dict, index, isSelected);
                }),
              ),
            ),
          ),
          Container(
            height: 20,
            width: 1,
            color: context.appColorScheme.border.dividerColor
                .withValues(alpha: 0.6),
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            onPressed: widget.onOpenSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    DictionarySource dict,
    int index,
    bool isSelected,
  ) {
    final key = _tabKeys.putIfAbsent(index, () => GlobalKey());
    final primaryColor = context.m3Primary;
    final unselectedTextColor =
        context.appColorScheme.text.primary.withValues(alpha: 0.7);

    Widget iconWidget;
    if (dict.isAndroidApp) {
      iconWidget = Icon(
        Icons.phone_android,
        size: 14,
        color: isSelected ? primaryColor : unselectedTextColor,
      );
    } else if (dict.isImages) {
      iconWidget = Icon(
        Icons.image_search,
        size: 14,
        color: isSelected ? primaryColor : unselectedTextColor,
      );
    } else if (dict.isAI) {
      if (dict.aiType == AIType.virtualDictionary) {
        iconWidget = Icon(
          Icons.psychology,
          size: 14,
          color: isSelected ? primaryColor : unselectedTextColor,
        );
      } else {
        iconWidget = Icon(
          Icons.auto_awesome,
          size: 14,
          color: isSelected ? primaryColor : unselectedTextColor,
        );
      }
    } else {
      final faviconBytes = _tabFavicons[dict.hashCode];
      final faviconUrl = _tabFaviconUrls[dict.hashCode];
      if (faviconBytes != null) {
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.memory(
            faviconBytes,
            width: 14,
            height: 14,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.language,
              size: 14,
              color: isSelected ? primaryColor : unselectedTextColor,
            ),
          ),
        );
      } else if (faviconUrl != null) {
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.network(
            faviconUrl,
            width: 14,
            height: 14,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.language,
              size: 14,
              color: isSelected ? primaryColor : unselectedTextColor,
            ),
          ),
        );
      } else {
        iconWidget = Icon(
          Icons.language,
          size: 14,
          color: isSelected ? primaryColor : unselectedTextColor,
        );
      }
    }

    final title = _tabTitles[dict.hashCode] ?? dict.name;

    return Padding(
      key: key,
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            _animateToPage(index);
          },
          child: Container(
            constraints: const BoxConstraints(maxWidth: 150, minHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? context.appColorScheme.background.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isSelected
                  ? Border.all(
                      color: context.appColorScheme.border.dividerColor,
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              isSelected ? primaryColor : unselectedTextColor,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 12,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDictionaryContent(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      allowImplicitScrolling: true,
      onPageChanged: (index) async {
        if (_isPreloading) return;
        setState(() {
          _currentPage = index;
        });
        _scrollToTab(index);
        final currentDict = widget.dictionaries[index];
        if (widget.isSentence) {
          await widget.dictionaryService.rememberLastUsedSentenceDictionary(
            widget.languageId,
            currentDict.name,
          );
        } else {
          await widget.dictionaryService.rememberLastUsedDictionary(
            widget.languageId,
            currentDict.name,
          );
        }
        widget.onPageChanged?.call(index);
        _loadCurrentPageContent();
      },
      itemCount: widget.dictionaries.length,
      itemBuilder: (context, index) {
        final dict = widget.dictionaries[index];
        if (widget.customTabBuilder != null) {
          final customWidget =
              widget.customTabBuilder!(context, dict, index);
          if (customWidget != null) {
            return customWidget;
          }
        }
        if (dict.isAndroidApp) {
          return AndroidAppLauncherView(
            text: widget.searchText,
            isSentence: widget.isSentence,
            isActive: _currentPage == index,
            autoInvoke: !_hasAutoInvokedLocalApp,
            onAutoInvoked: () {
              if (mounted) {
                setState(() {
                  _hasAutoInvokedLocalApp = true;
                });
              }
            },
          );
        }
        return _buildWebViewPage(context, dict, index);
      },
    );
  }

  Widget _buildWebViewPage(
    BuildContext context,
    DictionarySource dictionary,
    int index,
  ) {
    if (dictionary.isAI) {
      if (dictionary.aiType == AIType.virtualDictionary) {
        return _buildVirtualDictionaryContent(context);
      }
      return _buildAITranslationTabContent(context);
    }

    final url = widget.dictionaryService.buildUrl(
      widget.searchText,
      dictionary.urlTemplate,
    );

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        sharedCookiesEnabled: true,
        cacheEnabled: true,
        javaScriptEnabled: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory(() => VerticalDragGestureRecognizer()),
      },
      onWebViewCreated: (controller) {
        _webviewControllers[dictionary.hashCode] = controller;
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.trim().isNotEmpty && mounted) {
          setState(() {
            _tabTitles[dictionary.hashCode] = title.trim();
          });
        }
      },
      onReceivedIcon: (controller, icon) {
        if (mounted) {
          setState(() {
            _tabFavicons[dictionary.hashCode] = icon;
          });
        }
      },
      onLoadStop: (controller, url) async {
        if (index == _currentPage) {
          _preloadAdjacentPages();
        }
        try {
          final title = await controller.getTitle();
          if (title != null && title.trim().isNotEmpty && mounted) {
            setState(() {
              _tabTitles[dictionary.hashCode] = title.trim();
            });
          }
          final favicons = await controller.getFavicons();
          if (favicons.isNotEmpty && mounted) {
            setState(() {
              _tabFaviconUrls[dictionary.hashCode] =
                  favicons.first.url.toString();
            });
          }
        } catch (_) {}
      },
    );
  }

  Widget _buildAITranslationTabContent(BuildContext context) {
    if (_isLoadingAITab) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_aiTabErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 36, color: context.error),
              const SizedBox(height: 8),
              Text(
                _aiTabErrorMessage!,
                style: TextStyle(color: context.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  _hasFetchedAITab = false;
                  _fetchAITranslationTab();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_aiTabTranslation == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _fetchAITranslationTab,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Translate with AI'),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColorScheme.background.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.appColorScheme.border.dividerColor
                    .withValues(alpha: 0.5),
              ),
            ),
            child: SelectableText(
              _aiTabTranslation!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _aiTabTranslation!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              if (widget.onAddAITranslationToField != null) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    widget.onAddAITranslationToField!(_aiTabTranslation!);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add to Translation'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualDictionaryContent(BuildContext context) {
    if (_isLoadingVirtualDict) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_virtualDictionaryError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 36, color: context.error),
              const SizedBox(height: 8),
              Text(
                _virtualDictionaryError!,
                style: TextStyle(color: context.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  _hasFetchedVirtualDict = false;
                  _fetchVirtualDictionary();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_virtualDictionaryContent == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _fetchVirtualDictionary,
          icon: const Icon(Icons.psychology, size: 16),
          label: const Text('Generate Explanation'),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColorScheme.background.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.appColorScheme.border.dividerColor
                    .withValues(alpha: 0.5),
              ),
            ),
            child: SelectableText(
              _virtualDictionaryContent!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: _virtualDictionaryContent!),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              if (widget.onAddAITranslationToField != null) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    widget.onAddAITranslationToField!(
                      _virtualDictionaryContent!,
                    );
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add to Translation'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
