import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sentence_translation.dart';
import '../../settings/models/ai_settings.dart';
import '../../settings/providers/ai_settings_provider.dart';
import '../../../core/providers/android_app_provider.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../core/network/dictionary_service.dart';
import '../providers/sentence_tts_provider.dart';
import 'dictionary_browser_view.dart';
import 'dictionary_tab_reorder_dialog.dart';

class SentenceTranslationWidget extends ConsumerStatefulWidget {
  final String sentence;
  final SentenceTranslation? translation;
  final String translationProvider;
  final VoidCallback? onTranslate;
  final VoidCallback onClose;
  final VoidCallback? onPreviousSentence;
  final VoidCallback? onNextSentence;
  final int languageId;
  final DictionaryService dictionaryService;

  const SentenceTranslationWidget({
    super.key,
    required this.sentence,
    this.translation,
    required this.translationProvider,
    this.onTranslate,
    required this.onClose,
    this.onPreviousSentence,
    this.onNextSentence,
    required this.languageId,
    required this.dictionaryService,
  });

  @override
  ConsumerState<SentenceTranslationWidget> createState() =>
      _SentenceTranslationWidgetState();
}

class _SentenceTranslationWidgetState
    extends ConsumerState<SentenceTranslationWidget> {
  late TextEditingController _textController;
  late String _currentText;
  Timer? _debounceTimer;
  List<DictionarySource> _dictionaries = [];
  int _currentPage = 0;
  bool _hasLoaded = false;
  int _popupHeight = DictionaryService.defaultPopupHeight;

  @override
  void initState() {
    super.initState();
    _currentText = widget.sentence;
    _textController = TextEditingController(text: _currentText);
    _loadPopupHeight();
    _loadDictionaries();
  }

  @override
  void didUpdateWidget(SentenceTranslationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentence != widget.sentence) {
      _currentText = widget.sentence;
      _textController.text = widget.sentence;
    }
  }

  Future<void> _loadPopupHeight() async {
    final height = await widget.dictionaryService
        .getSentenceTranslationPopupHeight();
    if (mounted) {
      setState(() {
        _popupHeight = height;
      });
    }
  }

  Future<void> _loadDictionaries({bool preserveCurrentPage = false}) async {
    if (!mounted) return;

    final rawDictionaries = await widget.dictionaryService
        .getSentenceDictionariesForLanguage(widget.languageId);

    if (!mounted) return;

    final aiSettings = ref.read(aiSettingsProvider);
    final aiConfig = aiSettings.promptConfigs[AIPromptType.sentenceTranslation];
    final shouldAddAI =
        aiSettings.provider != AIProvider.none && aiConfig?.enabled == true;

    final virtualDictConfig =
        aiSettings.promptConfigs[AIPromptType.virtualDictionary];
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
          name: 'AI Dictionary ($modelName)',
          urlTemplate: '',
          isAI: true,
          aiType: AIType.virtualDictionary,
        ),
      );
    }

    final appService = ref.read(androidAppServiceProvider);
    final config = ref.read(localAppTabConfigProvider);
    final localAppSource = appService.isSupportedPlatform
        ? DictionarySource(
            name: config.tabTitle.isNotEmpty ? config.tabTitle : 'Apps',
            urlTemplate: '',
            isAndroidApp: true,
          )
        : null;

    final savedOrder = await appService.getTabOrder(
      widget.languageId,
      isSentence: true,
    );

    final ordered = appService.applyTabOrder<DictionarySource>(
      originalItems: allDictionaries,
      getId: (d) => d.name,
      savedOrder: savedOrder,
      localAppItem: localAppSource,
      includeLocalApp: config.enabled && appService.isSupportedPlatform,
    );

    int initialPage = _currentPage;
    if (!preserveCurrentPage) {
      final lastUsed = await widget.dictionaryService
          .getLastUsedSentenceDictionary(widget.languageId);
      if (lastUsed != null && ordered.isNotEmpty) {
        final index = ordered.indexWhere((d) => d.name == lastUsed);
        if (index >= 0) {
          initialPage = index;
        }
      }
    }

    if (ordered.isNotEmpty) {
      initialPage = initialPage.clamp(0, ordered.length - 1);
    } else {
      initialPage = 0;
    }

    if (mounted) {
      setState(() {
        _dictionaries = ordered;
        _currentPage = initialPage;
        _hasLoaded = true;
      });
    }
  }

  void _openTabReorderDialog() {
    final rawWebviewDicts =
        _dictionaries.where((d) => !d.isAndroidApp).toList();
    DictionaryTabReorderDialog.show(
      context,
      languageId: widget.languageId,
      isSentence: true,
      webviewDictionaries: rawWebviewDicts,
      onOrderChanged: () {
        _loadDictionaries(preserveCurrentPage: true);
      },
    );
  }

  void _onTextChanged(String newText) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _currentText = newText;
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    ref.read(sentenceTTSProvider.notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxModalHeight = screenHeight * 0.94;
    final maxAvailableHeight =
        (screenHeight - viewInsets.bottom - 16).clamp(240.0, maxModalHeight);

    final browserHeight = _popupHeight.toDouble().clamp(
          DictionaryService.minPopupHeight.toDouble(),
          screenHeight * 0.75,
        );

    if (!_hasLoaded) {
      return Container(
        constraints: BoxConstraints(maxHeight: maxAvailableHeight),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.appColorScheme.background.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxAvailableHeight),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: context.appColorScheme.background.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: browserHeight,
              child: DictionaryBrowserView(
                dictionaries: _dictionaries,
                initialPage: _currentPage,
                searchText: _currentText,
                languageId: widget.languageId,
                isSentence: true,
                dictionaryService: widget.dictionaryService,
                onPageChanged: (index) {
                  _currentPage = index;
                },
                onOpenSettings: () => _showHeightAdjustmentDialog(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 14),
              child: Divider(
                height: 1,
                thickness: 1.5,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.35),
              ),
            ),
            _buildTextSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColorScheme.background.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.appColorScheme.border.dividerColor
              .withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Text',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: context.appColorScheme.text.primary,
                    ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    color: context.m3Primary,
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _currentText),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Text copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    tooltip: 'Copy text',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 4),
                  Consumer(
                    builder: (context, ref, child) {
                      final ttsState = ref.watch(sentenceTTSProvider);
                      final isCurrentSentence =
                          ttsState.currentText == _currentText;

                      IconData icon;
                      Color color;
                      VoidCallback? onPressed;

                      if (isCurrentSentence && ttsState.isLoading) {
                        icon = Icons.hourglass_empty;
                        color = context.m3Primary;
                        onPressed = null;
                      } else if (isCurrentSentence && ttsState.isPlaying) {
                        icon = Icons.stop;
                        color = context.error;
                        onPressed = () =>
                            ref.read(sentenceTTSProvider.notifier).stop();
                      } else {
                        icon = Icons.volume_up;
                        color = context.m3Primary;
                        onPressed = () => ref
                            .read(sentenceTTSProvider.notifier)
                            .speakSentence(_currentText, 0);
                      }

                      return IconButton(
                        icon: Icon(icon, size: 20),
                        color: color,
                        onPressed: onPressed,
                        tooltip: isCurrentSentence && ttsState.isPlaying
                            ? 'Stop TTS'
                            : 'Read text',
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
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _textController,
            maxLines: 6,
            minLines: 4,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.m3Primary,
                  width: 1.5,
                ),
              ),
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              hintText: 'Edit text...',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColorScheme.text.primary
                        .withValues(alpha: 0.4),
                  ),
            ),
            onChanged: _onTextChanged,
          ),
        ],
      ),
    );
  }

  void _showHeightAdjustmentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _HeightAdjustmentDialog(
        currentHeight: _popupHeight,
        onHeightChanged: (newHeight) async {
          await widget.dictionaryService.setSentenceTranslationPopupHeight(
            newHeight,
          );
          if (mounted) {
            setState(() {
              _popupHeight = newHeight;
            });
          }
        },
        onOpenTabReorder: _openTabReorderDialog,
      ),
    );
  }
}

