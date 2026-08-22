import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lute_for_mobile/features/settings/models/tts_settings.dart';

class TTSVoice {
  final String name;
  final String locale;
  final String? quality;
  final bool isNetworkConnectionRequired;

  TTSVoice({
    required this.name,
    required this.locale,
    this.quality,
    this.isNetworkConnectionRequired = false,
  });

  String get displayName {
    String displayName = name;

    displayName = displayName.replaceFirst(
      RegExp(r'^([a-z]{2}-[a-z]{2})-'),
      '',
    );
    displayName = displayName.replaceFirst(
      RegExp(r'^com\.google\.android\.tts\.'),
      '',
    );
    displayName = displayName.replaceFirst(
      RegExp(r'^com\.apple\.ttsbundle\.'),
      '',
    );
    displayName = displayName.replaceFirst(RegExp(r'^com\.samsung\.smt\.'), '');
    displayName = displayName.replaceAll('#', ' ');
    displayName = displayName.replaceAll('_', ' ');

    if (displayName.isEmpty) {
      displayName = name;
    }

    final parts = displayName.split(' ');
    final formattedName = parts
        .map(
          (part) => part.isEmpty
              ? ''
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');

    final localeDisplay = locale.isNotEmpty ? ' [$locale]' : '';
    final qualitySuffix = quality != null && quality != 'normal'
        ? ' ($quality)'
        : '';
    final networkSuffix = isNetworkConnectionRequired ? ' (Online)' : '';

    return '$formattedName$localeDisplay$qualitySuffix$networkSuffix';
  }

  factory TTSVoice.fromMap(Map<dynamic, dynamic> map) {
    return TTSVoice(
      name: map['name']?.toString() ?? '',
      locale: map['locale']?.toString() ?? '',
      quality: map['quality']?.toString(),
      isNetworkConnectionRequired: map['isNetworkConnectionRequired'] == true,
    );
  }
}

abstract class TTSService {
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setLanguage(String languageCode);
  Future<void> setSettings(TTSSettingsConfig config);
  Future<List<TTSVoice>> getAvailableVoices();
  void dispose();
  Stream<PlayerState> get playerStateStream;
  Future<Uint8List> getAudioBytes(String text);
  bool get supportsBytesOutput;
}

class OnDeviceTTSService implements TTSService {
  static final FlutterTts _sharedFlutterTts = FlutterTts();
  static bool _handlersConfigured = false;
  static Completer<void>? _chunkCompleter;
  static int _currentPlaybackId = 0;
  static final StreamController<PlayerState> _sharedPlayerStateController =
      StreamController<PlayerState>.broadcast();

  static bool _isStopped = false;
  static bool _isWarmedUp = false;
  AudioPlayer? _audioPlayer;

  OnDeviceTTSService() {
    _ensureInitialized();
  }

  /// Pre-warm the system TTS engine so the TextToSpeech object is created
  /// on the main thread before any speak() call. This prevents a native
  /// crash on OnePlus/Oplus devices where lazy creation inside speak()
  /// triggers on the wrong thread.
  static Future<void> warmUp() async {
    if (_isWarmedUp) return;
    _ensureInitialized();
    try {
      await _sharedFlutterTts.getLanguages.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      _isWarmedUp = true;
      debugPrint('OnDeviceTTS warmed up successfully');
    } catch (e) {
      debugPrint('OnDeviceTTS warm-up failed (non-fatal): $e');
    }
  }

