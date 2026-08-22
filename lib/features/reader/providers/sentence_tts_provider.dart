import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lute_for_mobile/core/network/tts_service.dart';
import 'package:lute_for_mobile/core/providers/tts_provider.dart';
import 'package:lute_for_mobile/features/settings/models/tts_settings.dart';
import 'package:lute_for_mobile/features/settings/providers/tts_settings_provider.dart';
import 'package:lute_for_mobile/shared/providers/language_data_provider.dart';
import '../providers/audio_player_provider.dart';

enum SentenceTTSStatus { idle, loading, playing, paused, error }

@immutable
class SentenceTTSState {
  final SentenceTTSStatus status;
  final String? errorMessage;
  final String? currentText;
  final int? currentSentenceId;
  final int retryCount;
  final bool isFallenBackToNone;
  final BytesSource? ttsAudioSource;

  const SentenceTTSState({
    this.status = SentenceTTSStatus.idle,
    this.errorMessage,
    this.currentText,
    this.currentSentenceId,
    this.retryCount = 0,
    this.isFallenBackToNone = false,
    this.ttsAudioSource,
  });

  bool get isPlaying => status == SentenceTTSStatus.playing;
  bool get isPaused => status == SentenceTTSStatus.paused;
  bool get isLoading => status == SentenceTTSStatus.loading;
  bool get hasError => status == SentenceTTSStatus.error;

  SentenceTTSState copyWith({
    SentenceTTSStatus? status,
    String? errorMessage,
    String? currentText,
    int? currentSentenceId,
    int? retryCount,
    bool? isFallenBackToNone,
    BytesSource? ttsAudioSource,
  }) {
    return SentenceTTSState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      currentText: currentText ?? this.currentText,
      currentSentenceId: currentSentenceId ?? this.currentSentenceId,
      retryCount: retryCount ?? this.retryCount,
      isFallenBackToNone: isFallenBackToNone ?? this.isFallenBackToNone,
      ttsAudioSource: ttsAudioSource ?? this.ttsAudioSource,
    );
  }
}

class SentenceTTSNotifier extends Notifier<SentenceTTSState> {
  static const int maxRetries = 3;

  @override
  SentenceTTSState build() {
    ref.onDispose(() {
      _playerStateSubscription?.cancel();
      _completeSubscription?.cancel();
      _ttsServiceStateSubscription?.cancel();
      _activeTTSService?.dispose();
    });
    return const SentenceTTSState();
  }

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _completeSubscription;
  StreamSubscription<PlayerState>? _ttsServiceStateSubscription;
  TTSService? _activeTTSService;

  void _setupPlayerStateListener() {
    final audioPlayer = ref
        .read(audioPlayerProvider.notifier)
        .state
        .audioPlayer;
    _playerStateSubscription?.cancel();
    _completeSubscription?.cancel();

    _playerStateSubscription = audioPlayer.onPlayerStateChanged.listen((
      playerState,
    ) {
      debugPrint('TTS Player state changed: $playerState');
      if (playerState == PlayerState.completed) {
        debugPrint('TTS audio completed, resetting state');
        state = const SentenceTTSState();
      }
    });

    _completeSubscription = audioPlayer.onPlayerComplete.listen((_) {
      debugPrint('TTS onPlayerComplete triggered');
      state = const SentenceTTSState();
    });
  }

  void _setupTTSServiceListener(TTSService ttsService) {
    _ttsServiceStateSubscription?.cancel();

    _ttsServiceStateSubscription = ttsService.playerStateStream.listen((
      playerState,
    ) {
      debugPrint('TTS Service state changed: $playerState');
      if (playerState == PlayerState.completed ||
          playerState == PlayerState.stopped) {
        debugPrint('TTS service finished, resetting state');
        state = const SentenceTTSState();
      } else if (playerState == PlayerState.paused) {
        state = state.copyWith(status: SentenceTTSStatus.paused);
      } else if (playerState == PlayerState.playing) {
        state = state.copyWith(status: SentenceTTSStatus.playing);
      }
    });
  }

  String _getUserFriendlyErrorMessage(String error) {
    if (error.contains('connection') || error.contains('connect')) {
      return 'Could not connect to TTS service. Please check your settings or network connection.';
    }
    if (error.contains('auth') ||
        error.contains('key') ||
        error.contains('401')) {
      return 'Invalid API key. Please check your TTS settings.';
    }
    if (error.contains('voice') || error.contains('No voices selected')) {
      return 'Please select a voice in TTS settings.';
    }
    if (error.contains('rate') || error.contains('quota')) {
      return 'TTS service quota exceeded. Please try again later.';
    }
    return 'TTS failed: $error';
  }

