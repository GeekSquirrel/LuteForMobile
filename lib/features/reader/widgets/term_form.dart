import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/term_form.dart';
import '../models/term_tooltip.dart';
import '../../settings/providers/settings_provider.dart'
    show termFormSettingsProvider;
import '../../settings/models/ai_settings.dart';
import '../../settings/providers/ai_settings_provider.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../core/network/content_service.dart';
import '../../../core/network/dictionary_service.dart';
import '../../../core/widgets/lute_image.dart';
import '../providers/sentence_tts_provider.dart';
import '../../../core/providers/ai_provider.dart';
import '../../../core/providers/android_app_provider.dart';
import 'dictionary_browser_view.dart';
import 'dictionary_tab_reorder_dialog.dart';
import 'parent_search.dart';
import '../providers/current_book_provider.dart';

class TermFormWidget extends ConsumerStatefulWidget {
  final TermForm termForm;
  final String? sentence;
  final String? initialReaderStatus;
  final void Function(TermForm)? onSave;
  final void Function(TermForm) onUpdate;
  final VoidCallback? onCancel;
  final ContentService contentService;
  final void Function(TermParent)? onParentDoubleTap;
  final DictionaryService dictionaryService;
  final VoidCallback? onDismiss;
  final void Function(bool)? onDictionaryToggle;
  final void Function(int langId)? onStatus99Changed;

  const TermFormWidget({
    super.key,
    required this.termForm,
    this.sentence,
    this.initialReaderStatus,
    this.onSave,
    required this.onUpdate,
    this.onCancel,
    required this.contentService,
    required this.dictionaryService,
    this.onParentDoubleTap,
    this.onDismiss,
    this.onDictionaryToggle,
    this.onStatus99Changed,
  });

  @override
  ConsumerState<TermFormWidget> createState() => _TermFormWidgetState();
}

class _TermFormWidgetState extends ConsumerState<TermFormWidget> {
  final GlobalKey<DictionaryBrowserViewState> _browserViewKey =
      GlobalKey<DictionaryBrowserViewState>();
  late TextEditingController _translationController;
  late TextEditingController _romanizationController;
  late TextEditingController _imageSearchController;
  late final FocusNode _translationFocusNode;
  late final FocusNode _romanizationFocusNode;
  late String _selectedStatus;
  late DictionaryService _dictionaryService;
  String? _currentImageUrl;
  String? _currentImageFilename;
  List<DictionarySource> _dictionaries = [];
  int _currentPage = 0;
  bool _hasLoaded = false;
  bool _isLoadingAITranslation = false;
  bool _isSavingImage = false;
  List<String> _pendingAITranslations = [];
  String? _lastAutoFetchedTermKey;
  Timer? _debounceTimer;
  int _popupHeight = DictionaryService.defaultPopupHeight;

  // Image search state
  List<TermImageSearchResult> _imageSearchResults = [];
  bool _isLoadingImages = false;
  String? _imageSearchError;