  static void _ensureInitialized() {
    if (_handlersConfigured) return;
    _handlersConfigured = true;

    _sharedFlutterTts.setStartHandler(() {
      debugPrint('FlutterTts started speaking chunk');
    });

    _sharedFlutterTts.setProgressHandler((
      String text,
      int start,
      int end,
      String word,
    ) {
      _lastSpokenOffsetInChunk = start;
    });

    _sharedFlutterTts.setCompletionHandler(() {
      debugPrint('FlutterTts chunk completed');
      _lastSpokenOffsetInChunk = 0;
      if (_chunkCompleter != null && !_chunkCompleter!.isCompleted) {
        _chunkCompleter!.complete();
      }
    });

    _sharedFlutterTts.setCancelHandler(() {
      debugPrint('FlutterTts cancelled');
      if (_chunkCompleter != null && !_chunkCompleter!.isCompleted) {
        _chunkCompleter!.complete();
      }
    });

    _sharedFlutterTts.setErrorHandler((msg) {
      debugPrint('FlutterTts error: $msg');
      if (_chunkCompleter != null && !_chunkCompleter!.isCompleted) {
        _chunkCompleter!.complete();
      }
    });
  }

  @override
  Stream<PlayerState> get playerStateStream =>
      _sharedPlayerStateController.stream;

  static bool _isPaused = false;
  static Completer<void>? _pauseCompleter;
  static int _lastSpokenOffsetInChunk = 0;
  static int _pausedOffset = 0;
  static final Stopwatch _chunkStopwatch = Stopwatch();
  static String _currentChunkText = '';
  static double _currentRate = 0.5;

  static double _estimateCharsPerSecond(String text) {
    final cjkCount =
        RegExp(r'[\u4e00-\u9fa5\u3040-\u30ff\uac00-\ud7af]').allMatches(text).length;
    final isCJK = cjkCount > text.length * 0.3;
    final rateFactor = _currentRate / 0.5;
    if (isCJK) {
      return 5.0 * rateFactor;
    } else {
      return 15.0 * rateFactor;
    }
  }

  static int _calculateCurrentOffset() {
    if (_lastSpokenOffsetInChunk > 0) {
      return _lastSpokenOffsetInChunk;
    }

    if (_chunkStopwatch.isRunning && _currentChunkText.isNotEmpty) {
      final elapsedSeconds = _chunkStopwatch.elapsedMilliseconds / 1000.0;
      final charsPerSec = _estimateCharsPerSecond(_currentChunkText);
      final estimated = (elapsedSeconds * charsPerSec).round();
      return estimated.clamp(0, _currentChunkText.length);
    }

    return 0;
  }