  String? _mapLanguageToLocale(String lang) {
    final lower = lang.toLowerCase().trim();
    if (lower.isEmpty) return null;
    if (lower.contains('english') || lower == 'en') return 'en-US';
    if (lower.contains('chinese') ||
        lower.contains('mandarin') ||
        lower.contains('中文') ||
        lower.contains('汉语') ||
        lower == 'zh') {
      return 'zh-CN';
    }
    if (lower.contains('japanese') ||
        lower.contains('日本語') ||
        lower == 'ja' ||
        lower == 'jp') {
      return 'ja-JP';
    }
    if (lower.contains('spanish') ||
        lower.contains('español') ||
        lower == 'es') {
      return 'es-ES';
    }
    if (lower.contains('french') ||
        lower.contains('français') ||
        lower == 'fr') {
      return 'fr-FR';
    }
    if (lower.contains('german') ||
        lower.contains('deutsch') ||
        lower == 'de') {
      return 'de-DE';
    }
    if (lower.contains('korean') ||
        lower.contains('한국어') ||
        lower == 'ko') {
      return 'ko-KR';
    }
    if (lower.contains('russian') ||
        lower.contains('русский') ||
        lower == 'ru') {
      return 'ru-RU';
    }
    if (lower.contains('italian') ||
        lower.contains('italiano') ||
        lower == 'it') {
      return 'it-IT';
    }
    if (lower.contains('portuguese') ||
        lower.contains('português') ||
        lower == 'pt') {
      return 'pt-PT';
    }
    if (lower.contains('arabic') || lower == 'ar') return 'ar-SA';
    if (lower.contains('turkish') || lower == 'tr') return 'tr-TR';
    if (lower.contains('dutch') || lower == 'nl') return 'nl-NL';
    if (lower.contains('polish') || lower == 'pl') return 'pl-PL';
    if (lower.contains('swedish') || lower == 'sv') return 'sv-SE';
    if (lower.contains('vietnamese') || lower == 'vi') return 'vi-VN';
    if (lower.contains('thai') || lower == 'th') return 'th-TH';
    if (lower.contains('greek') || lower == 'el') return 'el-GR';
    if (lower.contains('hindi') || lower == 'hi') return 'hi-IN';
    if (lower.contains('latin') || lower == 'la') return 'la';
    if (lower.length == 2 || lower.contains('-')) return lang;
    return null;
  }

  Future<void> _applyLanguage(
    TTSService ttsService, {
    int? languageId,
    String? languageCode,
  }) async {
    try {
      if (languageCode != null && languageCode.isNotEmpty) {
        final locale = _mapLanguageToLocale(languageCode);
        if (locale != null) {
          await ttsService.setLanguage(locale);
        }
      } else if (languageId != null && languageId > 0) {
        final languages = ref.read(languageListProvider).value;
        final matched =
            languages?.where((l) => l.id == languageId).firstOrNull;
        if (matched != null) {
          final locale = _mapLanguageToLocale(matched.name);
          if (locale != null) {
            await ttsService.setLanguage(locale);
          }
        }
      }
    } catch (e) {
      debugPrint('Error applying language to TTS service: $e');
    }
  }