class _HeightAdjustmentDialog extends StatefulWidget {
  final int currentHeight;
  final Future<void> Function(int) onHeightChanged;
  final VoidCallback onOpenTabReorder;

  const _HeightAdjustmentDialog({
    required this.currentHeight,
    required this.onHeightChanged,
    required this.onOpenTabReorder,
  });

  @override
  State<_HeightAdjustmentDialog> createState() =>
      _HeightAdjustmentDialogState();
}

class _HeightAdjustmentDialogState extends State<_HeightAdjustmentDialog> {
  late double _height;

  @override
  void initState() {
    super.initState();
    _height = widget.currentHeight.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Popup Height: ${_height.round()} px',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          Slider(
            value: _height,
            min: DictionaryService.minPopupHeight.toDouble(),
            max: DictionaryService.maxPopupHeight.toDouble(),
            divisions:
                (DictionaryService.maxPopupHeight -
                    DictionaryService.minPopupHeight) ~/
                DictionaryService.popupHeightStep,
            label: '${_height.round()} px',
            onChanged: (value) {
              setState(() {
                _height = value;
              });
            },
            onChangeEnd: (value) {
              widget.onHeightChanged(value.round());
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sort),
            title: const Text('Reorder Tabs'),
            subtitle: const Text('Reorder dictionary & app tabs'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenTabReorder();
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