  @override
  Future<void> speak(String text) async {
    final int playbackId = ++_currentPlaybackId;
    _isStopped = false;
    _isPaused = false;
    _pauseCompleter = null;
    _lastSpokenOffsetInChunk = 0;
    _pausedOffset = 0;
    _chunkStopwatch.reset();
    _ensureInitialized();

    try {
      try {
        await _sharedFlutterTts.stop();
      } catch (_) {}

      final chunks = _splitTextIntoChunks(text);

      if (chunks.isEmpty) {
        _sharedPlayerStateController.add(PlayerState.completed);
        return;
      }

      _sharedPlayerStateController.add(PlayerState.playing);

      for (int i = 0; i < chunks.length; i++) {
        if (_isStopped || _currentPlaybackId != playbackId) {
          debugPrint('TTS speak aborted for playback #$playbackId');
          return;
        }

        String chunk = chunks[i];
        if (chunk.trim().isEmpty) continue;

        while (chunk.trim().isNotEmpty) {
          if (_isStopped || _currentPlaybackId != playbackId) return;

          // If paused, wait here before speaking
          if (_isPaused && _pauseCompleter != null) {
            await _pauseCompleter!.future;
            if (_isStopped || _currentPlaybackId != playbackId) return;
          }

          _lastSpokenOffsetInChunk = 0;
          _currentChunkText = chunk;
          _chunkStopwatch.reset();
          _chunkStopwatch.start();

          _chunkCompleter = Completer<void>();
          await _sharedFlutterTts.speak(chunk);

          // Calculate dynamic safety timeout based on chunk length
          final safetyTimeoutSeconds = (chunk.length ~/ 10) + 8;
          try {
            await _chunkCompleter!.future.timeout(
              Duration(seconds: safetyTimeoutSeconds),
              onTimeout: () {
                debugPrint(
                  'FlutterTts chunk $i/${chunks.length} reached safety timeout, advancing',
                );
              },
            );
          } catch (_) {}

          _chunkStopwatch.stop();

          // If paused during this chunk's speech, calculate the remaining text to speak upon resume
          if (_isPaused) {
            int resumeOffset = _pausedOffset > 0 ? _pausedOffset : _calculateCurrentOffset();
            debugPrint('TTS paused at offset $resumeOffset in chunk of length ${chunk.length} (lastSpoken: $_lastSpokenOffsetInChunk, stopwatch: ${_chunkStopwatch.elapsedMilliseconds}ms)');

            if (resumeOffset >= chunk.length) {
              chunk = '';
            } else if (resumeOffset > 0) {
              int rewindStart = resumeOffset;
              int minOffset = (resumeOffset - 6).clamp(0, chunk.length);
              while (rewindStart > minOffset && chunk[rewindStart] != ' ') {
                rewindStart--;
              }
              if (chunk[rewindStart] == ' ') {
                rewindStart++;
              } else {
                rewindStart = (resumeOffset - 1).clamp(0, chunk.length);
              }
              chunk = chunk.substring(rewindStart).trim();
            }
            _pausedOffset = 0;
            _chunkStopwatch.reset();

            // Wait for unpause
            if (_pauseCompleter != null) {
              await _pauseCompleter!.future;
              if (_isStopped || _currentPlaybackId != playbackId) return;
            }
            // Loop continues and speaks the remaining `chunk`
          } else {
            // Chunk fully finished without being paused mid-way
            break;
          }
        }

        // Small inter-chunk pause for natural breathing rhythm
        if (i < chunks.length - 1 && !_isStopped && _currentPlaybackId == playbackId) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      if (!_isStopped && _currentPlaybackId == playbackId) {
        _sharedPlayerStateController.add(PlayerState.completed);
      }
    } catch (e) {
      if (_currentPlaybackId == playbackId) {
        _sharedPlayerStateController.add(PlayerState.stopped);
      }
      if (e is TTSException) rethrow;
      throw TTSException('Failed to speak with on-device TTS: $e');
    }
  }

  List<String> _splitTextIntoChunks(String text, {int maxChunkLength = 150}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];
    if (trimmed.length <= maxChunkLength) return [trimmed];

    final chunks = <String>[];
    // Split by sentence terminators first: . ! ? ; \n and Chinese/Japanese equivalents 。！？；
    final sentencePattern = RegExp(r'[^.!?;\n。！？；…]+[.!?;\n。！？；…]*|\S+');
    final matches = sentencePattern.allMatches(trimmed);

    StringBuffer currentChunk = StringBuffer();

    for (final match in matches) {
      final segment = match.group(0) ?? '';
      if (segment.trim().isEmpty) continue;

      if (currentChunk.length + segment.length > maxChunkLength &&
          currentChunk.isNotEmpty) {
        chunks.add(currentChunk.toString().trim());
        currentChunk.clear();
      }

      // If a single segment is longer than maxChunkLength (e.g. long sentence without punctuation),
      // sub-split by comma, colon, dash, or whitespace
      if (segment.length > maxChunkLength) {
        final subPattern = RegExp(r'[^,:\-，：、\s]+[,:\-，：、\s]*|\S+');
        final subMatches = subPattern.allMatches(segment);
        for (final subMatch in subMatches) {
          final subSegment = subMatch.group(0) ?? '';
          if (subSegment.trim().isEmpty) continue;
          if (currentChunk.length + subSegment.length > maxChunkLength &&
              currentChunk.isNotEmpty) {
            chunks.add(currentChunk.toString().trim());
            currentChunk.clear();
          }
          currentChunk.write(subSegment);
        }
      } else {
        currentChunk.write(segment);
      }

      if (!segment.endsWith(' ') && !segment.endsWith('\n')) {
        currentChunk.write(' ');
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
    }

    // Fallback if regex produced nothing
    if (chunks.isEmpty) {
      for (int i = 0; i < trimmed.length; i += maxChunkLength) {
        int end = (i + maxChunkLength < trimmed.length)
            ? i + maxChunkLength
            : trimmed.length;
        chunks.add(trimmed.substring(i, end).trim());
      }
    }

    return chunks.where((c) => c.isNotEmpty).toList();
  }

  @override
  Future<void> pause() async {
    try {
      _isPaused = true;
      _chunkStopwatch.stop();
      _pausedOffset = _calculateCurrentOffset();
      _pauseCompleter = Completer<void>();
      // Stop current utterance on engine so sound stops immediately
      await _sharedFlutterTts.stop();
      if (_chunkCompleter != null && !_chunkCompleter!.isCompleted) {
        _chunkCompleter!.complete();
      }
      _sharedPlayerStateController.add(PlayerState.paused);
    } catch (e) {
      debugPrint('Failed to pause on-device TTS: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      _isPaused = false;
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
      _pauseCompleter = null;
      _sharedPlayerStateController.add(PlayerState.playing);
    } catch (e) {
      debugPrint('Failed to resume on-device TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      _isStopped = true;
      _isPaused = false;
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
      _pauseCompleter = null;
      if (_chunkCompleter != null && !_chunkCompleter!.isCompleted) {
        _chunkCompleter!.complete();
      }
      await _sharedFlutterTts.stop();
      _sharedPlayerStateController.add(PlayerState.stopped);
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
        await _audioPlayer!.release();
      }
    } catch (e) {
      throw TTSException('Failed to stop on-device TTS: $e');
    }
  }

  @override
  Future<void> setLanguage(String languageCode) async {
    try {
      _ensureInitialized();
      await _sharedFlutterTts.setLanguage(languageCode);
    } catch (e) {
      throw TTSException('Failed to set language: $e');
    }
  }

  @override
  Future<void> setSettings(TTSSettingsConfig config) async {
    try {
      _ensureInitialized();
      String? voiceName = config.voice;
      String? voiceLocale = config.voiceLocale;

      debugPrint(
        'Applying on-device TTS settings: voice=$voiceName, locale=$voiceLocale, rate=${config.rate}, pitch=${config.pitch}, volume=${config.volume}',
      );

      if (voiceLocale != null && voiceLocale.isNotEmpty) {
        await _sharedFlutterTts.setLanguage(voiceLocale);
      }

      if (voiceName != null && voiceName.isNotEmpty) {
        if (voiceLocale != null && voiceLocale.isNotEmpty) {
          await _sharedFlutterTts.setVoice({
            'name': voiceName,
            'locale': voiceLocale,
          });
        } else {
          await _sharedFlutterTts.setVoice({'name': voiceName});
        }
      }
      if (config.rate != null) {
        _currentRate = config.rate!;
        await _sharedFlutterTts.setSpeechRate(config.rate!);
      }
      if (config.pitch != null) {
        await _sharedFlutterTts.setPitch(config.pitch!);
      }
      if (config.volume != null) {
        await _sharedFlutterTts.setVolume(config.volume!);
      }
    } catch (e) {
      throw TTSException('Failed to set on-device TTS settings: $e');
    }
  }

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    try {
      _ensureInitialized();
      final voices = await _sharedFlutterTts.getVoices;
      final result = <TTSVoice>[];
      for (final v in voices) {
        try {
          final voice = TTSVoice.fromMap(v);
          if (voice.name.isNotEmpty) {
            result.add(voice);
          }
        } catch (_) {}
      }
      return result;
    } catch (e) {
      throw TTSException('Failed to get on-device voices: $e');
    }
  }

  @override
  void dispose() {
    // Shared singleton lifecycle
  }

  @override
  Future<Uint8List> getAudioBytes(String text) async {
    throw TTSException('On-device TTS does not support audio bytes output');
  }

  @override
  bool get supportsBytesOutput => false;
}

class KokoroTTSService implements TTSService {
  final String endpointUrl;
  final List<KokoroVoiceWeight> voices;
  final String audioFormat;
  final double speed;