  @override
  void initState() {
    super.initState();
    _dictionaryService = widget.dictionaryService;
    _translationFocusNode = FocusNode();
    _romanizationFocusNode = FocusNode();
    _translationFocusNode.addListener(_onFocusChange);
    _romanizationFocusNode.addListener(_onFocusChange);
    _translationController = TextEditingController(
      text: widget.termForm.translation ?? '',
    );
    _romanizationController = TextEditingController(
      text: widget.termForm.romanization ?? '',
    );
    _imageSearchController = TextEditingController(
      text: widget.termForm.term,
    );
    _selectedStatus = widget.termForm.status;
    _currentImageUrl = widget.termForm.imageUrl;
    _currentImageFilename = widget.termForm.imageFilename;

    _loadPopupHeight();
    _loadDictionaries();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoFetchAITranslation();
    });
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _translationFocusNode.removeListener(_onFocusChange);
    _romanizationFocusNode.removeListener(_onFocusChange);
    _translationFocusNode.dispose();
    _romanizationFocusNode.dispose();
    _translationController.dispose();
    _romanizationController.dispose();
    _imageSearchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPopupHeight() async {
    final height = await _dictionaryService.getTermFormPopupHeight();
    if (mounted) {
      setState(() {
        _popupHeight = height;
      });
    }
  }

  Future<void> _loadDictionaries({bool preserveCurrentPage = false}) async {
    if (!mounted) return;

    final rawDictionaries = await _dictionaryService.getDictionariesForLanguage(
      widget.termForm.languageId,
    );

    if (!mounted) return;

    final aiSettings = ref.read(aiSettingsProvider);
    final aiConfig = aiSettings.promptConfigs[AIPromptType.termTranslation];
    final shouldAddAI =
        aiSettings.provider != AIProvider.none && aiConfig?.enabled == true;

    final virtualDictConfig =
        aiSettings.promptConfigs[AIPromptType.termExplanation];
    final shouldAddVirtualDict =
        aiSettings.provider != AIProvider.none &&
        virtualDictConfig?.enabled == true;

    final allDictionaries = List<DictionarySource>.from(rawDictionaries);
    if (shouldAddAI) {
      final modelName =
          aiSettings.providerConfigs[aiSettings.provider]?.model ?? 'gpt-4o';
      allDictionaries.add(
        DictionarySource(
          name: 'AI: $modelName',
          urlTemplate: '',
          isAI: true,
          aiType: AIType.translation,
        ),
      );
    }
    if (shouldAddVirtualDict) {
      final modelName =
          aiSettings.providerConfigs[aiSettings.provider]?.model ?? 'gpt-4o';
      allDictionaries.add(
        DictionarySource(
          name: 'Virtual: $modelName',
          urlTemplate: '',
          isAI: true,
          aiType: AIType.virtualDictionary,
        ),
      );
    }

    final appService = ref.read(androidAppServiceProvider);
    final savedOrder = await appService.getTabOrder(
      widget.termForm.languageId,
      isSentence: false,
    );

    final config = ref.read(localAppTabConfigProvider);
    final localAppSource = DictionarySource(
      name: config.tabTitle.isNotEmpty ? config.tabTitle : 'Apps',
      urlTemplate: '',
      isAndroidApp: true,
    );

    const imagesSource = DictionarySource(
      name: 'Images',
      urlTemplate: '',
      isImages: true,
    );

    final ordered = appService.applyTabOrder<DictionarySource>(
      originalItems: allDictionaries,
      getId: (d) => d.name,
      savedOrder: savedOrder,
      localAppItem: localAppSource,
      includeLocalApp: config.enabled && appService.isSupportedPlatform,
      imagesItem: imagesSource,
      includeImages: true,
    );

    int initialPage = 0;
    if (preserveCurrentPage && _currentPage < ordered.length) {
      initialPage = _currentPage;
    } else {
      final lastUsed = await _dictionaryService.getLastUsedDictionary(
        widget.termForm.languageId,
      );
      if (lastUsed != null && ordered.isNotEmpty) {
        final index = ordered.indexWhere((d) => d.name == lastUsed);
        if (index >= 0) {
          initialPage = index;
        } else {
          initialPage = 0;
        }
      } else {
        initialPage = 0;
      }
    }

    if (mounted) {
      setState(() {
        _dictionaries = ordered;
        _currentPage = initialPage;
        _hasLoaded = true;
      });
    }
  }

  void _navigateToImagesTab() {
    final imagesIndex = _dictionaries.indexWhere((d) => d.isImages);
    if (imagesIndex >= 0) {
      _browserViewKey.currentState?.animateToTab(imagesIndex);
      if (_imageSearchResults.isEmpty && !_isLoadingImages) {
        _searchImages();
      }
    }
  }

  @override
  void didUpdateWidget(TermFormWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.termForm.translation != widget.termForm.translation &&
        _translationController.text != (widget.termForm.translation ?? '')) {
      _translationController.text = widget.termForm.translation ?? '';
    }
    if (oldWidget.termForm.romanization != widget.termForm.romanization &&
        _romanizationController.text != (widget.termForm.romanization ?? '')) {
      _romanizationController.text = widget.termForm.romanization ?? '';
    }
    if (oldWidget.termForm.status != widget.termForm.status) {
      _selectedStatus = widget.termForm.status;
    }
    if (oldWidget.termForm.imageUrl != widget.termForm.imageUrl ||
        oldWidget.termForm.imageFilename != widget.termForm.imageFilename) {
      _currentImageUrl = widget.termForm.imageUrl;
      _currentImageFilename = widget.termForm.imageFilename;
    }
    if (oldWidget.termForm.parents != widget.termForm.parents) {
      setState(() {});
    }
    if (oldWidget.termForm.term != widget.termForm.term) {
      _imageSearchController.text = widget.termForm.term;
      _imageSearchResults = [];
      _loadDictionaries(preserveCurrentPage: false);
    }
    if (oldWidget.termForm.term != widget.termForm.term ||
        oldWidget.termForm.termId != widget.termForm.termId ||
        oldWidget.termForm.status != widget.termForm.status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeAutoFetchAITranslation();
      });
    }
  }

  void _updateForm() {
    final updatedForm = widget.termForm.copyWith(
      translation: _translationController.text.trim(),
      status: _selectedStatus,
      romanization: _romanizationController.text.trim(),
      parents: widget.termForm.parents,
    );
    widget.onUpdate(updatedForm);
  }

  List<String> _splitTranslations(String raw) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _addPendingTranslationToField(String translation) {
    final currentTranslations = _splitTranslations(_translationController.text);
    if (!currentTranslations.contains(translation)) {
      currentTranslations.add(translation);
      _translationController.text = currentTranslations.join(', ');
      _updateForm();
    }

    setState(() {
      _pendingAITranslations = _pendingAITranslations
          .where((item) => item != translation)
          .toList();
    });
  }

  void _maybeAutoFetchAITranslation() {
    if (!mounted || _isLoadingAITranslation) return;

    final settings = ref.read(termFormSettingsProvider);
    final aiSettings = ref.read(aiSettingsProvider);
    final termConfig = aiSettings.promptConfigs[AIPromptType.termTranslation];
    final shouldShowAI =
        aiSettings.provider != AIProvider.none && termConfig?.enabled == true;
    final effectiveStatus =
        widget.initialReaderStatus ?? widget.termForm.status;

    if (!settings.autoFetchAITranslationsForStatus0 ||
        !shouldShowAI ||
        effectiveStatus != '0') {
      return;
    }

    final termKey =
        '${widget.termForm.termId ?? 'new'}:${widget.termForm.term}:$effectiveStatus';
    if (_lastAutoFetchedTermKey == termKey) return;

    _lastAutoFetchedTermKey = termKey;
    _fetchAITranslation();
  }

  void _openTabReorderDialog() {
    final rawWebviewDicts =
        _dictionaries.where((d) => !d.isAndroidApp && !d.isImages).toList();
    DictionaryTabReorderDialog.show(
      context,
      languageId: widget.termForm.languageId,
      isSentence: false,
      webviewDictionaries: rawWebviewDicts,
      onOrderChanged: () {
        _loadDictionaries(preserveCurrentPage: true);
      },
    );
  }

  void _showSettingsMenu() {
    final aiSettings = ref.read(aiSettingsProvider);
    final termConfig = aiSettings.promptConfigs[AIPromptType.termTranslation];
    final shouldShowAIOption =
        aiSettings.provider != AIProvider.none && termConfig?.enabled == true;

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final currentSettings = ref.watch(termFormSettingsProvider);
          final notifier = ref.read(termFormSettingsProvider.notifier);

          return AlertDialog(
            title: const Text('Term Form Settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Image Button'),
                    value: currentSettings.showImages,
                    onChanged: (value) {
                      notifier.updateShowImages(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Romanization'),
                    value: currentSettings.showRomanization,
                    onChanged: (value) {
                      notifier.updateShowRomanization(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Tags'),
                    value: currentSettings.showTags,
                    onChanged: (value) {
                      notifier.updateShowTags(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Tooltip Images'),
                    value: currentSettings.showTooltipImages,
                    onChanged: (value) {
                      notifier.updateShowTooltipImages(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Word Glow Effect'),
                    value: currentSettings.wordGlowEnabled,
                    onChanged: (value) {
                      notifier.updateWordGlowEnabled(value);
                    },
                  ),
                  if (shouldShowAIOption) ...[
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-fetch AI for new terms'),
                      value: currentSettings.autoFetchAITranslationsForStatus0,
                      onChanged: (value) {
                        notifier.updateAutoFetchAITranslationsForStatus0(value);
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-add AI translations to field'),
                      value: currentSettings.autoAddAITranslations,
                      onChanged: (value) {
                        notifier.updateAutoAddAITranslations(value);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHeightAdjustmentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Popup Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Popup Height',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    200,
                    250,
                    300,
                    350,
                    400,
                    450,
                    500,
                    550,
                    600,
                  ].map((h) {
                    final isSelected = _popupHeight == h;
                    return ChoiceChip(
                      label: Text('${h}px'),
                      selected: isSelected,
                      onSelected: (selected) async {
                        if (selected) {
                          setDialogState(() {
                            _popupHeight = h;
                          });
                          setState(() {
                            _popupHeight = h;
                          });
                          await _dictionaryService.setTermFormPopupHeight(h);
                        }
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sort),
                  title: const Text('Reorder Tabs'),
                  subtitle: const Text('Change tab order'),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _openTabReorderDialog();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune),
                  title: const Text('Term Form Settings'),
                  subtitle: const Text('Images, Tags, Romanization, AI'),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _showSettingsMenu();
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditTermDialog(BuildContext context) {
    final TextEditingController termEditController = TextEditingController(
      text: widget.termForm.term,
    );

    bool canSave(String newText) {
      if (newText.length != widget.termForm.term.length) {
        return false;
      }
      if (newText.toLowerCase() != widget.termForm.term.toLowerCase()) {
        return false;
      }
      return true;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Term Capitalization'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You can only change the capitalization of letters. '
                  'The number of characters must remain the same.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: termEditController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Term',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    errorText: canSave(termEditController.text)
                        ? null
                        : 'Capitalization only - same characters and length',
                  ),
                  onChanged: (value) {
                    setDialogState(() {});
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  termEditController.text =
                      termEditController.text.toLowerCase();
                  setDialogState(() {});
                },
                child: const Icon(Icons.format_size),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canSave(termEditController.text)
                    ? () {
                        final updatedForm = widget.termForm.copyWith(
                          term: termEditController.text,
                        );
                        widget.onUpdate(updatedForm);
                        Navigator.of(dialogContext).pop();
                      }
                    : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _fetchAITranslation() async {
    if (_isLoadingAITranslation) return;

    setState(() {
      _isLoadingAITranslation = true;
    });

    try {
      final aiService = ref.read(aiServiceProvider);
      final currentBookState = ref.read(currentBookProvider);
      final language =
          currentBookState.languageName ??
          currentBookState.book?.language ??
          'Unknown';

      final translation = await aiService.translateTerm(
        widget.termForm.term,
        language,
        sentence: widget.sentence,
      );
      final cleanTranslations = _splitTranslations(
        translation.replaceAll('\n', ' '),
      );

      if (ref.read(termFormSettingsProvider).autoAddAITranslations) {
        final currentTranslations = _splitTranslations(
          _translationController.text,
        );
        for (final item in cleanTranslations) {
          if (!currentTranslations.contains(item)) {
            currentTranslations.add(item);
          }
        }
        _translationController.text = currentTranslations.join(', ');
        _updateForm();
      } else {
        final existingTranslations = _splitTranslations(
          _translationController.text,
        );
        setState(() {
          _pendingAITranslations = cleanTranslations
              .where((item) => !existingTranslations.contains(item))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI translation failed: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAITranslation = false;
        });
      }
    }
  }

  // --- Image search methods ---
  Future<void> _searchImages() async {
    final query = _imageSearchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoadingImages = true;
      _imageSearchError = null;
    });

    try {
      final results = await widget.contentService.searchTermImages(
        widget.termForm.languageId,
        query,
        '',
      );
      if (mounted) {
        setState(() {
          _imageSearchResults = results;
          if (results.isEmpty) {
            _imageSearchError = 'No images found';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageSearchError = _extractErrorMessage(e);
          _imageSearchResults = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingImages = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    await _saveImage(
      operation: () => widget.contentService.uploadTermImage(
        widget.termForm.languageId,
        widget.termForm.term,
        path,
      ),
      successMessage: 'Image uploaded',
    );
  }

  void _showImageUrlDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save Image From URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/image.jpg',
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) async {
            final imageUrl = controller.text.trim();
            if (imageUrl.isEmpty) return;
            Navigator.of(dialogContext).pop();
            await _saveImage(
              operation: () => widget.contentService.saveTermImageFromUrl(
                widget.termForm.languageId,
                widget.termForm.term,
                imageUrl,
              ),
              successMessage: 'Image saved',
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final imageUrl = controller.text.trim();
              if (imageUrl.isEmpty) return;
              Navigator.of(dialogContext).pop();
              await _saveImage(
                operation: () => widget.contentService.saveTermImageFromUrl(
                  widget.termForm.languageId,
                  widget.termForm.term,
                  imageUrl,
                ),
                successMessage: 'Image saved',
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage({
    required Future<TermImageUploadResult> Function() operation,
    required String successMessage,
  }) async {
    if (_isSavingImage) return;

    setState(() {
      _isSavingImage = true;
    });

    try {
      final result = await operation();
      setState(() {
        _currentImageUrl = result.imageUrl ?? _currentImageUrl;
        _currentImageFilename = result.imageFilename ?? _currentImageFilename;
      });

      final updatedForm = widget.termForm.copyWith(
        imageUrl: _currentImageUrl,
        imageFilename: _currentImageFilename,
      );

      widget.onUpdate(updatedForm);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        final message = _extractErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image update failed: $message')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingImage = false;
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      _currentImageUrl = null;
      _currentImageFilename = null;
    });

    widget.onUpdate(widget.termForm.copyWith(clearImage: true));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image removed')));
    }
  }

  String _extractErrorMessage(Object error) {
    final raw = error.toString();
    final marker = 'Exception: ';
    final normalized =
        raw.startsWith(marker) ? raw.substring(marker.length) : raw;

    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map) {
        for (final key in const ['error', 'message', 'detail']) {
          final value = decoded[key]?.toString().trim();
          if (value != null && value.isNotEmpty) {
            return value;
          }
        }
      }
    } catch (_) {}

    return normalized;
  }

  // --- UI Builders ---
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxModalHeight = screenHeight * 0.94;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardHeight = viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    if (!_hasLoaded) {
      return Container(
        constraints: BoxConstraints(maxHeight: maxModalHeight),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.appColorScheme.background.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final browserHeight = _popupHeight.toDouble().clamp(
          DictionaryService.minPopupHeight.toDouble(),
          screenHeight * 0.75,
        );

    final isBottomFormFocused =
        _translationFocusNode.hasFocus || _romanizationFocusNode.hasFocus;
    final isBottomEditing = isBottomFormFocused && isKeyboardOpen;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: isBottomEditing ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final currentKeyboardOffset = keyboardHeight * t;

        return SizedBox(
          height: screenHeight,
          width: double.infinity,
          child: Stack(
            children: [
              // Full-screen focus scrim over the entire screen behind the modal
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (isKeyboardOpen) {
                      FocusScope.of(context).unfocus();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.50 * t),
                  ),
                ),
              ),

              // Modal sheet container aligned to bottom
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: maxModalHeight,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  decoration: BoxDecoration(
                    color: context.appColorScheme.background.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top browser card: stationary in x, y; moves into screen along z-axis
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(
                            1.0 - 0.04 * t,
                            1.0 - 0.04 * t,
                            1.0,
                          )
                            ..setTranslationRaw(0.0, 0.0, -25.0 * t)
                            ..setEntry(3, 2, 0.001),
                          child: Stack(
                            children: [
                              ExcludeFocus(
                                excluding: t > 0.01,
                                child: SizedBox(
                                  height: browserHeight,
                                  child: DictionaryBrowserView(
                                    key: _browserViewKey,
                                    dictionaries: _dictionaries,
                                    initialPage: _currentPage,
                                    searchText: widget.termForm.term,
                                    sentence: widget.sentence,
                                    languageId: widget.termForm.languageId,
                                    isSentence: false,
                                    dictionaryService: widget.dictionaryService,
                                    onPageChanged: (index) {
                                      _currentPage = index;
                                      if (index < _dictionaries.length &&
                                          _dictionaries[index].isImages &&
                                          _imageSearchResults.isEmpty &&
                                          !_isLoadingImages) {
                                        _searchImages();
                                      }
                                    },
                                    onOpenSettings: () =>
                                        _showHeightAdjustmentDialog(context),
                                    customTabBuilder: (context, dict, index) {
                                      if (dict.isImages) {
                                        return _buildImagesPageView(context);
                                      }
                                      return null;
                                    },
                                    onAddAITranslationToField:
                                        _addPendingTranslationToField,
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: t < 0.01,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => FocusScope.of(context).unfocus(),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Color.lerp(
                                          Colors.transparent,
                                          context.appColorScheme.background.background
                                              .withValues(alpha: 0.94),
                                          t,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: context.appColorScheme.border.dividerColor
                                              .withValues(alpha: 0.3 * t),
                                        ),
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity:
                                              (t - 0.3).clamp(0.0, 1.0) / 0.7,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: context
                                                  .appColorScheme
                                                  .background
                                                  .surface
                                                  .withValues(alpha: 0.85),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: context
                                                    .appColorScheme
                                                    .border
                                                    .dividerColor
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.edit_note_rounded,
                                                  size: 18,
                                                  color: context.m3Primary,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Tap to return to dictionary',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: context
                                                            .appColorScheme
                                                            .text
                                                            .primary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 14.0 * (1.0 - t).clamp(0.0, 1.0),
                          ),
                          child: Opacity(
                            opacity: (1.0 - t).clamp(0.0, 1.0),
                            child: Divider(
                              height: 1,
                              thickness: 1.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                        ),

                        // Bottom card: pushed along y-axis by keyboard, blurring content behind it
                        Transform.translate(
                          offset: Offset(0, -currentKeyboardOffset),
                          child: _buildTermFormSection(context, t),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagesPageView(BuildContext context) {
    return Column(
      children: [
        // Top search bar + upload actions
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _imageSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search images...',
                      hintStyle: const TextStyle(fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search, size: 18),
                        padding: EdgeInsets.zero,
                        onPressed: _searchImages,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchImages(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Upload file',
                child: IconButton(
                  icon: const Icon(Icons.upload_file, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 34, height: 34),
                  onPressed: _isSavingImage ? null : _pickAndUploadImage,
                ),
              ),
              Tooltip(
                message: 'From URL',
                child: IconButton(
                  icon: const Icon(Icons.link, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 34, height: 34),
                  onPressed:
                      _isSavingImage ? null : () => _showImageUrlDialog(context),
                ),
              ),
            ],
          ),
        ),

        // If currently attached image exists, show current preview banner
        if (_currentImageUrl != null &&
            _currentImageUrl!.trim().isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.appColorScheme.background.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.appColorScheme.border.dividerColor
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: LuteImage(
                      imageUrl: _currentImageUrl,
                      fit: BoxFit.cover,
                      errorWidget: _buildSmallImagePlaceholder(context),
                      placeholder: _buildSmallImagePlaceholder(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentImageFilename?.isNotEmpty == true
                        ? 'Current: $_currentImageFilename'
                        : 'Current term image',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 30, height: 30),
                  tooltip: 'Remove current image',
                  onPressed: _isSavingImage ? null : _removeImage,
                ),
              ],
            ),
          ),
        ],

        // Grid of search results or states
        Expanded(
          child: _isLoadingImages
              ? const Center(child: CircularProgressIndicator())
              : _imageSearchError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            size: 36,
                            color: context.error,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _imageSearchError!,
                            style: TextStyle(
                              color: context.error,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _searchImages,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _imageSearchResults.isEmpty
                      ? Center(
                          child: TextButton.icon(
                            onPressed: _searchImages,
                            icon: const Icon(Icons.image_search),
                            label: const Text('Search Images for this term'),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.3,
                          ),
                          itemCount: _imageSearchResults.length,
                          itemBuilder: (context, index) {
                            final result = _imageSearchResults[index];
                            final previewUrl =
                                result.thumbnailUrl ?? result.imageUrl;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isSavingImage
                                    ? null
                                    : () async {
                                        await _saveImage(
                                          operation: () => widget.contentService
                                              .saveTermImageFromUrl(
                                            widget.termForm.languageId,
                                            widget.termForm.term,
                                            result.imageUrl,
                                          ),
                                          successMessage:
                                              'Image saved as term image',
                                        );
                                      },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: context
                                          .appColorScheme.border.dividerColor,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: LuteImage(
                                      imageUrl: previewUrl,
                                      fit: BoxFit.cover,
                                      errorWidget:
                                          _buildImagePlaceholder(context),
                                      placeholder:
                                          _buildImagePlaceholder(context),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildSmallImagePlaceholder(BuildContext context) {
    return Icon(
      Icons.image_outlined,
      size: 16,
      color: context.m3Secondary.withValues(alpha: 0.8),
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.appColorScheme.background.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 48,
        color: context.m3Secondary.withValues(alpha: 0.8),
      ),
    );
  }

  // --- Bottom Term Form Section ---
  Widget _buildTermFormSection(BuildContext context, [double t = 0.0]) {
    final settings = ref.watch(termFormSettingsProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.appColorScheme.background.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.appColorScheme.border.dividerColor
              .withValues(alpha: 0.5 + 0.3 * t),
          width: 1,
        ),
        boxShadow: t > 0.001
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25 * t),
                  blurRadius: 16 * t,
                  spreadRadius: 1 * t,
                  offset: Offset(0, -4 * t),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Term Title + TTS Button + (Right: Image Button if enabled)
          Row(
            children: [
              Flexible(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPress: () => _showEditTermDialog(context),
                  child: Text(
                    widget.termForm.term,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: context.appColorScheme.text.primary,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Consumer(
                builder: (context, ref, child) {
                  final ttsState = ref.watch(sentenceTTSProvider);
                  final isCurrentTerm =
                      ttsState.currentText == widget.termForm.term;

                  IconData icon;
                  Color color;
                  VoidCallback? onPressed;

                  if (isCurrentTerm && ttsState.isLoading) {
                    icon = Icons.hourglass_empty;
                    color = context.m3Primary;
                    onPressed = null;
                  } else if (isCurrentTerm && ttsState.isPlaying) {
                    icon = Icons.stop;
                    color = context.error;
                    onPressed = () =>
                        ref.read(sentenceTTSProvider.notifier).stop();
                  } else {
                    icon = Icons.volume_up;
                    color = context.m3Primary;
                    onPressed = () => ref
                        .read(sentenceTTSProvider.notifier)
                        .speakSentence(widget.termForm.term, 0);
                  }

                  return IconButton(
                    icon: Icon(icon, size: 20),
                    color: color,
                    onPressed: onPressed,
                    tooltip: isCurrentTerm && ttsState.isPlaying
                        ? 'Stop TTS'
                        : 'Read term',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Translation Field + AI Quick add + Image Button
          _buildTranslationField(context),
          const SizedBox(height: 8),

          // Row 3: Status buttons (1, 2, 3, 4, 5, ✓ 99, ✕ 98) evenly spaced
          _buildStatusField(context),

          if (widget.termForm.showRomanization &&
              settings.showRomanization) ...[
            const SizedBox(height: 8),
            _buildRomanizationField(context),
          ],
          if (settings.showTags) ...[
            const SizedBox(height: 8),
            _buildTagsSection(context),
          ],
          const SizedBox(height: 8),
          _buildParentsSection(context),
        ],
      ),
    );
  }

  Widget _buildFormImageButton(BuildContext context) {
    final hasImage =
        _currentImageUrl != null && _currentImageUrl!.trim().isNotEmpty;

    return Tooltip(
      message: hasImage ? 'View / Search Images' : 'Search images',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToImagesTab,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: context.appColorScheme.background.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.appColorScheme.border.dividerColor,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: hasImage
                  ? LuteImage(
                      imageUrl: _currentImageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: Icon(
                        Icons.image_outlined,
                        size: 22,
                        color: context.appColorScheme.text.primary
                            .withValues(alpha: 0.7),
                      ),
                      placeholder: Icon(
                        Icons.image_outlined,
                        size: 22,
                        color: context.appColorScheme.text.primary
                            .withValues(alpha: 0.7),
                      ),
                    )
                  : Icon(
                      Icons.image_outlined,
                      size: 22,
                      color: context.appColorScheme.text.primary
                          .withValues(alpha: 0.7),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTranslationField(BuildContext context) {
    final settings = ref.watch(termFormSettingsProvider);
    final aiSettings = ref.watch(aiSettingsProvider);
    final termConfig = aiSettings.promptConfigs[AIPromptType.termTranslation];
    final shouldShowAI =
        aiSettings.provider != AIProvider.none && termConfig?.enabled == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!settings.autoAddAITranslations &&
            _pendingAITranslations.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _pendingAITranslations.map((translation) {
                return ActionChip(
                  avatar: const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(
                    translation,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () =>
                      _addPendingTranslationToField(translation),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextFormField(
                  focusNode: _translationFocusNode,
                  controller: _translationController,
                  decoration: InputDecoration(
                    labelText: 'Translation',
                    labelStyle:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: context.m3Secondary,
                              fontWeight: FontWeight.w600,
                            ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'Enter translation',
                    hintStyle: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(_updateForm),
                ),
              ),
              if (shouldShowAI) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoadingAITranslation
                        ? null
                        : _fetchAITranslation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.m3Primary,
                      foregroundColor:
                          context.appColorScheme.text.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: _isLoadingAITranslation
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                context.appColorScheme.text.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.psychology, size: 22),
                  ),
                ),
              ],
              if (settings.showImages) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: _buildFormImageButton(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusField(BuildContext context) {
    final statusItems = [
      ('1', '1', _getStatusColor('1')),
      ('2', '2', _getStatusColor('2')),
      ('3', '3', _getStatusColor('3')),
      ('4', '4', _getStatusColor('4')),
      ('5', '5', _getStatusColor('5')),
      ('99', '✓', _getStatusColor('99')),
      ('98', '✕', _getStatusColor('98')),
    ];

    return Row(
      children: statusItems.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildStatusButton(context, item.$1, item.$2, item.$3),
          ),
        );
      }).toList(),
    );
  }

  Color _getStatusColor(String status) {
    return context.getStatusColorForVisualization(status);
  }

  Widget _buildStatusButton(
    BuildContext context,
    String statusValue,
    String label,
    Color statusColor,
  ) {
    final isSelected = _selectedStatus == statusValue;

    // Special styling for Well-Known (99): classic green background with white checkmark
    if (statusValue == '99') {
      const greenColor = Color(0xFF2E7D32);
      final bgColor =
          isSelected ? greenColor : greenColor.withValues(alpha: 0.28);
      final borderColor =
          isSelected ? greenColor : greenColor.withValues(alpha: 0.7);
      final checkColor = isSelected
          ? const Color(0xFFFFFFFF)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.45);

      return InkWell(
        onTap: () {
          final oldStatus = _selectedStatus;
          setState(() {
            _selectedStatus = statusValue;
          });
          if (oldStatus != '99') {
            widget.onStatus99Changed?.call(widget.termForm.languageId);
          }
          _updateForm();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : 1.2,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 19,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: checkColor,
              ),
            ),
          ),
        ),
      );
    }

    final labelColor = isSelected ? const Color(0xFFFFFFFF) : statusColor;
    final bgColor =
        isSelected ? statusColor : statusColor.withValues(alpha: 0.18);
    final borderColor =
        isSelected ? statusColor : statusColor.withValues(alpha: 0.55);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStatus = statusValue;
        });
        _updateForm();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: labelColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRomanizationField(BuildContext context) {
    return TextFormField(
      focusNode: _romanizationFocusNode,
      controller: _romanizationController,
      decoration: InputDecoration(
        labelText: 'Romanization',
        labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.m3Secondary,
              fontWeight: FontWeight.w600,
            ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        hintText: 'Enter romanization (optional)',
        hintStyle: TextStyle(
          color: context.appColorScheme.text.primary.withValues(alpha: 0.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
      onChanged: (_) => _updateForm(),
    );
  }

  Widget _buildTagsSection(BuildContext context) {
    final tags = widget.termForm.tags ?? [];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Tags',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.m3Secondary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ...tags.map((tag) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildTagChip(context, tag),
                  );
                }),
                _buildAddBadgeButton(
                  context: context,
                  onTap: () => _showAddTagDialog(context),
                  tooltip: 'Add Tag',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagChip(BuildContext context, String tag) {
    return GestureDetector(
      onLongPress: () => _showDeleteTagConfirmation(context, tag),
      child: Chip(
        label: Text(tag, style: const TextStyle(fontSize: 11)),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: null,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      ),
    );
  }

  void _showAddTagDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter tag name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              _addTag(value.trim());
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _addTag(controller.text.trim());
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addTag(String tag) {
    if (widget.termForm.tags == null) {
      final updatedForm = widget.termForm.copyWith(tags: [tag]);
      widget.onUpdate(updatedForm);
    } else {
      if (!widget.termForm.tags!.contains(tag)) {
        final updatedForm = widget.termForm.copyWith(
          tags: [...widget.termForm.tags!, tag],
        );
        widget.onUpdate(updatedForm);
      }
    }
  }

  void _showDeleteTagConfirmation(BuildContext context, String tag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Tag'),
        content: Text('Remove tag "$tag"?'),
        actions: [
          TextButton(
            onPressed: () {
              _removeTag(tag);
              Navigator.of(context).pop();
            },
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _removeTag(String tag) {
    if (widget.termForm.tags != null) {
      final updatedForm = widget.termForm.copyWith(
        tags: widget.termForm.tags!.where((t) => t != tag).toList(),
      );
      widget.onUpdate(updatedForm);
    }
  }

  Widget _buildAddBadgeButton({
    required BuildContext context,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.appColorScheme.background.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(
                color: context.appColorScheme.border.dividerColor,
                width: 1,
              ),
            ),
            child: Icon(
              Icons.add,
              size: 16,
              color: context.m3Primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParentsSection(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Parents',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.m3Secondary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ...widget.termForm.parents.map((parent) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildParentChip(context, parent),
                  );
                }),
                _buildAddBadgeButton(
                  context: context,
                  onTap: () => _showAddParentDialog(context),
                  tooltip: 'Add Parent',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParentChip(BuildContext context, TermParent parent) {
    final status = parent.status?.toString() ?? '0';
    final textColor = context.getStatusTextColor(status);
    final backgroundColor = context.getStatusBackgroundColor(status);

    return GestureDetector(
      onLongPress: () => _showDeleteParentConfirmation(context, parent),
      onTap: () {
        if (widget.onParentDoubleTap != null) {
          widget.onParentDoubleTap!(parent);
        }
      },
      onDoubleTap: () {
        if (widget.onParentDoubleTap != null) {
          widget.onParentDoubleTap!(parent);
        }
      },
      child: Chip(
        backgroundColor: backgroundColor,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              parent.term,
              style: TextStyle(color: textColor, fontSize: 11),
            ),
            if (parent.translation != null &&
                parent.translation!.trim().isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                '(${parent.translation})',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddParentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Parent Term',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ParentSearchWidget(
                  languageId: widget.termForm.languageId,
                  existingParentIds: widget.termForm.parents
                      .map((p) => p.id)
                      .where((id) => id != null)
                      .cast<int>()
                      .toList(),
                  contentService: widget.contentService,
                  onParentSelected: (parent) {
                    _addParent(parent);
                  },
                  onDone: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addParent(TermParent parent) {
    final updatedForm = widget.termForm.copyWith(
      parents: [...widget.termForm.parents, parent],
    );
    widget.onUpdate(updatedForm);
  }

  void _removeParent(TermParent parent) {
    final updatedForm = widget.termForm.copyWith(
      parents: widget.termForm.parents.where((p) => p != parent).toList(),
    );
    widget.onUpdate(updatedForm);
  }

  void _showDeleteParentConfirmation(BuildContext context, TermParent parent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Parent'),
        content: Text('Remove parent term from "${parent.term}"?'),
        actions: [
          TextButton(
            onPressed: () {
              _removeParent(parent);
              Navigator.of(context).pop();
            },
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