  Future<void> speakSentence(
    String text,
    int sentenceId, {
    int? languageId,
    String? languageCode,
  }) async {
    if (text.trim().isEmpty) return;

    await stop();

    final settings = ref.read(ttsSettingsProvider);
    var ttsService = ref.read(ttsServiceProvider);

    // Fall back to OnDevice system TTS if disabled or none
    if (ttsService is NoTTSService) {
      final onDevice = OnDeviceTTSService();
      final config = settings.providerConfigs[TTSProvider.onDevice];
      if (config != null) {
        await onDevice.setSettings(config);
      }
      ttsService = onDevice;
    }
    _activeTTSService = ttsService;

    try {
      state = state.copyWith(
        status: SentenceTTSStatus.loading,
        currentText: text,
        currentSentenceId: sentenceId,
        errorMessage: null,
        retryCount: 0,
        isFallenBackToNone: false,
        ttsAudioSource: null,
      );

      await _applyLanguage(
        ttsService,
        languageId: languageId,
        languageCode: languageCode,
      );

      if (ttsService.supportsBytesOutput) {
        debugPrint('Fetching TTS audio bytes...');
        final audioBytes = await ttsService.getAudioBytes(text);
        debugPrint('Got ${audioBytes.length} bytes of audio');

        final bytesSource = BytesSource(audioBytes);

        state = state.copyWith(
          status: SentenceTTSStatus.playing,
          ttsAudioSource: bytesSource,
        );

        final audioPlayer = ref.read(audioPlayerProvider.notifier);
        _setupPlayerStateListener();

        debugPrint('Starting TTS playback...');
        await audioPlayer.playTTSAudio(bytesSource);
        debugPrint('TTS playback started');
      } else {
        debugPrint('Using direct speak for on-device system TTS...');
        _setupTTSServiceListener(ttsService);
        // Ensure the TTS engine is warmed up before speaking to avoid
        // native crashes (e.g. on Oplus devices) from lazy TextToSpeech init.
        await OnDeviceTTSService.warmUp();
        await ttsService.speak(text);
        state = state.copyWith(status: SentenceTTSStatus.playing);
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
      await _handleError(
        text,
        sentenceId,
        e,
        languageId: languageId,
        languageCode: languageCode,
      );
    }
  }

  Future<void> _handleError(
    String text,
    int sentenceId,
    dynamic error, {
    int? languageId,
    String? languageCode,
  }) async {
    final currentRetries = state.retryCount;

    if (currentRetries < maxRetries) {
      debugPrint('Retrying TTS (${currentRetries + 1}/$maxRetries)');
      state = state.copyWith(retryCount: currentRetries + 1);

      await Future.delayed(const Duration(seconds: 1));

      try {
        final TTSService ttsService =
            _activeTTSService ?? ref.read(ttsServiceProvider);
        final audioPlayer = ref.read(audioPlayerProvider.notifier);

        await _applyLanguage(
          ttsService,
          languageId: languageId,
          languageCode: languageCode,
        );

        if (ttsService.supportsBytesOutput) {
          final audioBytes = await ttsService.getAudioBytes(text);
          final bytesSource = BytesSource(audioBytes);

          state = state.copyWith(
            status: SentenceTTSStatus.playing,
            ttsAudioSource: bytesSource,
          );

          await audioPlayer.playTTSAudio(bytesSource);
        } else {
          debugPrint('Using direct speak for on-device system TTS on retry...');
          _setupTTSServiceListener(ttsService);
          await OnDeviceTTSService.warmUp();
          await ttsService.speak(text);
          state = state.copyWith(status: SentenceTTSStatus.playing);
        }
      } catch (retryError) {
        await _handleError(
          text,
          sentenceId,
          retryError,
          languageId: languageId,
          languageCode: languageCode,
        );
      }
    } else {
      final userFriendlyError =
          _getUserFriendlyErrorMessage(error.toString());
      state = state.copyWith(
        status: SentenceTTSStatus.error,
        errorMessage: userFriendlyError,
        retryCount: 0,
      );
    }
  }

  Future<void> pause() async {
    final TTSService ttsService =
        _activeTTSService ?? ref.read(ttsServiceProvider);
    final audioPlayer = ref.read(audioPlayerProvider.notifier);

    try {
      debugPrint('Pausing TTS...');
      if (ttsService.supportsBytesOutput) {
        await audioPlayer.pause();
      } else {
        await ttsService.pause();
      }
      state = state.copyWith(status: SentenceTTSStatus.paused);
    } catch (e) {
      debugPrint('Failed to pause TTS: $e');
    }
  }

  Future<void> resume() async {
    final TTSService ttsService =
        _activeTTSService ?? ref.read(ttsServiceProvider);
    final audioPlayer = ref.read(audioPlayerProvider.notifier);

    try {
      debugPrint('Resuming TTS...');
      if (ttsService.supportsBytesOutput) {
        await audioPlayer.play();
      } else {
        await ttsService.resume();
      }
      state = state.copyWith(status: SentenceTTSStatus.playing);
    } catch (e) {
      debugPrint('Failed to resume TTS: $e');
    }
  }

  Future<void> stop() async {
    final TTSService ttsService =
        _activeTTSService ?? ref.read(ttsServiceProvider);
    final audioPlayer = ref.read(audioPlayerProvider.notifier);

    try {
      debugPrint('Stopping TTS...');
      if (ttsService.supportsBytesOutput) {
        await audioPlayer.stop();
      } else {
        await ttsService.stop();
      }
      _ttsServiceStateSubscription?.cancel();
      state = const SentenceTTSState();
    } catch (e) {
      debugPrint('Failed to stop TTS: $e');
    }
  }

  Future<void> toggle(
    String text,
    int sentenceId, {
    int? languageId,
    String? languageCode,
  }) async {
    if (state.isPlaying) {
      await pause();
    } else if (state.isPaused) {
      await resume();
    } else {
      await speakSentence(
        text,
        sentenceId,
        languageId: languageId,
        languageCode: languageCode,
      );
    }
  }

  void clearError() {
    state = state.copyWith(
      status: SentenceTTSStatus.idle,
      errorMessage: null,
      isFallenBackToNone: false,
    );
  }
}

final sentenceTTSProvider =
    NotifierProvider<SentenceTTSNotifier, SentenceTTSState>(() {
  return SentenceTTSNotifier();
});