  final Dio _dio = Dio();
  late final AudioPlayer _audioPlayer;
  final _playerStateController = StreamController<PlayerState>.broadcast();

  KokoroTTSService({
    required this.endpointUrl,
    required this.voices,
    this.audioFormat = 'mp3',
    this.speed = 1.0,
  }) {
    _audioPlayer = AudioPlayer()
      ..setReleaseMode(ReleaseMode.stop)
      ..onPlayerStateChanged.listen((state) {
        _playerStateController.add(state);
      });
  }

  String _generateVoiceString() {
    if (voices.isEmpty) return '';
    if (voices.length == 1) {
      return voices.first.voice;
    }
    return voices.map((v) => '${v.voice}(${v.weight})').join('+');
  }

  @override
  Future<void> speak(String text) async {
    try {
      final voiceString = _generateVoiceString();
      if (voiceString.isEmpty) {
        throw TTSException('No voices selected for Kokoro TTS');
      }

      final response = await _dio.post(
        '$endpointUrl/audio/speech',
        data: {
          'model': 'kokoro',
          'input': text,
          'voice': voiceString,
          'response_format': audioFormat,
          'speed': speed,
        },
        options: Options(responseType: ResponseType.bytes),
      );

      final audioBytes = response.data as List<int>;
      await _audioPlayer.play(BytesSource(Uint8List.fromList(audioBytes)));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) {
        throw TTSException(
          'Failed to connect to Kokoro server at $endpointUrl',
        );
      }
      throw TTSException('Kokoro TTS request failed: ${e.message}');
    } catch (e) {
      throw TTSException('Failed to speak with Kokoro TTS: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      throw TTSException('Failed to pause Kokoro TTS: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      throw TTSException('Failed to resume Kokoro TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.release();
    } catch (e) {
      throw TTSException('Failed to stop Kokoro TTS: $e');
    }
  }

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<void> setSettings(TTSSettingsConfig config) async {}

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    try {
      final response = await _dio.get('$endpointUrl/audio/voices');
      final data = response.data;
      if (data is Map && data.containsKey('voices')) {
        return (data['voices'] as List)
            .map((v) => TTSVoice(name: v.toString(), locale: ''))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) {
        throw TTSException(
          'Failed to connect to Kokoro server at $endpointUrl',
        );
      }
      throw TTSException('Failed to fetch available voices: ${e.message}');
    } catch (e) {
      throw TTSException('Failed to get available voices: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _playerStateController.close();
  }

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Future<Uint8List> getAudioBytes(String text) async {
    final voiceString = _generateVoiceString();
    if (voiceString.isEmpty) {
      throw TTSException('No voices selected for Kokoro TTS');
    }

    final response = await _dio.post(
      '$endpointUrl/audio/speech',
      data: {
        'model': 'kokoro',
        'input': text,
        'voice': voiceString,
        'response_format': audioFormat,
        'speed': speed,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final audioBytes = response.data as List<int>;
    return Uint8List.fromList(audioBytes);
  }

  @override
  bool get supportsBytesOutput => true;
}

class OpenAITTSService implements TTSService {
  final String apiKey;
  final String? model;
  final String? voice;

  final Dio _dio = Dio();
  late final AudioPlayer _audioPlayer;
  final _playerStateController = StreamController<PlayerState>.broadcast();

  OpenAITTSService({required this.apiKey, this.model, this.voice}) {
    _audioPlayer = AudioPlayer()
      ..setReleaseMode(ReleaseMode.stop)
      ..onPlayerStateChanged.listen((state) {
        _playerStateController.add(state);
      });
  }

  @override
  Future<void> speak(String text) async {
    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/audio/speech',
        data: {
          'model': model ?? 'tts-1',
          'input': text,
          'voice': voice ?? 'alloy',
          'response_format': 'mp3',
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final audioBytes = response.data as List<int>;
      await _audioPlayer.play(BytesSource(Uint8List.fromList(audioBytes)));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw TTSException('Invalid OpenAI API key');
      }
      if (e.type == DioExceptionType.connectionError) {
        throw TTSException('Failed to connect to OpenAI API');
      }
      throw TTSException('OpenAI TTS request failed: ${e.message}');
    } catch (e) {
      throw TTSException('Failed to speak with OpenAI TTS: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      throw TTSException('Failed to pause OpenAI TTS: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      throw TTSException('Failed to resume OpenAI TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.release();
    } catch (e) {
      throw TTSException('Failed to stop OpenAI TTS: $e');
    }
  }

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<void> setSettings(TTSSettingsConfig config) async {}

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    return [
      'alloy',
      'echo',
      'fable',
      'onyx',
      'nova',
      'shimmer',
    ].map((v) => TTSVoice(name: v, locale: 'en-US')).toList();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _playerStateController.close();
  }

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Future<Uint8List> getAudioBytes(String text) async {
    final response = await _dio.post(
      'https://api.openai.com/v1/audio/speech',
      data: {
        'model': model ?? 'tts-1',
        'input': text,
        'voice': voice ?? 'alloy',
        'response_format': 'mp3',
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final audioBytes = response.data as List<int>;
    return Uint8List.fromList(audioBytes);
  }

  @override
  bool get supportsBytesOutput => true;
}

class LocalOpenAITTSService implements TTSService {
  final String endpointUrl;
  final String? model;
  final String? voice;
  final String? apiKey;

  final Dio _dio = Dio();
  late final AudioPlayer _audioPlayer;
  final _playerStateController = StreamController<PlayerState>.broadcast();

  LocalOpenAITTSService({
    required this.endpointUrl,
    this.model,
    this.voice,
    this.apiKey,
  }) {
    _audioPlayer = AudioPlayer()
      ..setReleaseMode(ReleaseMode.stop)
      ..onPlayerStateChanged.listen((state) {
        _playerStateController.add(state);
      });
  }

  @override
  Future<void> speak(String text) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};

      if (apiKey != null && apiKey!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final response = await _dio.post(
        '$endpointUrl/audio/speech',
        data: {
          'model': model ?? 'tts-1',
          'input': text,
          'voice': voice ?? 'alloy',
          'response_format': 'mp3',
        },
        options: Options(responseType: ResponseType.bytes, headers: headers),
      );

      final audioBytes = response.data as List<int>;
      await _audioPlayer.play(BytesSource(Uint8List.fromList(audioBytes)));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) {
        throw TTSException(
          'Failed to connect to local endpoint at $endpointUrl',
        );
      }
      if (e.response?.statusCode == 401) {
        throw TTSException('Invalid API key for local endpoint');
      }
      throw TTSException('Local OpenAI TTS request failed: ${e.message}');
    } catch (e) {
      throw TTSException('Failed to speak with local OpenAI TTS: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      throw TTSException('Failed to pause local OpenAI TTS: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      throw TTSException('Failed to resume local OpenAI TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.release();
    } catch (e) {
      throw TTSException('Failed to stop local OpenAI TTS: $e');
    }
  }

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<void> setSettings(TTSSettingsConfig config) async {}

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    return [
      'alloy',
      'echo',
      'fable',
      'onyx',
      'nova',
      'shimmer',
    ].map((v) => TTSVoice(name: v, locale: 'en-US')).toList();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _playerStateController.close();
  }

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Future<Uint8List> getAudioBytes(String text) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final response = await _dio.post(
      '$endpointUrl/audio/speech',
      data: {
        'model': model ?? 'tts-1',
        'input': text,
        'voice': voice ?? 'alloy',
        'response_format': 'mp3',
      },
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );

    final audioBytes = response.data as List<int>;
    return Uint8List.fromList(audioBytes);
  }

  @override
  bool get supportsBytesOutput => true;
}

class SupertonicFastApiTTSService implements TTSService {
  final String endpointUrl;
  final String voice;
  final String languageCode;
  final int totalSteps;
  final double speed;

  final Dio _dio = Dio();
  late final AudioPlayer _audioPlayer;
  final _playerStateController = StreamController<PlayerState>.broadcast();

  SupertonicFastApiTTSService({
    required this.endpointUrl,
    required this.voice,
    required this.languageCode,
    required this.totalSteps,
    required this.speed,
  }) {
    _audioPlayer = AudioPlayer()
      ..setReleaseMode(ReleaseMode.stop)
      ..onPlayerStateChanged.listen((state) {
        _playerStateController.add(state);
      });
  }

  String get _synthesizeUrl => '$endpointUrl/synthesize';

  @override
  Future<void> speak(String text) async {
    try {
      final audioBytes = await getAudioBytes(text);
      await _audioPlayer.play(BytesSource(audioBytes));
    } catch (e) {
      if (e is TTSException) {
        rethrow;
      }
      throw TTSException('Failed to speak with Supertonic FastAPI TTS: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      throw TTSException('Failed to pause Supertonic FastAPI TTS: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      throw TTSException('Failed to resume Supertonic FastAPI TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.release();
    } catch (e) {
      throw TTSException('Failed to stop Supertonic FastAPI TTS: $e');
    }
  }

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<void> setSettings(TTSSettingsConfig config) async {}

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    try {
      final response = await _dio.get('$endpointUrl/voices');
      final data = response.data;

      if (data is Map && data['voices'] is List) {
        return (data['voices'] as List)
            .map((v) => TTSVoice(name: v.toString(), locale: languageCode))
            .toList();
      }

      return [];
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) {
        throw TTSException(
          'Failed to connect to Supertonic FastAPI at $endpointUrl',
        );
      }
      throw TTSException(
        'Failed to fetch Supertonic FastAPI voices: ${e.message}',
      );
    } catch (e) {
      throw TTSException('Failed to load Supertonic FastAPI voices: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _playerStateController.close();
  }

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Future<Uint8List> getAudioBytes(String text) async {
    try {
      final response = await _dio.post(
        _synthesizeUrl,
        data: {
          'text': text,
          'voice': voice,
          'lang': languageCode,
          'total_steps': totalSteps,
          'speed': speed,
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Content-Type': 'application/json'},
        ),
      );

      final audioBytes = response.data as List<int>;
      return Uint8List.fromList(audioBytes);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) {
        throw TTSException(
          'Failed to connect to Supertonic FastAPI at $endpointUrl',
        );
      }
      throw TTSException('Supertonic FastAPI TTS request failed: ${e.message}');
    } catch (e) {
      throw TTSException(
        'Failed to fetch audio from Supertonic FastAPI TTS: $e',
      );
    }
  }

  @override
  bool get supportsBytesOutput => true;
}

class NoTTSService implements TTSService {
  @override
  Future<void> speak(String text) async {
    debugPrint('TTS is disabled');
  }

  @override
  Future<void> pause() async {
    debugPrint('TTS is disabled');
  }

  @override
  Future<void> resume() async {
    debugPrint('TTS is disabled');
  }

  @override
  Future<void> stop() async {
    debugPrint('TTS is disabled');
  }

  @override
  Future<void> setLanguage(String languageCode) async {
    debugPrint('TTS is disabled');
  }

  @override
  Future<void> setSettings(TTSSettingsConfig config) async {
    debugPrint('TTS is disabled');
  }

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    return [];
  }

  @override
  void dispose() {}

  @override
  Stream<PlayerState> get playerStateStream =>
      Stream.value(PlayerState.completed);

  @override
  Future<Uint8List> getAudioBytes(String text) async {
    throw TTSException('TTS is disabled');
  }

  @override
  bool get supportsBytesOutput => false;
}

class TTSException implements Exception {
  final String message;
  TTSException(this.message);

  @override
  String toString() => message;
}
