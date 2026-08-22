import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sentence_tts_provider.dart';
import '../../../shared/theme/theme_extensions.dart';

class SentenceTTSButton extends ConsumerStatefulWidget {
  final String text;
  final int sentenceId;

  const SentenceTTSButton({
    super.key,
    required this.text,
    required this.sentenceId,
  });

  @override
  ConsumerState<SentenceTTSButton> createState() => _SentenceTTSButtonState();
}

class _SentenceTTSButtonState extends ConsumerState<SentenceTTSButton> {
  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(sentenceTTSProvider);
    final iconColor = context.appColorScheme.material3.primary;
    final errorColor = context.appColorScheme.error.error;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ttsState.hasError && ttsState.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ttsState.errorMessage!),
            backgroundColor: errorColor,
            action: SnackBarAction(
              label: 'Retry',
              textColor: context.appColorScheme.error.onError,
              onPressed: () {
                ref.read(sentenceTTSProvider.notifier).clearError();
                ref
                    .read(sentenceTTSProvider.notifier)
                    .speakSentence(widget.text, widget.sentenceId);
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });

    final isCurrentSentence = ttsState.currentText == widget.text;
    final isActive = isCurrentSentence &&
        (ttsState.isPlaying || ttsState.isPaused || ttsState.isLoading);

    if (isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pause / Resume / Loading Button
          if (ttsState.isLoading)
            IconButton(
              icon: const Icon(Icons.hourglass_empty),
              color: iconColor,
              onPressed: null,
              tooltip: 'Loading TTS',
            )
          else if (ttsState.isPlaying)
            IconButton(
              icon: const Icon(Icons.pause),
              color: iconColor,
              onPressed: () =>
                  ref.read(sentenceTTSProvider.notifier).pause(),
              tooltip: 'Pause TTS',
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow),
              color: iconColor,
              onPressed: () =>
                  ref.read(sentenceTTSProvider.notifier).resume(),
              tooltip: 'Resume TTS',
            ),
          // Stop Button
          IconButton(
            icon: const Icon(Icons.stop),
            color: errorColor,
            onPressed: () =>
                ref.read(sentenceTTSProvider.notifier).stop(),
            tooltip: 'Stop TTS',
          ),
        ],
      );
    }

    if (ttsState.hasError && isCurrentSentence) {
      return IconButton(
        icon: const Icon(Icons.refresh),
        color: errorColor,
        onPressed: () {
          ref.read(sentenceTTSProvider.notifier).clearError();
          ref
              .read(sentenceTTSProvider.notifier)
              .speakSentence(widget.text, widget.sentenceId);
        },
        tooltip: 'Retry TTS',
      );
    }

    return IconButton(
      icon: const Icon(Icons.volume_up),
      color: iconColor,
      onPressed: () => ref
          .read(sentenceTTSProvider.notifier)
          .speakSentence(widget.text, widget.sentenceId),
      tooltip: 'Play TTS',
    );
  }
}
