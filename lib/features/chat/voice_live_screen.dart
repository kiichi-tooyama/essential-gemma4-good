import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart' show XFile;
import 'package:essential_sdk_dart/essential_sdk_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_language.dart';
import '../../app/app_preferences_controller.dart';
import '../../app/runtime_health_controller.dart';
import '../model_management/model_management_controller.dart';
import '../model_management/model_management_models.dart';
import '../shared/location_context_service.dart';
import '../shared/web_research_service.dart';
import 'camera_capture_screen.dart';
import 'chat_controller.dart';

class VoiceLiveScreen extends StatefulWidget {
  const VoiceLiveScreen({
    required this.chatController,
    required this.modelController,
    required this.preferencesController,
    required this.runtimeHealthController,
    this.initialModelId,
    this.autoStart = true,
    super.key,
  });

  final ChatController chatController;
  final ModelManagementController modelController;
  final AppPreferencesController preferencesController;
  final RuntimeHealthController runtimeHealthController;
  final String? initialModelId;
  final bool autoStart;

  @override
  State<VoiceLiveScreen> createState() => _VoiceLiveScreenState();
}

class _VoiceLiveScreenState extends State<VoiceLiveScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _voiceChannel = MethodChannel(
    'essential/native_voice',
  );
  static const MethodChannel _voiceEventsChannel = MethodChannel(
    'essential/native_voice_events',
  );
  static const int _liveShortPromptRunes = 1200;
  static const int _liveDefaultContextTokens = 3072;
  static const int _liveShortContextTokens = 2048;
  static const int _liveHeavyContextTokens = 2048;
  static const int _liveMultimodalContextTokens = 4000;

  final EssentialGenAiRuntime _genAiRuntime = EssentialGenAiRuntime();
  final WebResearchService _webResearchService = WebResearchService();
  final LocationContextService _locationContextService =
      const LocationContextService();

  List<EssentialGenAiModel> _genAiModels = const <EssentialGenAiModel>[];
  _LiveModelChoice? _selectedModel;
  final List<String> _pendingImagePaths = <String>[];

  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  bool _micEnabled = true;
  bool _loopRunning = false;
  bool _generating = false;
  bool _webSearchEnabled = true;
  bool get _locationSearchEnabled =>
      widget.preferencesController.locationSearchEnabled;
  _LivePhase _phase = _LivePhase.listening;
  String _status = 'Listening...';
  String _speechSequenceId = 'live-${DateTime.now().microsecondsSinceEpoch}';
  String _spokenBuffer = '';
  int _responseEpoch = 0;
  String? _activeAssistantMessageId;
  bool _assistantSpeaking = false;
  DateTime? _suppressListeningUntil;
  DateTime? _hardMuteUntil;
  LocationContextResult? _cachedLocationContext;
  DateTime? _cachedLocationAt;
  double _activity = 0.35;
  double _voiceLevel = 0;
  int _emptyListenCount = 0;
  bool _preferOnDeviceSpeech = true;

  @override
  void initState() {
    super.initState();
    _status = _liveText('聞き取り中…', 'Listening...');
    _voiceEventsChannel.setMethodCallHandler(_handleVoiceEvent);
    unawaited(_initialize());
  }

  String _liveText(String japanese, String english) {
    return widget.preferencesController.useEnglish ? english : japanese;
  }

  String _statusTextForPhase(_LivePhase phase) {
    switch (phase) {
      case _LivePhase.listening:
        return _liveText('聞き取り中…', 'Listening...');
      case _LivePhase.recognizing:
        return _liveText('聞き取っています…', 'Listening...');
      case _LivePhase.preparing:
        return _liveText('回答準備中…', 'Preparing answer...');
      case _LivePhase.locating:
        return _liveText('位置情報を取得中…', 'Getting location...');
      case _LivePhase.searchingWeb:
        return _liveText('Web検索中…', 'Searching the web...');
      case _LivePhase.webSourcesFound:
        return _liveText('Web情報を確認しました', 'Found web sources');
      case _LivePhase.noWebSources:
        return _liveText('Web情報は見つかりませんでした', 'No web sources found');
      case _LivePhase.generating:
        return _liveText('生成中…', 'Generating...');
      case _LivePhase.writing:
        return _liveText('回答を書いています…', 'Writing answer...');
      case _LivePhase.generatingAndSpeaking:
        return _liveText('生成・読み上げ中…', 'Generating and speaking...');
      case _LivePhase.speaking:
        return _liveText('読み上げ中…', 'Speaking...');
      case _LivePhase.cooldown:
        return _liveText('次の聞き取り準備中…', 'Ready to listen...');
      case _LivePhase.stopped:
        return _liveText('マイクオフ', 'Mic off');
      case _LivePhase.error:
        return _liveText('エラーが発生しました', 'Something went wrong');
    }
  }

  double _activityForPhase(_LivePhase phase) {
    switch (phase) {
      case _LivePhase.listening:
        return 0.62;
      case _LivePhase.recognizing:
        return 0.78;
      case _LivePhase.preparing:
        return 0.36;
      case _LivePhase.locating:
      case _LivePhase.searchingWeb:
      case _LivePhase.webSourcesFound:
      case _LivePhase.noWebSources:
        return 0.42;
      case _LivePhase.generating:
        return 0.72;
      case _LivePhase.writing:
      case _LivePhase.generatingAndSpeaking:
        return 0.82;
      case _LivePhase.speaking:
        return 0.56;
      case _LivePhase.cooldown:
        return 0.38;
      case _LivePhase.stopped:
        return 0.15;
      case _LivePhase.error:
        return 0.2;
    }
  }

  void _setLiveStatus(_LivePhase phase, {String? message, double? activity}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = phase;
      _status = message ?? _statusTextForPhase(phase);
      _activity = activity ?? _activityForPhase(phase);
    });
  }

  Future<void> _initialize() async {
    await widget.chatController.initialize(
      initialModelId: widget.initialModelId,
    );
    await widget.modelController.initialize();
    _genAiModels = await _genAiRuntime.discoverModels();
    _selectedModel = _resolveInitialModel();
    if (!mounted) {
      return;
    }
    setState(() {});
    if (widget.autoStart) {
      _startLoop();
    }
    unawaited(_warmAudioRuntime());
    unawaited(_prepareNativeTts());
    unawaited(_warmSelectedGenAiModel());
  }

  Future<void> _warmAudioRuntime() async {
    debugPrint('ESSENTIAL_PERF live_stt_runtime=android_speech_recognizer');
  }

  Future<void> _warmSelectedGenAiModel() async {
    final model = _selectedModel;
    if (model == null || model.runtime != _LiveModelRuntime.genAi) {
      return;
    }
    if (!_shouldCacheModel(model)) {
      return;
    }
    try {
      final warmup = await _genAiRuntime
          .warmUp(
            modelPath: model.path,
            maxTokens: 640,
            contextTokens: _liveContextTokensFor(
              model,
              requestedMaxTokens: 640,
              promptRunes: 0,
            ),
            topK: _stableLiveTopK(model),
            topP: _stableLiveTopP(model),
            temperature: _stableLiveTemperature(model),
            accelerator: 'gpu',
            visionAccelerator: 'gpu',
          )
          .timeout(const Duration(seconds: 30));
      debugPrint(
        'ESSENTIAL_PERF live_genai_warmup_ms=${warmup?.loadAndSetupMs ?? 0} model=${model.id}',
      );
    } catch (error) {
      debugPrint('Live GenAI warmup failed: $error');
    }
  }

  @override
  void dispose() {
    _micEnabled = false;
    unawaited(_voiceChannel.invokeMethod<void>('stopSpeaking'));
    unawaited(_voiceChannel.invokeMethod<void>('stopRecognition'));
    unawaited(_genAiRuntime.cancel());
    unawaited(_genAiRuntime.releaseIdle());
    _voiceEventsChannel.setMethodCallHandler(null);
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _handleVoiceEvent(MethodCall call) async {
    if (!mounted) {
      return;
    }
    switch (call.method) {
      case 'level':
        final args = call.arguments as Map<Object?, Object?>?;
        final level = (args?['level'] as num?)?.toDouble() ?? 0;
        setState(() {
          _voiceLevel = level.clamp(0.0, 1.0);
          if (_phase == _LivePhase.listening ||
              _phase == _LivePhase.recognizing) {
            _activity = (0.45 + _voiceLevel * 0.5).clamp(0.0, 1.0);
          }
        });
      case 'speechStart':
        if (_phase == _LivePhase.recognizing) {
          _setLiveStatus(_LivePhase.recognizing);
        }
      case 'speechEnd':
        setState(() => _voiceLevel = 0.08);
      case 'speechError':
        setState(() => _voiceLevel = 0);
    }
  }

  List<_LiveModelChoice> get _modelChoices {
    final choices = <_LiveModelChoice>[];
    final seenPaths = <String>{};
    for (final model in widget.modelController.installedModels) {
      final genAiReplacement = _preferredGenAiModelFor(model.modelId);
      _addLiveModelChoice(
        choices: choices,
        seenPaths: seenPaths,
        id: model.modelId,
        title: genAiReplacement == null
            ? model.displayName
            : _friendlyLiveModelTitle(model.modelId),
        sizeBytes: genAiReplacement?.sizeBytes ?? model.sizeBytes,
        path: genAiReplacement?.path ?? model.activePath,
      );
    }
    for (final bundle in widget.modelController.installedBundles) {
      for (final componentId in bundle.componentModelIds) {
        final component = widget.modelController.componentInstallationFor(
          componentId,
        );
        if (component == null || !_isLiveChatComponent(component)) {
          continue;
        }
        final genAiReplacement = _preferredGenAiModelFor(component.modelId);
        _addLiveModelChoice(
          choices: choices,
          seenPaths: seenPaths,
          id: 'bundle:${bundle.bundleId}:${component.modelId}',
          title: _friendlyLiveModelTitle(component.modelId),
          sizeBytes: genAiReplacement?.sizeBytes ?? component.sizeBytes,
          path: genAiReplacement?.path ?? component.activePath,
        );
      }
    }
    for (final model in _genAiModels) {
      if (!seenPaths.add(model.path)) {
        continue;
      }
      choices.add(
        _LiveModelChoice(
          id: model.id,
          title: model.title.isEmpty ? 'Local GenAI model' : model.title,
          subtitle: 'LiteRT-LM · ${_formatBytes(model.sizeBytes)}',
          path: model.path,
          runtime: _LiveModelRuntime.genAi,
        ),
      );
    }
    choices.sort((left, right) {
      final priority = _liveModelPriority(
        left,
      ).compareTo(_liveModelPriority(right));
      if (priority != 0) {
        return priority;
      }
      final leftGemma = left.title.toLowerCase().contains('gemma') ? 0 : 1;
      final rightGemma = right.title.toLowerCase().contains('gemma') ? 0 : 1;
      if (leftGemma != rightGemma) {
        return leftGemma.compareTo(rightGemma);
      }
      return left.title.compareTo(right.title);
    });
    return choices;
  }

  int _liveModelPriority(_LiveModelChoice choice) {
    final value = '${choice.id} ${choice.title} ${choice.path}'.toLowerCase();
    if (choice.runtime == _LiveModelRuntime.genAi &&
        value.contains('gemma-4-e2b')) {
      return 0;
    }
    if (choice.runtime == _LiveModelRuntime.genAi &&
        value.contains('gemma-4-e4b')) {
      return 1;
    }
    if (value.contains('gemma-4-e2b')) {
      return 2;
    }
    if (value.contains('gemma-4-e4b')) {
      return 3;
    }
    return 5;
  }

  bool _shouldCacheModel(_LiveModelChoice model) {
    return _isLiveGenAiModel(model) && !_isMemoryHeavyLiveModel(model);
  }

  bool _isMemoryHeavyLiveModel(_LiveModelChoice model) {
    final value = '${model.id} ${model.title} ${model.path}'.toLowerCase();
    return value.contains('e4b') && value.contains('litertlm');
  }

  int _liveContextTokensFor(
    _LiveModelChoice model, {
    bool hasImages = false,
    int? requestedMaxTokens,
    int? promptRunes,
  }) {
    final base = hasImages
        ? _liveMultimodalContextTokens
        : _isMemoryHeavyLiveModel(model)
        ? _liveHeavyContextTokens
        : promptRunes != null && promptRunes <= _liveShortPromptRunes
        ? _liveShortContextTokens
        : _liveDefaultContextTokens;
    return math.max(base, requestedMaxTokens ?? 0).clamp(512, 4096).toInt();
  }

  bool _isLiveGenAiModel(_LiveModelChoice model) {
    return model.runtime == _LiveModelRuntime.genAi &&
        model.path.toLowerCase().endsWith('.litertlm');
  }

  int _stableLiveTopK(_LiveModelChoice model) {
    if (_isLiveGenAiModel(model)) {
      return 8;
    }
    return 64;
  }

  double _stableLiveTopP(_LiveModelChoice model) {
    if (_isLiveGenAiModel(model)) {
      return 0.82;
    }
    return 0.95;
  }

  double _stableLiveTemperature(_LiveModelChoice model) {
    if (_isLiveGenAiModel(model)) {
      return 0.2;
    }
    return 1.0;
  }

  EssentialGenAiModel? _preferredGenAiModelFor(String modelId) {
    final normalizedModelId = modelId.toLowerCase();
    String? target;
    if (normalizedModelId == 'gemma-4-e2b-it' ||
        normalizedModelId == 'gemma-4-e2b-litertlm-it') {
      target = 'gemma-4-e2b-it';
    } else if (normalizedModelId == 'gemma-4-e4b-it' ||
        normalizedModelId == 'gemma-4-e4b-litertlm-it') {
      target = 'gemma-4-e4b-it';
    }
    if (target == null) {
      return null;
    }
    for (final model in _genAiModels) {
      final path = model.path.toLowerCase();
      if (path.contains(target) && path.endsWith('.litertlm')) {
        return model;
      }
    }
    return null;
  }

  void _addLiveModelChoice({
    required List<_LiveModelChoice> choices,
    required Set<String> seenPaths,
    required String id,
    required String title,
    required int sizeBytes,
    required String path,
  }) {
    final normalized = path.toLowerCase();
    if (!seenPaths.add(path)) {
      return;
    }
    if (normalized.endsWith('.litertlm')) {
      choices.add(
        _LiveModelChoice(
          id: id,
          title: title,
          subtitle: 'LiteRT-LM · ${_formatBytes(sizeBytes)}',
          path: path,
          runtime: _LiveModelRuntime.genAi,
        ),
      );
    }
  }

  bool _isLiveChatComponent(InstalledBundleComponentRecord component) {
    return component.type == 'base' &&
        component.modality == 'text' &&
        (component.format == 'litertlm' ||
            component.activePath.toLowerCase().endsWith('.litertlm'));
  }

  String _friendlyLiveModelTitle(String modelId) {
    switch (modelId) {
      case 'gemma-4-e4b-it':
        return _liveText('Gemma-4 E4B 高品質', 'Gemma-4 E4B High quality');
      case 'gemma-4-e4b-litertlm-it':
        return 'Gemma-4 E4B LiteRT-LM';
      case 'gemma-4-e2b-litertlm-it':
        return 'Gemma-4 E2B LiteRT-LM';
      case 'gemma-4-e2b-it':
        return _liveText('Gemma-4 E2B 軽量', 'Gemma-4 E2B Light');
      case 'essential-mini':
        return _liveText('Essential Mini 低負荷', 'Essential Mini Low load');
      default:
        return modelId;
    }
  }

  _LiveModelChoice? _resolveInitialModel() {
    final choices = _modelChoices;
    if (choices.isEmpty) {
      return null;
    }
    final initialId = widget.initialModelId;
    if (initialId != null) {
      for (final choice in choices) {
        if (choice.id == initialId) {
          return choice;
        }
      }
    }
    return choices.firstWhere(
      (choice) =>
          choice.runtime == _LiveModelRuntime.genAi &&
          choice.title.toLowerCase().contains('gemma'),
      orElse: () => choices.first,
    );
  }

  void _startLoop() {
    if (_loopRunning) {
      return;
    }
    _micEnabled = true;
    _loopRunning = true;
    _setLiveStatus(_LivePhase.listening);
    unawaited(_listenLoop());
  }

  Future<void> _prepareNativeTts() async {
    try {
      await _voiceChannel.invokeMethod<void>('prepareTts', <String, Object?>{
        'language': widget.preferencesController.useEnglish ? 'en-US' : 'ja-JP',
        'engine': 'android_tts',
      });
    } catch (error) {
      debugPrint('Live TTS prepare skipped: $error');
    }
  }

  Future<void> _toggleMic() async {
    if (_micEnabled) {
      _micEnabled = false;
      _spokenBuffer = '';
      if (_generating ||
          _assistantSpeaking ||
          _activeAssistantMessageId != null) {
        await _interruptActiveResponse();
      }
      _assistantSpeaking = false;
      await _stopLiveRecordingQuietly();
      await _voiceChannel.invokeMethod<void>('stopSpeaking');
      await _genAiRuntime.cancel();
      if (!mounted) {
        return;
      }
      _setLiveStatus(_LivePhase.stopped);
      return;
    }
    _startLoop();
  }

  Future<void> _listenLoop() async {
    while (mounted && _micEnabled) {
      if (_phase == _LivePhase.cooldown || _phase == _LivePhase.speaking) {
        if (await _isListeningSuppressed()) {
          await Future<void>.delayed(const Duration(milliseconds: 160));
          continue;
        }
        _setLiveStatus(_LivePhase.listening);
        continue;
      }
      if (_phase != _LivePhase.listening) {
        await Future<void>.delayed(const Duration(milliseconds: 160));
        continue;
      }
      if (await _isListeningSuppressed()) {
        _setLiveStatus(
          _assistantSpeaking ? _LivePhase.speaking : _LivePhase.cooldown,
        );
        await Future<void>.delayed(const Duration(milliseconds: 180));
        continue;
      }
      _setLiveStatus(_LivePhase.recognizing);
      final recognized = await _recognizeOnce();
      if (!mounted || !_micEnabled) {
        break;
      }
      final userText = recognized.trim();
      if (userText.isEmpty) {
        _emptyListenCount += 1;
        setState(() {
          _phase = _LivePhase.listening;
          _status = _liveText('聞き取れませんでした', 'Could not hear that');
          _activity = 0.24;
          _voiceLevel = 0;
        });
        final delayMs = math.min(1800, 450 + _emptyListenCount * 260);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (mounted && _micEnabled && _phase == _LivePhase.listening) {
          _setLiveStatus(_LivePhase.listening);
        }
        continue;
      }
      _emptyListenCount = 0;
      _setLiveStatus(_LivePhase.preparing);
      unawaited(_answer(userText));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    _loopRunning = false;
  }

  Future<String> _recognizeOnce() async {
    try {
      if (await _isListeningSuppressed()) {
        return '';
      }
      final recordStartedAt = DateTime.now();
      final language = widget.preferencesController.useEnglish
          ? 'en-US'
          : 'ja-JP';
      var text = await _voiceChannel.invokeMethod<String>(
        'recognizeOnce',
        <String, Object?>{
          'language': language,
          'preferOnDevice': _preferOnDeviceSpeech,
        },
      );
      if ((text ?? '').trim().isEmpty &&
          widget.preferencesController.useEnglish) {
        text = await _voiceChannel.invokeMethod<String>(
          'recognizeOnce',
          <String, Object?>{
            'language': 'ja-JP',
            'preferOnDevice': _preferOnDeviceSpeech,
          },
        );
      }
      debugPrint(
        'ESSENTIAL_PERF live_stt_ms=${DateTime.now().difference(recordStartedAt).inMilliseconds} recognizer=android_on_device chars=${text?.trim().runes.length ?? 0}',
      );
      return text?.trim() ?? '';
    } on PlatformException catch (error) {
      if (_preferOnDeviceSpeech &&
          (error.code == 'speech_unavailable' ||
              error.code == 'speech_error')) {
        _preferOnDeviceSpeech = false;
        await Future<void>.delayed(const Duration(milliseconds: 220));
        return _recognizeOnce();
      }
      if (mounted && error.code != 'speech_error') {
        _setLiveStatus(
          _LivePhase.error,
          message:
              error.message ??
              _liveText('音声認識に失敗しました', 'Speech recognition failed'),
        );
        setState(() => _voiceLevel = 0);
      }
      return '';
    } catch (error) {
      debugPrint('Live Android speech recognition failed: $error');
      if (mounted) {
        _setLiveStatus(
          _LivePhase.error,
          message: _liveText(
            '端末内音声認識に失敗しました',
            'On-device speech recognition failed',
          ),
        );
      }
      return '';
    }
  }

  Future<void> _stopLiveRecordingQuietly() async {
    await _voiceChannel
        .invokeMethod<void>('stopRecognition')
        .catchError((_) {});
  }

  Future<bool> _isListeningSuppressed() async {
    final now = DateTime.now();
    final suppressUntil = _suppressListeningUntil;
    final hardMuteUntil = _hardMuteUntil;
    if ((suppressUntil != null && now.isBefore(suppressUntil)) ||
        (hardMuteUntil != null && now.isBefore(hardMuteUntil))) {
      return true;
    }
    try {
      final state = await _voiceChannel.invokeMethod<Map<Object?, Object?>>(
        'getTtsState',
      );
      if (state?['speaking'] == true || state?['initializing'] == true) {
        _assistantSpeaking = true;
        _hardMuteUntil = now.add(const Duration(milliseconds: 450));
        return true;
      }
      if (_assistantSpeaking) {
        setState(() {
          _assistantSpeaking = false;
          if (_phase == _LivePhase.speaking ||
              _phase == _LivePhase.generatingAndSpeaking) {
            _phase = _LivePhase.cooldown;
            _status = _statusTextForPhase(_LivePhase.cooldown);
            _activity = _activityForPhase(_LivePhase.cooldown);
          }
        });
      }
    } catch (_) {
      // If native TTS state is unavailable, rely on Dart-side state.
      if (_assistantSpeaking) {
        return true;
      }
    }
    return false;
  }

  Future<void> _answer(String userText) async {
    final model = _selectedModel ?? _resolveInitialModel();
    if (model == null) {
      await widget.chatController.addUserMessage(userText);
      final assistantId = widget.chatController.startAssistantMessage(
        progressLabel: _liveText('モデル確認中', 'Checking model'),
      );
      await widget.chatController.failAssistantMessage(
        assistantId,
        _liveText(
          'AIモデルが見つかりません。AI追加からモデルを追加してください。',
          'No AI model was found. Add a model from Add AI.',
        ),
      );
      _setLiveStatus(
        _LivePhase.error,
        message: _liveText('AIモデルがありません', 'No AI model available'),
      );
      return;
    }

    _setLiveStatus(_LivePhase.preparing);
    _selectedModel = model;
    final imagePaths = List<String>.from(_pendingImagePaths);
    _pendingImagePaths.clear();
    final attachments = imagePaths
        .map(
          (path) => ChatAttachment(
            id: 'live-image-${DateTime.now().microsecondsSinceEpoch}-$path',
            type: ChatAttachmentType.image,
            filePath: path,
          ),
        )
        .toList(growable: false);

    await widget.chatController.addUserMultimodalMessage(
      text: userText,
      attachments: attachments,
    );
    await widget.chatController.updateCurrentModel(model.id);
    final assistantId = widget.chatController.startAssistantMessage(
      progressLabel: _liveText('回答準備中', 'Preparing answer'),
    );
    final responseEpoch = ++_responseEpoch;
    _activeAssistantMessageId = assistantId;
    _speechSequenceId =
        'live-$responseEpoch-${DateTime.now().microsecondsSinceEpoch}';
    _spokenBuffer = '';
    _hardMuteUntil = DateTime.now().add(const Duration(milliseconds: 900));
    await _stopLiveRecordingQuietly();

    setState(() {
      _generating = true;
      _phase = _LivePhase.preparing;
      _status = _statusTextForPhase(_LivePhase.preparing);
      _activity = _activityForPhase(_LivePhase.preparing);
    });

    try {
      final webResult = _webSearchEnabled
          ? await _buildWebResearchForPrompt(
              userText,
              hasImages: imagePaths.isNotEmpty,
            )
          : const WebResearchResult(query: '', sources: <WebSource>[]);
      final webContext = webResult.buildPromptContext(maxRunes: 850);
      if (mounted && _isCurrentResponse(responseEpoch, assistantId)) {
        if (webResult.hasSources) {
          _setLiveStatus(_LivePhase.webSourcesFound);
          await Future<void>.delayed(const Duration(milliseconds: 180));
        } else if (webResult.query.trim().isNotEmpty &&
            !_isObviousLocalOnlyPrompt(userText)) {
          _setLiveStatus(_LivePhase.noWebSources);
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      final prompt = _buildPrompt(
        userText,
        webContext: webContext,
        webSearchQuery: webResult.hasSources ? webResult.query : null,
        hasImages: imagePaths.isNotEmpty,
      );
      await _answerWithGenAi(
        model: model,
        assistantId: assistantId,
        prompt: prompt,
        imagePaths: imagePaths,
        webSources: webResult.sources,
        responseEpoch: responseEpoch,
      );
      if (!_isCurrentResponse(responseEpoch, assistantId)) {
        return;
      }
      await _flushSpeech(force: true);
      await _voiceChannel.invokeMethod<void>('finishSpeech', <String, Object?>{
        'sequenceId': _speechSequenceId,
      });
      await _waitForTtsQuiet();
      _assistantSpeaking = false;
      if (mounted) {
        _setLiveStatus(_micEnabled ? _LivePhase.listening : _LivePhase.stopped);
      }
    } catch (error) {
      if (!_isCurrentResponse(responseEpoch, assistantId)) {
        return;
      }
      _assistantSpeaking = false;
      await widget.chatController.failAssistantMessage(
        assistantId,
        _liveText(
          '応答生成に失敗しました: $error',
          'Failed to generate a response: $error',
        ),
      );
      if (mounted) {
        _setLiveStatus(
          _LivePhase.error,
          message: _liveText('応答に失敗しました', 'Response failed'),
        );
      }
    } finally {
      if (_isCurrentResponse(responseEpoch, assistantId)) {
        _activeAssistantMessageId = null;
      }
      if (mounted && responseEpoch == _responseEpoch) {
        setState(() {
          _generating = false;
        });
      }
    }
  }

  Future<void> _answerWithGenAi({
    required _LiveModelChoice model,
    required String assistantId,
    required String prompt,
    required List<String> imagePaths,
    required List<WebSource> webSources,
    required int responseEpoch,
  }) async {
    var streamed = '';
    final maxTokens = _liveResponseTokenBudget(
      prompt: prompt,
      hasImages: imagePaths.isNotEmpty,
    );
    if (mounted) {
      _setLiveStatus(_LivePhase.generating);
    }
    final response = await _generateLiveGenAi(
      model: model,
      prompt: prompt,
      imagePaths: imagePaths,
      maxTokens: maxTokens,
      onToken: (token) {
        if (!mounted ||
            !_micEnabled ||
            !_isCurrentResponse(responseEpoch, assistantId)) {
          return;
        }
        final visible = _cleanToken(streamed, token);
        if (visible.isEmpty) {
          return;
        }
        streamed += visible;
        widget.chatController.appendAssistantChunk(assistantId, visible);
        unawaited(_queueSpeech(visible));
        _setLiveStatus(
          _assistantSpeaking
              ? _LivePhase.generatingAndSpeaking
              : _LivePhase.writing,
        );
      },
    );
    if (!_isCurrentResponse(responseEpoch, assistantId)) {
      return;
    }
    final completedText = _repairLiveOutput(
      _cleanOutput(response.text),
      webSources: webSources,
    );
    await widget.chatController.completeAssistantMessage(
      assistantId,
      finalText: completedText,
      webSources: webSources,
    );
    if (_isCurrentResponse(responseEpoch, assistantId) &&
        streamed.trim().isEmpty &&
        !_looksLikeJunkSpeech(completedText)) {
      await _queueSpeech(completedText, force: true);
    }
    unawaited(_finishPostGenerationModelWork(model));
  }

  Future<void> _finishPostGenerationModelWork(_LiveModelChoice model) async {
    try {
      await widget.chatController
          .summarizeAndWriteSharedMemoryFromCurrentSession(
            summarize: (prompt) => _summarizeMemoryWithGenAi(model, prompt),
          );
    } finally {
      await _genAiRuntime.releaseIdle(
        keepModelPath: _shouldCacheModel(model) ? model.path : null,
      );
    }
  }

  Future<WebResearchResult> _buildWebResearchForPrompt(
    String userText, {
    required bool hasImages,
  }) async {
    if (_isObviousLocalOnlyPrompt(userText) && !hasImages) {
      return WebResearchResult(query: userText, sources: const <WebSource>[]);
    }
    final planningText = userText.trim();
    final shouldUseWeb =
        _webResearchService.shouldUseWeb(planningText) ||
        hasImages ||
        _isProductResearchPrompt(planningText);
    if (!shouldUseWeb) {
      return WebResearchResult(query: userText, sources: const <WebSource>[]);
    }
    var locationContext = '';
    var locationNotice = '';
    if (_locationSearchEnabled && _shouldUseLocationForWeb(planningText)) {
      _setLiveStatus(_LivePhase.locating);
      final locationResult = await _currentLocationContextForWeb();
      locationContext = locationResult.context;
      locationNotice = locationResult.notice;
    } else if (!_locationSearchEnabled &&
        _shouldUseLocationForWeb(planningText)) {
      locationNotice = '位置情報がオフのため、利用可能な情報だけで回答します。';
    }
    _setLiveStatus(_LivePhase.searchingWeb);
    return _webResearchService.research(
      _takeRunes(
        _webQueryForLive(
          _livePlanningTextForQuery(userText, hasImages: hasImages),
          hasImages: hasImages,
        ),
        220,
      ),
      maxResults: 3,
      maxPageReads: 1,
      pageMaxChars: 700,
      locationContext: locationContext,
      locationNotice: locationNotice,
    );
  }

  int _liveResponseTokenBudget({
    required String prompt,
    required bool hasImages,
  }) {
    if (_isObviousLocalOnlyPrompt(prompt) && !hasImages) return 96;
    if (hasImages || _isProductResearchPrompt(prompt)) return 900;
    if (prompt.runes.length < 80) return 360;
    return 640;
  }

  bool _isProductResearchPrompt(String promptText) {
    return RegExp(
      r'(商品|製品|型番|値段|価格|レビュー|口コミ|Amazon|楽天|比較|どっち|どちら|買う|購入|OCR|バーコード|JAN)',
      caseSensitive: false,
    ).hasMatch(promptText);
  }

  String _webQueryForLive(String planningText, {required bool hasImages}) {
    final compact = planningText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (hasImages && _isProductResearchPrompt(compact)) {
      return '$compact 価格 レビュー 比較';
    }
    if (hasImages) {
      return '$compact 画像 商品 価格 レビュー';
    }
    return compact;
  }

  bool _isObviousLocalOnlyPrompt(String promptText) {
    return RegExp(
      r'^(こんにちは|こんばんは|おはよう|ありがとう|ありがと|hi|hello|hey|ok|了解|うん|はい|いいえ)[。!！\s]*$',
      caseSensitive: false,
    ).hasMatch(promptText.trim().toLowerCase());
  }

  String _livePlanningTextForQuery(String userText, {required bool hasImages}) {
    final buffer = StringBuffer(userText.trim());
    if (hasImages) {
      buffer.writeln('添付画像あり。画像内容に関する検索が必要な可能性があります。');
    }
    return buffer.toString().trim();
  }

  bool _shouldUseLocationForWeb(String promptText) {
    return RegExp(
      r'(近く|近所|周辺|最寄り|ここから|現在地|現在いる|今いる|今いる所|今いるところ|ここ|こちら|付近|天気|気温|雨|near me|nearby|weather)',
      caseSensitive: false,
    ).hasMatch(promptText);
  }

  Future<LocationContextResult> _currentLocationContextForWeb() async {
    try {
      final cached = _cachedLocationContext;
      final cachedAt = _cachedLocationAt;
      if (cached != null &&
          cached.context.trim().isNotEmpty &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < const Duration(minutes: 5)) {
        return cached;
      }
      final result = await _locationContextService.currentForWeb();
      _cachedLocationContext = result;
      _cachedLocationAt = DateTime.now();
      return result;
    } catch (error) {
      debugPrint('Live location unavailable: $error');
      return const LocationContextResult(
        context: '',
        notice: '位置情報を取得できなかったため、利用可能な情報だけで回答します。',
      );
    }
  }

  Future<EssentialGenAiGenerationResult> _generateLiveGenAi({
    required _LiveModelChoice model,
    required String prompt,
    required List<String> imagePaths,
    required int maxTokens,
    required void Function(String token) onToken,
  }) async {
    Future<EssentialGenAiGenerationResult> run(String accelerator) async {
      final stopwatch = Stopwatch()..start();
      final contextTokens = _liveContextTokensFor(
        model,
        hasImages: imagePaths.isNotEmpty,
        requestedMaxTokens: maxTokens,
        promptRunes: prompt.runes.length,
      );
      final response = await _genAiRuntime.generate(
        requestId: 'live-${DateTime.now().microsecondsSinceEpoch}',
        modelPath: model.path,
        prompt: prompt,
        systemInstruction: _liveSystemInstruction(),
        imagePaths: imagePaths,
        maxTokens: maxTokens,
        contextTokens: contextTokens,
        topK: _stableLiveTopK(model),
        topP: _stableLiveTopP(model),
        temperature: _stableLiveTemperature(model),
        accelerator: accelerator,
        visionAccelerator: imagePaths.isEmpty ? accelerator : 'gpu',
        onToken: onToken,
      );
      debugPrint(
        'ESSENTIAL_PERF live_genai_total_ms=${stopwatch.elapsedMilliseconds} '
        'native_latency_ms=${response.latencyMs} '
        'native_load_ms=${response.loadAndSetupMs ?? -1} '
        'native_first_token_ms=${response.firstTokenMs ?? -1} '
        'native_generation_ms=${response.generationMs} '
        'accelerator=${response.accelerator ?? accelerator} '
        'max_tokens=$maxTokens context_tokens=$contextTokens '
        'model=${model.id} chars=${response.text.runes.length}',
      );
      return response;
    }

    try {
      return await run('gpu');
    } on PlatformException catch (error) {
      final message = error.message ?? '';
      final shouldRetryOnCpu =
          error.code == 'genai_error' &&
          (message.contains('Failed to enqueue barrier') ||
              message.contains('Status Code: 13') ||
              message.contains('INTERNAL'));
      if (!shouldRetryOnCpu || imagePaths.isNotEmpty) {
        rethrow;
      }
      if (mounted) {
        _setLiveStatus(
          _LivePhase.generating,
          message: _liveText('CPUで再試行しています…', 'Retrying on CPU...'),
          activity: 0.48,
        );
      }
      return run('cpu');
    }
  }

  String _buildPrompt(
    String userText, {
    required String webContext,
    required String? webSearchQuery,
    required bool hasImages,
  }) {
    final messages =
        widget.chatController.currentSession?.messages ?? const <ChatMessage>[];
    final history = messages
        .where((message) => message.text.trim().isNotEmpty)
        .where(
          (message) =>
              message.role != ChatMessageRole.user ||
              message.text.trim() != userText.trim(),
        )
        .toList(growable: false);
    final start = math.max(0, history.length - 4);
    final buffer = StringBuffer();
    final sharedMemoryContext = widget.chatController
        .buildSharedMemoryPromptContext();
    if (sharedMemoryContext.isNotEmpty) {
      buffer
        ..writeln(sharedMemoryContext)
        ..writeln();
    }
    if (history.isNotEmpty) {
      buffer.writeln('同一会話内の履歴:');
      for (final message in history.sublist(start)) {
        final role = message.role == ChatMessageRole.user ? 'ユーザー' : 'AI';
        buffer.writeln('$role: ${_takeRunes(message.text, 180)}');
      }
      buffer.writeln();
    }
    if (webContext.isNotEmpty) {
      if (webSearchQuery != null) {
        buffer.writeln('次のWeb検索結果を根拠にして答えてください。検索クエリ: $webSearchQuery');
      }
      buffer.writeln(
        'Web検索結果と現在地情報はこのアプリから提供されています。利用可能な情報として扱い、「Web検索できません」「場所が分かりません」とは言わず、根拠を使って答えてください。現在地情報が含まれる場合は、それをユーザーの現在地として扱ってください。',
      );
      buffer.writeln(_takeRunes(webContext, 850));
      buffer.writeln();
    }
    if (hasImages) {
      buffer.writeln('添付画像を確認し、見える内容を根拠に答えてください。');
      buffer.writeln(
        '商品や型番が写っている場合は、商品名・型番・JANなど見える文字をOCR相当で抽出し、Web検索結果があれば価格帯、レビュー傾向、比較ポイントをURL根拠付きで整理してください。',
      );
      buffer.writeln();
    }
    buffer.writeln('今回のユーザー発話: $userText');
    return buffer.toString();
  }

  String _liveSystemInstruction() {
    return widget.preferencesController.t('live.system');
  }

  Future<String> _summarizeMemoryWithGenAi(
    _LiveModelChoice model,
    String prompt,
  ) async {
    try {
      final response = await _genAiRuntime
          .generate(
            requestId: 'live-memory-${DateTime.now().microsecondsSinceEpoch}',
            modelPath: model.path,
            prompt: prompt,
            systemInstruction: '会話内容を短く要約してください。余計な説明は書かないでください。',
            maxTokens: 96,
            contextTokens: _liveContextTokensFor(model, requestedMaxTokens: 96),
            topK: 8,
            topP: 0.8,
            temperature: 0.1,
          )
          .timeout(const Duration(seconds: 45));
      return _cleanOutput(response.text);
    } catch (_) {
      return '';
    }
  }

  Future<void> _queueSpeech(String chunk, {bool force = false}) async {
    final text = _speechTextForTts(chunk);
    if (text.isEmpty) {
      return;
    }
    _spokenBuffer += text;
    await _flushSpeech(force: force);
  }

  Future<void> _waitForTtsQuiet() async {
    _setLiveStatus(_LivePhase.speaking);
    final deadline = DateTime.now().add(const Duration(seconds: 18));
    while (mounted && DateTime.now().isBefore(deadline)) {
      try {
        final state = await _voiceChannel.invokeMethod<Map<Object?, Object?>>(
          'getTtsState',
        );
        if (state?['speaking'] != true && state?['initializing'] != true) {
          break;
        }
      } catch (_) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    _suppressListeningUntil = DateTime.now().add(
      const Duration(milliseconds: 650),
    );
    _hardMuteUntil = _suppressListeningUntil;
    _setLiveStatus(_LivePhase.cooldown);
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  Future<void> _flushSpeech({bool force = false}) async {
    final text = _spokenBuffer.trim();
    if (text.isEmpty) {
      return;
    }
    final shouldSpeak =
        force ||
        RegExp(r'[。！？.!?\n]$').hasMatch(text) ||
        text.runes.length >= 72;
    if (!shouldSpeak) {
      debugPrint(
        'ESSENTIAL_PERF live_tts_flush_deferred chars=${text.runes.length} force=$force',
      );
      return;
    }
    _spokenBuffer = '';
    final language = _ttsLanguageForText(text);
    _assistantSpeaking = true;
    final now = DateTime.now();
    _hardMuteUntil = now.add(const Duration(milliseconds: 500));
    _suppressListeningUntil = _hardMuteUntil;
    await _stopLiveRecordingQuietly();
    _setLiveStatus(
      _generating ? _LivePhase.generatingAndSpeaking : _LivePhase.speaking,
    );
    try {
      debugPrint(
        'ESSENTIAL_PERF live_tts_chunk_chars=${text.runes.length} language=$language method=speakChunk engine=android_tts',
      );
      final state = await _voiceChannel
          .invokeMethod<Map<Object?, Object?>>('speakChunk', <String, Object?>{
            'text': text,
            'sequenceId': _speechSequenceId,
            'flush': false,
            'language': language,
            'engine': 'android_tts',
          });
      debugPrint(
        'ESSENTIAL_PERF live_tts_chunk_state engine=${state?['engine']} playbackEngine=${state?['playbackEngine']} speaking=${state?['speaking']} active=${state?['activeUtterances']} utteranceId=${state?['utteranceId']}',
      );
    } on PlatformException catch (chunkError) {
      debugPrint(
        'Live speakChunk failed: ${chunkError.code} ${chunkError.message} details=${chunkError.details}',
      );
      _assistantSpeaking = false;
      _setLiveStatus(
        _LivePhase.error,
        message: _liveText('読み上げに失敗しました', 'TTS unavailable'),
      );
    } catch (error) {
      debugPrint('Live TTS failed: $error');
      _assistantSpeaking = false;
      _setLiveStatus(
        _LivePhase.error,
        message: _liveText('読み上げに失敗しました', 'TTS unavailable'),
      );
    }
  }

  String _ttsLanguageForText(String text) {
    final asciiLetters = RegExp(r'[A-Za-z]').allMatches(text).length;
    final japanese = RegExp(
      r'[\u3040-\u30ff\u3400-\u9fff]',
    ).allMatches(text).length;
    return asciiLetters > japanese * 2 ? 'en-US' : 'ja-JP';
  }

  bool _isCurrentResponse(int responseEpoch, String assistantId) {
    return responseEpoch == _responseEpoch &&
        _activeAssistantMessageId == assistantId &&
        _micEnabled;
  }

  Future<void> _interruptActiveResponse() async {
    _responseEpoch += 1;
    _spokenBuffer = '';
    _assistantSpeaking = false;
    _suppressListeningUntil = DateTime.now().add(
      const Duration(milliseconds: 400),
    );
    _hardMuteUntil = _suppressListeningUntil;
    final interruptedMessageId = _activeAssistantMessageId;
    _activeAssistantMessageId = null;
    await _voiceChannel.invokeMethod<void>('stopSpeaking');
    await _genAiRuntime.cancel();
    if (interruptedMessageId != null) {
      await widget.chatController.completeAssistantMessage(
        interruptedMessageId,
      );
    }
    if (mounted) {
      setState(() => _generating = false);
      _setLiveStatus(
        _LivePhase.cooldown,
        message: _liveText('割り込みを受け付けました', 'Interruption accepted'),
        activity: 0.5,
      );
    }
  }

  String _speechTextForTts(String value) {
    return value
        .replaceAll(RegExp(r'[*＊]+'), '')
        .split('\n')
        .map((line) {
          final cleaned = line
              .replaceAll(RegExp(r'^[\s・\-—–•●○#]+'), '')
              .replaceAll(RegExp(r'[!?！？]+'), '')
              .trimRight();
          return _isTtsPunctuationOnly(cleaned) ? '' : cleaned;
        })
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .replaceAll(RegExp(r'\s+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  bool _isTtsPunctuationOnly(String value) {
    return value
        .replaceAll(RegExp(r'''[\s。、，,：:；;…・\-—–()（）「」『』"'“”]+'''), '')
        .isEmpty;
  }

  String _cleanToken(String currentText, String token) {
    if (token.trim().isEmpty && currentText.isEmpty) {
      return '';
    }
    final compact = token.replaceAll(RegExp(r'\s+'), '').trim();
    if (RegExp(
      r'^<?unused[_-]?\d+>?$',
      caseSensitive: false,
    ).hasMatch(compact)) {
      return '';
    }
    if (_looksLikeSymbolGarbage(token) || _looksLikeSymbolGarbage(compact)) {
      return '';
    }
    return token;
  }

  String _cleanOutput(String text) {
    return text
        .split('\n')
        .map(
          (line) => line.replaceAll(
            RegExp(r'<?\bunused[_-]?\d+\b>?', caseSensitive: false),
            '',
          ),
        )
        .where((line) => !RegExp(r'^([*＊・\-—–•●○#\s])+$').hasMatch(line.trim()))
        .map((line) => line.replaceAll(RegExp(r'[*＊]+'), ''))
        .where((line) => !_looksLikeSymbolGarbage(line))
        .where((line) => !_isInternalReasoningLine(line))
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _repairLiveOutput(String text, {required List<WebSource> webSources}) {
    if (!_looksLikeJunkSpeech(text)) {
      return text;
    }
    final facts = webSources
        .take(3)
        .map(
          (source) => source.snippet.trim().isNotEmpty
              ? source.snippet.trim()
              : source.excerpt.trim(),
        )
        .where((value) => value.isNotEmpty)
        .map((value) => _takeRunes(value.replaceAll(RegExp(r'\s+'), ' '), 110))
        .toList(growable: false);
    if (facts.isNotEmpty) {
      return '確認できた情報を短くまとめます。\n・${facts.join('\n・')}';
    }
    return 'すみません、音声回答の生成が途中で崩れました。もう一度聞いてください。';
  }

  bool _looksLikeJunkSpeech(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '').trim();
    if (compact.isEmpty) {
      return true;
    }
    if (_looksLikeSymbolGarbage(compact)) {
      return true;
    }
    final meaningfulChars = RegExp(
      r'[A-Za-z0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',
    ).allMatches(compact).length;
    return compact.length >= 20 && meaningfulChars / compact.length < 0.18;
  }

  bool _looksLikeSymbolGarbage(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '').trim();
    if (compact.length < 8) {
      return false;
    }
    if (RegExp(r'''^(?:[<>|/"'`\\]+)+$''').hasMatch(compact)) {
      return true;
    }
    if (RegExp(r'''(?:>\s*<\s*\|\s*["']?\s*){3,}''').hasMatch(value)) {
      return true;
    }
    final symbolChars = RegExp(
      r'''[<>|/"'`\\_\-=~^:;,.、。・*＊#@!！?？()[\]{}]+''',
    ).allMatches(compact).length;
    final meaningfulChars = RegExp(
      r'[A-Za-z0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',
    ).allMatches(compact).length;
    return compact.length >= 24 &&
        symbolChars / compact.length > 0.78 &&
        meaningfulChars < 4;
  }

  bool _isInternalReasoningLine(String line) {
    final normalized = line
        .replaceAll(RegExp(r'[*_`#>\s]'), '')
        .replaceAll('：', ':')
        .trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.contains('思考過程') ||
        normalized.contains('役割名') ||
        normalized.contains('内部メモ') ||
        normalized.contains('話者ラベル')) {
      return true;
    }
    return RegExp(r'^\d+\.(確認|分析|推論|思考|解釈|回答方針)[:：]?').hasMatch(normalized) ||
        RegExp(r'^(確認|分析|推論|思考|解釈|回答方針)[:：]').hasMatch(normalized);
  }

  String _takeRunes(String value, int maxCharacters) {
    if (value.runes.length <= maxCharacters) {
      return value;
    }
    return String.fromCharCodes(value.runes.take(maxCharacters));
  }

  Future<void> _showModelPicker() async {
    final choices = _modelChoices;
    if (choices.isEmpty) {
      _setLiveStatus(
        _LivePhase.error,
        message: _liveText('使えるモデルがありません', 'No available model'),
      );
      return;
    }
    final picked = await showModalBottomSheet<_LiveModelChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  context.appText('Liveで使うAI', 'AI for Live'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final choice in choices)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: Text(choice.title),
                  subtitle: Text(choice.subtitle),
                  trailing: _selectedModel?.id == choice.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(choice),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) {
      return;
    }
    await widget.chatController.updateCurrentModel(picked.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedModel = picked;
      _phase = _micEnabled ? _LivePhase.listening : _LivePhase.stopped;
      _status = widget.preferencesController.useEnglish
          ? 'Switched to ${picked.title}'
          : '${picked.title} にしました';
      _activity = _activityForPhase(_phase);
    });
    unawaited(_warmSelectedGenAiModel());
  }

  Future<void> _capturePhoto() async {
    final captured = await Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(builder: (_) => const CameraCaptureScreen()),
    );
    if (captured == null || !mounted) {
      return;
    }
    setState(() {
      _pendingImagePaths.add(captured.path);
      _phase = _micEnabled ? _LivePhase.listening : _LivePhase.stopped;
      _status = _liveText(
        '次の発話に写真を添付します',
        'Photo will be attached to your next speech',
      );
      _activity = _activityForPhase(_phase);
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return 'local';
    }
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) {
      return '${mb.toStringAsFixed(0)} MB';
    }
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final messages =
        widget.chatController.currentSession?.messages ?? const <ChatMessage>[];
    final visibleMessages = messages.length > 2
        ? messages.sublist(messages.length - 2)
        : messages;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _glowController,
            widget.chatController,
            widget.preferencesController,
          ]),
          builder: (context, _) {
            final pulse = _glowController.value;
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        color: Colors.white,
                        tooltip: context.appText('閉じる', 'Close'),
                      ),
                      const Spacer(),
                      const Icon(Icons.graphic_eq_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Essential Live',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _showModelPicker,
                        icon: const Icon(Icons.tune_rounded),
                        color: Colors.white,
                        tooltip: context.appText('モデル選択', 'Choose model'),
                      ),
                    ],
                  ),
                ),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: <Widget>[
                      if (visibleMessages.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            context.appText(
                              '話しかけると、会話がここに表示されます。',
                              'Speak and the conversation will appear here.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      for (final message in visibleMessages)
                        _LiveMessageLine(message: message),
                    ],
                  ),
                ),
                _LiveGlow(
                  activity: _activity,
                  voiceLevel: _voiceLevel,
                  pulse: pulse,
                  aiSpeaking: _generating || _assistantSpeaking,
                ),
                if (_pendingImagePaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      context.appText(
                        '${_pendingImagePaths.length}枚の画像を次の発話に添付',
                        '${_pendingImagePaths.length} image(s) will be attached to your next speech',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white60),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const buttonCount = 5;
                      final gap = constraints.maxWidth < 360 ? 6.0 : 8.0;
                      final buttonSize = math.min(
                        62.0,
                        (constraints.maxWidth - gap * (buttonCount - 1)) /
                            buttonCount,
                      );
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _RoundLiveButton(
                            icon: Icons.photo_camera_rounded,
                            onPressed: _capturePhoto,
                            size: buttonSize,
                          ),
                          SizedBox(width: gap),
                          _RoundLiveButton(
                            icon: _webSearchEnabled
                                ? Icons.travel_explore_rounded
                                : Icons.public_off_rounded,
                            onPressed: () => setState(
                              () => _webSearchEnabled = !_webSearchEnabled,
                            ),
                            active: _webSearchEnabled,
                            size: buttonSize,
                          ),
                          SizedBox(width: gap),
                          _RoundLiveButton(
                            icon: _locationSearchEnabled
                                ? Icons.my_location_rounded
                                : Icons.location_disabled_rounded,
                            onPressed: _webSearchEnabled
                                ? () => widget.preferencesController
                                      .updateLocationSearchEnabled(
                                        !_locationSearchEnabled,
                                      )
                                : null,
                            active: _webSearchEnabled && _locationSearchEnabled,
                            size: buttonSize,
                          ),
                          SizedBox(width: gap),
                          _RoundLiveButton(
                            icon: _micEnabled
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            onPressed: _toggleMic,
                            active: _micEnabled,
                            size: buttonSize,
                          ),
                          SizedBox(width: gap),
                          _RoundLiveButton(
                            icon: Icons.close_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                            danger: true,
                            size: buttonSize,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (_selectedModel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _selectedModel!.title,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white38),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LiveMessageLine extends StatelessWidget {
  const _LiveMessageLine({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF26364F) : const Color(0xE61B1E24),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: isUser
                    ? context.appText('自分: ', 'You: ')
                    : context.appText('AI: ', 'AI: '),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: message.text.isEmpty ? '…' : message.text),
            ],
          ),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white, height: 1.42),
        ),
      ),
    );
  }
}

class _LiveGlow extends StatelessWidget {
  const _LiveGlow({
    required this.activity,
    required this.voiceLevel,
    required this.pulse,
    required this.aiSpeaking,
  });

  final double activity;
  final double voiceLevel;
  final double pulse;
  final bool aiSpeaking;

  @override
  Widget build(BuildContext context) {
    final intensity = (activity + voiceLevel * 0.55 + pulse * 0.18).clamp(
      0.0,
      1.0,
    );
    return SizedBox(
      width: double.infinity,
      height: 250 + intensity * 42,
      child: CustomPaint(
        painter: _LiveWavePainter(
          activity: intensity,
          voiceLevel: voiceLevel,
          pulse: pulse,
          aiSpeaking: aiSpeaking,
        ),
      ),
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  const _LiveWavePainter({
    required this.activity,
    required this.voiceLevel,
    required this.pulse,
    required this.aiSpeaking,
  });

  final double activity;
  final double voiceLevel;
  final double pulse;
  final bool aiSpeaking;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        const Color(0x0007080C),
        Color.lerp(const Color(0xFF0B1728), const Color(0xFF103B69), activity)!,
        Color.lerp(const Color(0xFF19427B), const Color(0xFF2EA7FF), activity)!,
        Color.lerp(const Color(0xFF6DD7FF), const Color(0xFFB7F3FF), activity)!,
      ],
      stops: const <double>[0.0, 0.33, 0.72, 1.0],
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        bottomLeft: const Radius.circular(58),
        bottomRight: const Radius.circular(58),
      ),
      Paint()..shader = baseGradient.createShader(rect),
    );

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5 + activity * 5.0
      ..shader = LinearGradient(
        colors: <Color>[
          const Color(0x0065DCFF),
          const Color(0xFF4EB7FF).withValues(alpha: 0.72),
          const Color(0xFFB5F4FF).withValues(alpha: 0.92),
          const Color(0x00348BFF),
        ],
      ).createShader(rect);

    for (var layer = 0; layer < 4; layer++) {
      final path = Path();
      final layerPhase = pulse * math.pi * 2 + layer * 0.72;
      final centerY = size.height * (0.62 + layer * 0.07);
      final amplitude =
          10.0 + activity * (20 + layer * 8) + voiceLevel * (28 - layer * 3);
      for (var x = 0.0; x <= size.width; x += 8) {
        final t = x / size.width;
        final y =
            centerY +
            math.sin(t * math.pi * (2.0 + layer * 0.55) + layerPhase) *
                amplitude *
                (aiSpeaking ? 0.74 : 1.0) +
            math.sin(t * math.pi * 6 + pulse * math.pi * 2) * amplitude * 0.18;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        wavePaint..strokeWidth = 2.5 + activity * 4 - layer * 0.3,
      );
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: aiSpeaking ? Alignment.bottomRight : Alignment.bottomLeft,
        radius: 0.88 + activity * 0.35,
        colors: <Color>[
          const Color(0x9935A4FF),
          const Color(0x5536E0FF),
          const Color(0x00000000),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter oldDelegate) {
    return oldDelegate.activity != activity ||
        oldDelegate.voiceLevel != voiceLevel ||
        oldDelegate.pulse != pulse ||
        oldDelegate.aiSpeaking != aiSpeaking;
  }
}

class _RoundLiveButton extends StatelessWidget {
  const _RoundLiveButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFE53935)
        : active
        ? const Color(0xFF26364F)
        : const Color(0xFF171A22);
    final iconSize = math.max(22.0, math.min(28.0, size * 0.46));
    return SizedBox.square(
      dimension: size,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
          disabledBackgroundColor: background.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white38,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(math.min(22, size * 0.36)),
          ),
        ),
        child: Icon(icon, size: iconSize),
      ),
    );
  }
}

enum _LivePhase {
  listening,
  recognizing,
  preparing,
  locating,
  searchingWeb,
  webSourcesFound,
  noWebSources,
  generating,
  writing,
  generatingAndSpeaking,
  speaking,
  cooldown,
  stopped,
  error,
}

enum _LiveModelRuntime { genAi }

class _LiveModelChoice {
  const _LiveModelChoice({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.runtime,
  });

  final String id;
  final String title;
  final String subtitle;
  final String path;
  final _LiveModelRuntime runtime;
}
