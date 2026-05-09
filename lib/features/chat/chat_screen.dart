import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'chat_controller.dart';
import 'chat_input_bar.dart';
import 'chat_message_bubble.dart';
import 'voice_live_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.controller,
    required this.preferencesController,
    required this.runtimeHealthController,
    required this.onOpenModels,
    this.chatController,
    super.key,
    this.smokeModelPath,
    this.smokePrompt,
    this.smokePrompts = const <String>[],
    this.smokeImagePaths = const <String>[],
    this.smokeAudioPaths = const <String>[],
  });

  final ModelManagementController controller;
  final AppPreferencesController preferencesController;
  final RuntimeHealthController runtimeHealthController;
  final VoidCallback onOpenModels;
  final ChatController? chatController;
  final String? smokeModelPath;
  final String? smokePrompt;
  final List<String> smokePrompts;
  final List<String> smokeImagePaths;
  final List<String> smokeAudioPaths;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _nativeVoiceChannel = MethodChannel(
    'essential/native_voice',
  );
  static const MethodChannel _sharedIntentChannel = MethodChannel(
    'essential/shared_intent',
  );

  late final ChatController _chatController =
      widget.chatController ?? ChatController();
  late final bool _ownsChatController = widget.chatController == null;
  final _composerController = TextEditingController();
  final _modelPathController = TextEditingController();
  final _scrollController = ScrollController();
  final WebResearchService _webResearchService = WebResearchService();
  final LocationContextService _locationContextService =
      const LocationContextService();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Future<void> _chatReady = _chatController.initialize(
    initialModelId: widget.smokeModelPath != null ? _smokeModelId : null,
  );

  final EssentialGenAiRuntime _genAiRuntime = EssentialGenAiRuntime();
  static const int _heavyGenAiModelBytes = 3 * 1024 * 1024 * 1024;
  static const int _defaultGenAiContextTokens = 3072;
  static const int _heavyGenAiContextTokens = 2048;
  static const int _multimodalGenAiContextTokens = 4000;
  String? _loadedModelPath;
  int? _loadedModelSizeBytes;
  String _status = 'Choose a model to chat on this device.';
  bool _isPreparingModel = false;
  bool _isGenerating = false;
  bool _cancelRequested = false;
  bool _userIsReadingHistory = false;
  bool _smokeStarted = false;
  bool _runtimeRecovered = false;
  bool _lowMemoryFallbackSuggested = false;
  bool _autoSpeakResponses = false;
  bool _webSearchEnabled = true;
  bool get _locationSearchEnabled =>
      widget.preferencesController.locationSearchEnabled;
  _GenAiGenerationConfig _genAiConfig = const _GenAiGenerationConfig();
  String? _warmingGenAiPath;
  String? _warmedGenAiPath;
  String? _selectedAdapterId;
  List<EssentialGenAiModel> _discoveredGenAiModels =
      const <EssentialGenAiModel>[];
  Timer? _healthMonitorTimer;
  LocationContextResult? _cachedLocationContext;
  DateTime? _cachedLocationAt;

  @override
  void initState() {
    super.initState();
    _status = _chatText(
      'モデルを選択すると、この端末内で会話できます。',
      'Choose a model to chat on this device.',
    );
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize();
    widget.controller.addListener(_handleInventoryChanged);
    widget.runtimeHealthController.initialize();
    if (widget.smokeModelPath != null) {
      _modelPathController.text = widget.smokeModelPath!;
    }
    _chatReady.then((_) {
      if (mounted) {
        _handleInventoryChanged();
      }
    });
    unawaited(_discoverGenAiModels());
    _sharedIntentChannel.setMethodCallHandler(_handleSharedIntentCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeInitialShare());
    });
  }

  String _chatText(String japanese, String english) {
    return widget.preferencesController.useEnglish ? english : japanese;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_smokeStarted && widget.smokeModelPath != null) {
      _smokeStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runSmokeFlow();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleInventoryChanged);
    WidgetsBinding.instance.removeObserver(this);
    _healthMonitorTimer?.cancel();
    _pulseController.dispose();
    _composerController.dispose();
    _modelPathController.dispose();
    _scrollController.dispose();
    if (_ownsChatController) {
      _chatController.dispose();
    }
    unawaited(_genAiRuntime.releaseIdle());
    _sharedIntentChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleSharedIntentCall(MethodCall call) async {
    if (call.method == 'sharedText') {
      final text = call.arguments?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        _insertSharedText(text);
      }
    }
  }

  Future<void> _consumeInitialShare() async {
    try {
      final text = await _sharedIntentChannel.invokeMethod<String>(
        'getInitialText',
      );
      if (text != null && text.trim().isNotEmpty) {
        _insertSharedText(text.trim());
      }
    } catch (_) {}
  }

  void _insertSharedText(String text) {
    if (!mounted) {
      return;
    }
    final prefix = _composerController.text.trim().isEmpty ? '' : '\n\n';
    _composerController.text = '${_composerController.text}$prefix$text';
    _composerController.selection = TextSelection.collapsed(
      offset: _composerController.text.length,
    );
    setState(() {
      _status = _chatText(
        '共有された内容を入力欄に追加しました。',
        'Added the shared content to the input field.',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isGenerating) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _cancelRequested = true;
      unawaited(_genAiRuntime.cancel());
      if (mounted) {
        setState(() {
          _status = _chatText(
            'バックグラウンド移行を検知したため、推論を安全停止しました。',
            'Stopped inference safely because the app moved to the background.',
          );
        });
      }
    }
  }

  Future<void> _ensureModelLoaded(_ModelChoice choice) async {
    if (_isGenAiModelChoice(choice) && _loadedModelPath == choice.path) {
      return;
    }
    if (!_isGenAiModelChoice(choice)) {
      throw StateError('Essential のAI生成は LiteRT-LM モデルのみ対応です。');
    }

    setState(() {
      _isPreparingModel = true;
      _status = _chatText(
        '${choice.title} を準備しています…',
        'Preparing ${choice.title}...',
      );
    });

    try {
      final stopwatch = Stopwatch()..start();
      final modelSizeBytes = await _modelSizeBytes(choice.path);
      if (modelSizeBytes == null) {
        throw StateError('Model file is not readable: ${choice.path}');
      }
      _loadedModelPath = choice.path;
      _loadedModelSizeBytes = modelSizeBytes;
      if (!mounted) {
        return;
      }
      debugPrint(
        'ESSENTIAL_PERF genai_model_ready_ms=${stopwatch.elapsedMilliseconds} model=${choice.id}',
      );
      setState(() {
        _status = _chatText(
          '${choice.title} の準備ができました。',
          '${choice.title} is ready.',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _chatText(
          'モデル準備に失敗しました: $error',
          'Model preparation failed: $error',
        );
      });
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingModel = false;
        });
      }
    }
  }

  Future<void> _generate({
    String? textOverride,
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    await _chatReady;
    if (_isGenerating) {
      return;
    }

    final session = _chatController.currentSession;
    final promptText = (textOverride ?? _composerController.text).trim();
    if (session == null || (promptText.isEmpty && attachments.isEmpty)) {
      return;
    }

    final selectedChoice = _resolveSelectedChoice();
    if (selectedChoice == null) {
      setState(() {
        _status = _chatText('先にモデルをダウンロードしてください。', 'Download a model first.');
      });
      return;
    }
    setState(() {
      _status = attachments.isEmpty
          ? _chatText(
              'この端末内で回答を生成しています…',
              'Generating an answer on this device...',
            )
          : _chatText(
              '添付ファイルを端末内モデルで解析しています…',
              'Analyzing attachments with the on-device model...',
            );
    });
    final enrichedAttachments = await _enrichAttachments(attachments);
    final choice = _resolveGenerationChoice(
      selectedChoice,
      enrichedAttachments,
    );
    if (_requiresGenAiModel(enrichedAttachments) &&
        !_isGenAiModelChoice(choice)) {
      setState(() {
        _status = _chatText(
          '画像・音声付きの質問には、Gemma LiteRT-LM などのマルチモーダルモデルが必要です。AI追加画面で画像対応モデルを追加してください。',
          'Questions with images or audio require a multimodal model such as Gemma LiteRT-LM. Add an image-capable model from Add AI.',
        );
      });
      return;
    }

    await widget.runtimeHealthController.refreshDeviceSnapshot();
    final currentModelSizeBytes = await _modelSizeBytes(choice.path);
    final preflight = widget.runtimeHealthController.buildPreflightDecision(
      currentModelId: choice.id,
      baseMaxTokens: 512,
      catalog: widget.controller.catalog,
      installedModels: _chatModelRecords,
      currentModelSizeBytes: currentModelSizeBytes,
    );
    if (preflight.blocked) {
      if (preflight.shouldSuggestFallback &&
          preflight.suggestedFallbackModelId != null &&
          await _confirmFallbackSwitch(
            message: preflight.message,
            fallbackModelName: preflight.suggestedFallbackModelName,
          )) {
        await _chatController.updateCurrentModel(
          preflight.suggestedFallbackModelId!,
        );
        setState(() {
          _status = _chatText(
            '軽量モデルへ切り替えました。もう一度送信してください。',
            'Switched to a lighter model. Send again.',
          );
        });
        return;
      }
      setState(() {
        _status = preflight.message;
      });
      return;
    }
    if (preflight.shouldSuggestFallback &&
        preflight.suggestedFallbackModelId != null &&
        preflight.suggestedFallbackModelId != choice.id) {
      _lowMemoryFallbackSuggested = true;
    }
    if (!_isGenAiModelChoice(choice)) {
      setState(() {
        _status = _chatText(
          'LiteRT-LM モデルを選択してください。旧LLM経路は無効化されています。',
          'Select a LiteRT-LM model. The legacy LLM path is disabled.',
        );
      });
      return;
    }

    _composerController.clear();
    await _chatController.addUserMultimodalMessage(
      text: promptText,
      attachments: enrichedAttachments,
    );
    await _chatController.updateCurrentModel(choice.id);
    final assistantMessageId = _chatController.startAssistantMessage(
      progressLabel: _webSearchEnabled
          ? _chatText('Web検索の必要性を確認中', 'Checking whether web search is needed')
          : _chatText('モデル初期化中', 'Initializing model'),
    );
    _scheduleScrollToBottom(force: true);
    final startedAt = DateTime.now();

    setState(() {
      _isGenerating = true;
      _cancelRequested = false;
      _runtimeRecovered = false;
      _status = _webSearchEnabled
          ? _chatText(
              'Web検索の必要性を確認しています…',
              'Checking whether web search is needed...',
            )
          : _chatText('モデルを初期化しています…', 'Initializing model...');
    });

    final webResult = _webSearchEnabled
        ? await _buildWebResearchForPrompt(
            promptText,
            assistantMessageId,
            enrichedAttachments,
          )
        : const WebResearchResult(query: '', sources: <WebSource>[]);
    final webContext = webResult.buildPromptContext();
    final requestedMaxTokens = _responseTokenBudget(
      promptText: promptText,
      attachments: enrichedAttachments,
      preflightMaxTokens: _isGenAiModelChoice(choice)
          ? _genAiContextTokensFor(choice)
          : preflight.maxTokens,
      modelSizeBytes: currentModelSizeBytes,
      choice: choice,
    );

    setState(() {
      _status = _chatText(
        'この端末内で回答を生成しています…',
        'Generating an answer on this device...',
      );
    });

    try {
      widget.runtimeHealthController.markInferenceStart();
      await widget.preferencesController.markInferenceStarted();
      _chatController.updateAssistantProgress(
        assistantMessageId,
        _chatText('モデル初期化中', 'Initializing model'),
      );
      await _generateWithGenAi(
        choice: choice,
        assistantMessageId: assistantMessageId,
        promptText: promptText,
        attachments: enrichedAttachments,
        webResult: webResult,
        webContext: webContext,
        requestedMaxTokens: requestedMaxTokens,
        startedAt: startedAt,
      );
    } catch (error) {
      debugPrint(
        'ESSENTIAL_PERF generation_error model=${choice.id} error=$error',
      );
      final fallbackMessage = await _handleFailureFallback(
        currentModelId: choice.id,
        currentModelPath: choice.path,
      );
      await _chatController.failAssistantMessage(
        assistantMessageId,
        _cancelRequested
            ? _chatText(
                '生成を停止しました。必要なら続きから聞き直せます。',
                'Generation stopped. Ask from where it left off if needed.',
              )
            : '${fallbackMessage ?? _chatText('応答を生成できませんでした。別のモデルに切り替えるか、もう一度お試しください。', 'Could not generate a response. Switch to another model or try again.')}\n$error',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _cancelRequested
            ? _chatText('生成を停止しました。', 'Generation stopped.')
            : fallbackMessage ?? _chatText('生成に失敗しました。', 'Generation failed.');
      });
    } finally {
      await widget.preferencesController.markInferenceFinished();
      await widget.runtimeHealthController.markInferenceFinished(
        latency: DateTime.now().difference(startedAt),
        recoveredRuntime: _runtimeRecovered,
        lowMemoryFallbackSuggested: _lowMemoryFallbackSuggested,
      );
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
      _scheduleScrollToBottom();
    }
  }

  Future<WebResearchResult> _buildWebResearchForPrompt(
    String promptText,
    String assistantMessageId,
    List<ChatAttachment> attachments,
  ) async {
    final plan = await _buildPromptPlan(promptText, attachments);
    if (!plan.shouldUseWeb) {
      _chatController.updateAssistantProgress(
        assistantMessageId,
        _chatText('モデル初期化中', 'Initializing model'),
      );
      setState(() {
        _status = _chatText('モデルを初期化しています…', 'Initializing model...');
      });
      return WebResearchResult(query: plan.query, sources: const <WebSource>[]);
    }

    if (!await _webResearchService.isOnlineForFeatures()) {
      final offlineNotice = _chatText(
        'オフラインのため、Web検索と位置情報を使わずに端末内モデルで回答します。',
        'Offline. I will answer on device without web search or location.',
      );
      _chatController.updateAssistantProgress(
        assistantMessageId,
        _chatText('モデル初期化中', 'Initializing model'),
      );
      setState(() {
        _status = offlineNotice;
      });
      return WebResearchResult(
        query: plan.query,
        sources: const <WebSource>[],
        locationNotice: offlineNotice,
      );
    }

    var locationContext = '';
    var locationNotice = '';
    if (_locationSearchEnabled && plan.shouldUseLocation) {
      _chatController.updateAssistantProgress(
        assistantMessageId,
        _chatText('位置情報を確認中', 'Checking location'),
      );
      setState(() {
        _status = _chatText('現在地を確認しています…', 'Checking location...');
      });
      final locationResult = await _currentLocationContextForWeb();
      locationContext = locationResult.context;
      locationNotice = locationResult.notice;
    } else if (!_locationSearchEnabled && plan.shouldUseLocation) {
      locationNotice = _chatText(
        '位置情報がオフのため、利用可能な情報だけで回答します。',
        'Location is off, so I will answer with the available information only.',
      );
    }

    _chatController.updateAssistantProgress(
      assistantMessageId,
      _chatText('Web検索中', 'Searching the web'),
    );
    setState(() {
      _status = _chatText('Web検索中…', 'Searching the web...');
    });
    final result = await _webResearchService.research(
      plan.query,
      locationContext: locationContext,
      locationNotice: locationNotice,
    );
    if (result.hasSources) {
      _chatController.updateAssistantWebSources(
        assistantMessageId,
        result.sources,
      );
      _chatController.updateAssistantProgress(
        assistantMessageId,
        _chatText('情報源を確認中', 'Checking sources'),
      );
      setState(() {
        _status = _chatText('情報源を確認しています…', 'Checking sources...');
      });
    } else {
      _chatController.updateAssistantProgress(
        assistantMessageId,
        _chatText('モデル初期化中', 'Initializing model'),
      );
      setState(() {
        _status = _chatText(
          'Web検索結果なし。端末内モデルで回答します…',
          'No web results. Answering with the on-device model...',
        );
      });
    }
    return result;
  }

  Future<_PromptPlan> _buildPromptPlan(
    String promptText,
    List<ChatAttachment> attachments,
  ) async {
    if (_isObviousLocalOnlyPrompt(promptText) && attachments.isEmpty) {
      return _PromptPlan(
        query: promptText,
        shouldUseWeb: false,
        shouldUseLocation: false,
      );
    }
    final planningInput = _planningInput(promptText, attachments);
    final shouldUseLocation = _shouldUseLocationForWeb(planningInput);
    var shouldUseWeb =
        _webResearchService.shouldUseWeb(planningInput) ||
        attachments.any((attachment) => _hasUsefulImageClue(attachment));
    if (!shouldUseWeb) {
      shouldUseWeb = await _shouldUseWebForPrompt(planningInput);
    }
    final query = _searchQueryForPrompt(promptText, attachments);
    return _PromptPlan(
      query: query.trim().isEmpty ? planningInput : query,
      shouldUseWeb: shouldUseWeb,
      shouldUseLocation: shouldUseLocation,
    );
  }

  Future<bool> _shouldUseWebForPrompt(String promptText) async {
    final trimmed = promptText.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_webResearchService.shouldUseWeb(trimmed)) {
      return true;
    }
    final normalized = trimmed.toLowerCase();
    final obviousLocalOnly = _isObviousLocalOnlyPrompt(normalized);
    final factualLookup = RegExp(
      r'([一-龥ぁ-んァ-ン]{2,}(市|区|町|村|県|府|都|道|駅|大学|会社|施設|病院|学校|公園).*(について|教えて|とは|情報|概要|どんな|どこ))',
    ).hasMatch(trimmed);
    if (factualLookup) {
      return true;
    }
    if (obviousLocalOnly || trimmed.runes.length <= 12) {
      return false;
    }
    final choice = _resolveWebGateChoice();
    if (!_isGenAiModelChoice(choice)) {
      return false;
    }
    try {
      final response = await _genAiRuntime
          .generate(
            requestId: _newRequestId('webgate'),
            modelPath: choice!.path,
            prompt:
                '次のユーザー入力に回答するために最新情報や外部情報のWeb検索が必要ならYES、不要ならNOだけ返してください。\n\n入力: $trimmed',
            systemInstruction: 'YESかNOだけを返してください。',
            maxTokens: 8,
            contextTokens: _genAiContextTokensFor(
              choice,
              requestedMaxTokens: 8,
            ),
            topK: 1,
            topP: 0.1,
            temperature: 0.0,
            accelerator: _genAiConfig.accelerator,
            visionAccelerator: _genAiConfig.accelerator,
          )
          .timeout(const Duration(seconds: 2));
      final answer = response.text.toUpperCase();
      if (answer.contains('YES')) {
        return true;
      }
      if (answer.contains('NO')) {
        return false;
      }
    } catch (error) {
      debugPrint('Web gate skipped: $error');
    }
    return false;
  }

  bool _isObviousLocalOnlyPrompt(String promptText) {
    return RegExp(
      r'^(こんにちは|こんばんは|おはよう|ありがとう|ありがと|hi|hello|hey|ok|了解|うん|はい|いいえ)[。!！\s]*$',
      caseSensitive: false,
    ).hasMatch(promptText.trim().toLowerCase());
  }

  _ModelChoice? _resolveWebGateChoice() {
    final choices = _modelChoices.where(_isGenAiModelChoice).toList();
    if (choices.isEmpty) {
      return null;
    }
    final selected = _resolveSelectedChoice();
    if (selected != null &&
        _isGenAiModelChoice(selected) &&
        !_isHighAccuracyModelId(selected.id)) {
      return selected;
    }
    for (final choice in choices) {
      if (!_isUnstableE2bLiteRtChoice(choice) &&
          !_isStableE4bLiteRtChoice(choice)) {
        return choice;
      }
    }
    for (final choice in choices) {
      if (_isUnstableE2bLiteRtChoice(choice)) {
        return choice;
      }
    }
    for (final choice in choices) {
      if (_isStableE4bLiteRtChoice(choice)) {
        return choice;
      }
    }
    return null;
  }

  String _planningInput(String promptText, List<ChatAttachment> attachments) {
    final buffer = StringBuffer(promptText.trim());
    final history = _genAiHistoryPrompt();
    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('直近の会話:')
        ..writeln(_takeRunes(history, 900));
    }
    final sharedMemoryContext = _chatController
        .buildSharedMemoryPromptContext();
    if (sharedMemoryContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(sharedMemoryContext);
    }
    final attachmentContext = _attachmentContextForPrompt(attachments);
    if (attachmentContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(attachmentContext);
    }
    return buffer.toString().trim();
  }

  String _searchQueryForPrompt(
    String promptText,
    List<ChatAttachment> attachments,
  ) {
    final parts = <String>[promptText.trim()];
    if (promptText.trim().runes.length <= 18) {
      final history = _genAiHistoryPrompt();
      if (history.isNotEmpty) {
        parts.add(_takeRunes(history.replaceAll(RegExp(r'\s+'), ' '), 160));
      }
    }
    for (final attachment in attachments) {
      parts.addAll(attachment.detectedObjects.map(_stripConfidence));
      parts.addAll(
        attachment.analysisLabels
            .where((label) => !_isGenericImageLabel(label))
            .map(_stripConfidence),
      );
      if (attachment.location != null) {
        final location = attachment.location!;
        parts.add(
          '緯度 ${location.latitude.toStringAsFixed(5)} 経度 ${location.longitude.toStringAsFixed(5)} 周辺',
        );
      }
    }
    final query = parts
        .map((part) => part.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((part) => part.isNotEmpty)
        .take(8)
        .join(' ');
    return _takeRunes(query, 220);
  }

  String _attachmentContextForPrompt(List<ChatAttachment> attachments) {
    final buffer = StringBuffer();
    for (final attachment in attachments) {
      if (attachment.type == ChatAttachmentType.image) {
        final labels = <String>[
          ...attachment.detectedObjects,
          ...attachment.analysisLabels,
        ].where((label) => label.trim().isNotEmpty).toList(growable: false);
        if (labels.isNotEmpty) {
          buffer.writeln('画像から得られた手がかり: ${labels.join(', ')}');
        }
      } else if (attachment.type == ChatAttachmentType.audio &&
          (attachment.transcription?.trim().isNotEmpty ?? false)) {
        buffer.writeln('音声文字起こし: ${attachment.transcription!.trim()}');
      } else if (attachment.type == ChatAttachmentType.location &&
          attachment.location != null) {
        final location = attachment.location!;
        buffer.writeln(
          '添付位置: 緯度 ${location.latitude.toStringAsFixed(6)}, 経度 ${location.longitude.toStringAsFixed(6)}, 精度 約${location.accuracy?.toStringAsFixed(0) ?? "不明"}m',
        );
      }
    }
    return _takeRunes(buffer.toString().trim(), 900);
  }

  String _stripConfidence(String value) {
    return value.replaceAll(RegExp(r'\s+\d{1,3}%$'), '').trim();
  }

  bool _hasUsefulImageClue(ChatAttachment attachment) {
    if (attachment.type != ChatAttachmentType.image) {
      return false;
    }
    return attachment.detectedObjects.isNotEmpty ||
        attachment.analysisLabels.any((label) => !_isGenericImageLabel(label));
  }

  bool _isGenericImageLabel(String label) {
    final normalized = label.trim();
    return normalized.isEmpty ||
        normalized == '画像を添付しました' ||
        normalized == '物体検出: なし';
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
      debugPrint('Location context unavailable for web search: $error');
      return const LocationContextResult(
        context: '',
        notice: '位置情報を取得できなかったため、利用可能な情報だけで回答します。',
      );
    }
  }

  Future<void> _generateWithGenAi({
    required _ModelChoice choice,
    required String assistantMessageId,
    required String promptText,
    required List<ChatAttachment> attachments,
    required WebResearchResult webResult,
    required String webContext,
    required int requestedMaxTokens,
    required DateTime startedAt,
  }) async {
    final stopwatch = Stopwatch()..start();
    final imagePaths = attachments
        .where((attachment) => attachment.type == ChatAttachmentType.image)
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toList(growable: false);
    final audioPaths = attachments
        .where((attachment) => attachment.type == ChatAttachmentType.audio)
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toList(growable: false);
    final requestId = _newRequestId('genai');
    var streamedText = '';
    var firstTokenSeen = false;
    final minWebTokens = webResult.hasSources ? 384 : 32;
    final effectiveMaxTokens = math
        .max(requestedMaxTokens, minWebTokens)
        .clamp(32, _genAiOutputLimit(promptText, attachments))
        .toInt();
    final contextTokens = _genAiContextTokensFor(
      choice,
      attachments: attachments,
      requestedMaxTokens: effectiveMaxTokens,
    );
    final effectiveTopK = _stableGenAiTopK(choice);
    final effectiveTopP = _stableGenAiTopP(choice);
    final effectiveTemperature = _stableGenAiTemperature(choice);
    _chatController.updateAssistantProgress(
      assistantMessageId,
      _chatText('思考中', 'Thinking'),
    );
    final response = await _genAiRuntime.generate(
      requestId: requestId,
      modelPath: choice.path,
      prompt: _buildGenAiPrompt(
        promptText,
        attachments,
        webContext: webContext,
      ),
      systemInstruction: _chatSystemInstruction(),
      imagePaths: imagePaths,
      audioPaths: audioPaths,
      maxTokens: effectiveMaxTokens,
      contextTokens: contextTokens,
      topK: effectiveTopK,
      topP: effectiveTopP,
      temperature: effectiveTemperature,
      accelerator: _genAiConfig.accelerator,
      visionAccelerator: _genAiConfig.accelerator,
      onToken: (token) {
        if (!mounted || _cancelRequested) {
          return;
        }
        if (!firstTokenSeen) {
          firstTokenSeen = true;
          _chatController.updateAssistantProgress(
            assistantMessageId,
            _chatText('回答生成中', 'Generating answer'),
          );
        }
        final visibleToken = _visibleGenAiToken(streamedText, token);
        if (visibleToken.isEmpty) {
          return;
        }
        streamedText += visibleToken;
        _chatController.appendAssistantChunk(assistantMessageId, visibleToken);
        _scheduleScrollToBottom();
      },
    );
    if (!mounted) {
      return;
    }
    final completed = _repairLowInformationAnswer(
      promptText: promptText,
      answer: _cleanGenAiOutput(response.text),
      webResult: webResult,
    );
    await _chatController.completeAssistantMessage(
      assistantMessageId,
      finalText: completed,
      webSources: webResult.sources,
    );
    if (!choice.isSmokeModel) {
      await widget.controller.markModelUsed(choice.id);
    }
    unawaited(_speakIfEnabled(completed));
    unawaited(_finishPostGenerationModelWork(choice));
    debugPrint(
      'ESSENTIAL_PERF genai_total_ms=${stopwatch.elapsedMilliseconds} native_latency_ms=${response.latencyMs} native_load_ms=${response.loadAndSetupMs ?? -1} native_first_token_ms=${response.firstTokenMs ?? -1} native_generation_ms=${response.generationMs} accelerator=${response.accelerator ?? _genAiConfig.accelerator} max_tokens=$effectiveMaxTokens context_tokens=$contextTokens top_k=$effectiveTopK top_p=$effectiveTopP temperature=$effectiveTemperature model=${choice.id} chars=${_runeLength(completed)} since_start_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
    );
    setState(() {
      _status = _chatText('応答が完了しました。', 'Response complete.');
    });
  }

  Future<void> _finishPostGenerationModelWork(_ModelChoice choice) async {
    try {
      await _chatController.summarizeAndWriteSharedMemoryFromCurrentSession(
        summarize: (prompt) => _summarizeMemoryWithChoice(choice, prompt),
      );
    } finally {
      await _genAiRuntime.releaseIdle();
    }
  }

  Future<String> _summarizeMemoryWithChoice(
    _ModelChoice choice,
    String prompt,
  ) async {
    try {
      if (!_isGenAiModelChoice(choice)) {
        return '';
      }
      final response = await _genAiRuntime
          .generate(
            requestId: _newRequestId('memory'),
            modelPath: choice.path,
            prompt: prompt,
            systemInstruction: '会話内容を短く要約してください。余計な説明は書かないでください。',
            maxTokens: 64,
            contextTokens: _genAiContextTokensFor(
              choice,
              requestedMaxTokens: 64,
            ),
            topK: 8,
            topP: 0.8,
            temperature: 0.1,
            accelerator: _genAiConfig.accelerator,
            visionAccelerator: _genAiConfig.accelerator,
          )
          .timeout(const Duration(seconds: 30));
      return _cleanGenAiOutput(response.text);
    } catch (error) {
      debugPrint('Shared memory summarizer unavailable: $error');
      return '';
    }
  }

  String _buildGenAiPrompt(
    String promptText,
    List<ChatAttachment> attachments, {
    String webContext = '',
  }) {
    final hasImages = attachments.any(
      (attachment) => attachment.type == ChatAttachmentType.image,
    );
    final hasAudio = attachments.any(
      (attachment) => attachment.type == ChatAttachmentType.audio,
    );
    final buffer = StringBuffer();
    final sharedMemoryContext = _chatController
        .buildSharedMemoryPromptContext();
    if (sharedMemoryContext.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(sharedMemoryContext);
    }
    final history = _genAiHistoryPrompt();
    if (history.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('直近の会話履歴:');
      buffer.writeln(history);
    }
    if (webContext.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(webContext);
      buffer.writeln();
      buffer.writeln(
        'Web検索結果と現在地情報はこのアプリから提供されています。利用可能な情報として扱い、「Web検索できません」「場所が分かりません」とは言わず、根拠を使って自然な文章だけで答えてください。特殊トークン、記号列、引用符の反復は出力しないでください。',
      );
    }
    if (hasImages) {
      buffer.writeln();
      buffer.writeln('添付画像を確認し、見える内容を根拠に答えてください。');
    }
    if (hasAudio) {
      buffer.writeln();
      buffer.writeln('添付音声を聞き取り、その内容に答えてください。');
    }
    final attachmentContext = _attachmentContextForPrompt(attachments);
    if (attachmentContext.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(attachmentContext);
    }
    final normalizedPrompt = promptText.trim();
    if (normalizedPrompt.isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('今回のユーザー入力:');
      buffer.write(normalizedPrompt);
    }
    return buffer.isEmpty
        ? widget.preferencesController.t('chat.defaultPrompt')
        : buffer.toString();
  }

  String _chatSystemInstruction() {
    return widget.preferencesController.t('chat.system');
  }

  String _genAiHistoryPrompt() {
    final messages = _chatController.currentSession?.messages;
    if (messages == null || messages.length <= 1) {
      return '';
    }
    final history = messages
        .take(messages.length - 1)
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);
    if (history.isEmpty) {
      return '';
    }
    final start = math.max(0, history.length - 8);
    final buffer = StringBuffer();
    for (final message in history.sublist(start)) {
      final role = message.role == ChatMessageRole.user ? 'ユーザー' : 'AI';
      final text = _takeRunes(
        message.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        420,
      );
      buffer.writeln('$role: $text');
    }
    return buffer.toString().trim();
  }

  String _visibleGenAiToken(String currentText, String token) {
    if (token.isEmpty) {
      return '';
    }
    final combined = '$currentText$token';
    final lines = combined.split('\n');
    final lastLine = lines.isEmpty ? combined : lines.last.trim();
    if (_isEmptyBulletLine(lastLine)) {
      final previousLines = lines
          .take(lines.length - 1)
          .map((line) => line.trim())
          .where(_isEmptyBulletLine)
          .length;
      if (previousLines >= 2 || token.trim().replaceAll('\n', '').length <= 2) {
        return '';
      }
    }
    if (_looksLikeUnusedTokenFragment(token) ||
        _looksLikeUnusedTokenFragment(lastLine)) {
      return '';
    }
    if (_looksLikeSymbolGarbage(token) || _looksLikeSymbolGarbage(lastLine)) {
      return '';
    }
    return token;
  }

  String _cleanGenAiOutput(String text) {
    final cleanedLines = <String>[];
    var emptyBulletRun = 0;
    for (final rawLine in text.trim().split('\n')) {
      final line = rawLine.trimRight();
      if (_isEmptyBulletLine(line.trim())) {
        emptyBulletRun += 1;
        if (emptyBulletRun > 1) {
          continue;
        }
        continue;
      }
      final withoutUnused = line.replaceAll(
        RegExp(r'<?\bunused[_-]?\d+\b>?', caseSensitive: false),
        '',
      );
      if (withoutUnused.trim().isEmpty) {
        continue;
      }
      if (_looksLikeSymbolGarbage(withoutUnused)) {
        continue;
      }
      emptyBulletRun = 0;
      cleanedLines.add(withoutUnused);
    }
    return cleanedLines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _repairLowInformationAnswer({
    required String promptText,
    required String answer,
    required WebResearchResult webResult,
  }) {
    if (_looksLikeJunkAnswer(answer) && webResult.hasSources) {
      return _answerFromWebSources(
        promptText: promptText,
        webResult: webResult,
      );
    }
    if (_looksLikeJunkAnswer(answer)) {
      return 'すみません、回答の生成が途中で崩れました。もう一度、短く自然な文章で答え直してください。';
    }
    final placeName = _placeNameFromPrompt(promptText);
    if (placeName == null || !_looksLikeLowInformationPlaceAnswer(answer)) {
      return answer;
    }
    final facts = <String>[];
    for (final source in webResult.sources.take(3)) {
      final text = <String>[
        source.snippet,
        source.excerpt,
      ].where((item) => item.trim().isNotEmpty).join(' ');
      final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.isNotEmpty) {
        facts.add(_takeRunes(compact, 120));
      }
    }
    if (facts.isNotEmpty) {
      return '$placeNameについて、確認できた情報をまとめます。\n'
          '・${facts.join('\n・')}\n'
          'さらに詳しく知りたい場合は、人口、交通、観光、住みやすさなどの観点で続けて聞いてください。';
    }
    return '$placeNameについて、まず概要から説明します。'
        '市区町村について聞かれた場合は、所在地、交通、生活環境、観光や歴史などを順に見ると分かりやすいです。'
        '現在Web検索結果を使えないため最新の数値は断定しませんが、必要ならWeb検索をオンにして最新情報も確認できます。';
  }

  bool _looksLikeJunkAnswer(String answer) {
    final normalized = answer
        .replaceAll(RegExp(r'<?\bunused[_-]?\d+\b>?', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s*＊・\-—–•●○#]+'), '');
    if (normalized.trim().isEmpty) {
      return true;
    }
    if (_looksLikeSymbolGarbage(answer)) {
      return true;
    }
    final meaningfulChars = RegExp(
      r'[A-Za-z0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',
    ).allMatches(answer).length;
    final visibleChars = answer.runes.where((code) => code > 0x20).length;
    if (visibleChars >= 20 && meaningfulChars / visibleChars < 0.18) {
      return true;
    }
    return RegExp(
      r'^(わかりません|場所がわかりません|情報がありません|回答できません|ニュースを教えることはできません)',
    ).hasMatch(normalized.trim());
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

  bool _looksLikeUnusedTokenFragment(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '').trim();
    return RegExp(
      r'^<?unused[_-]?\d+>?$',
      caseSensitive: false,
    ).hasMatch(compact);
  }

  String _answerFromWebSources({
    required String promptText,
    required WebResearchResult webResult,
  }) {
    final isWeather = RegExp(
      r'(天気|気温|雨|weather)',
      caseSensitive: false,
    ).hasMatch(promptText);
    final isNews = RegExp(
      r'(ニュース|news|最新)',
      caseSensitive: false,
    ).hasMatch(promptText);
    final heading = isWeather
        ? '現在地情報とWeb検索結果から天気関連情報をまとめます。'
        : isNews
        ? 'Web検索結果から最新ニュースの要点をまとめます。'
        : 'Web検索結果から確認できた情報をまとめます。';
    final lines = <String>[heading];
    if (webResult.locationContext.trim().isNotEmpty) {
      lines.add('現在地: ${webResult.locationContext.trim()}');
    }
    for (final source in webResult.sources.take(4)) {
      final title = source.title.trim();
      final detail = <String>[
        source.snippet.trim(),
        source.excerpt.trim(),
      ].where((item) => item.isNotEmpty).join(' ');
      final summary = _takeRunes(
        detail.replaceAll(RegExp(r'\s+'), ' ').trim(),
        isWeather ? 160 : 140,
      );
      final url = source.url.trim();
      if (title.isEmpty && summary.isEmpty) {
        continue;
      }
      lines.add(
        '・${title.isEmpty ? summary : title}'
        '${summary.isNotEmpty && summary != title ? ' - $summary' : ''}'
        '${url.isNotEmpty ? '\n  $url' : ''}',
      );
    }
    if (isNews && lines.length == 1) {
      lines.add(
        'ニュース検索を実行しましたが、現在この端末で本文を取得できるソースがありませんでした。'
        '分野を絞らず主要ニュースを取得する方針で再検索します。少し時間を置いてもう一度試してください。',
      );
    }
    if (lines.length == 1 && webResult.locationNotice.trim().isNotEmpty) {
      lines.add(webResult.locationNotice.trim());
    }
    return lines.join('\n');
  }

  String? _placeNameFromPrompt(String promptText) {
    final match = RegExp(
      r'([一-龥ぁ-んァ-ン]{2,}(市|区|町|村|県|府|都|道|駅|大学|会社|施設|病院|学校|公園))',
    ).firstMatch(promptText);
    return match?.group(1);
  }

  bool _looksLikeLowInformationPlaceAnswer(String answer) {
    final normalized = answer.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty || normalized.runes.length <= 32) {
      return true;
    }
    return normalized.contains('どのような情報に興味') ||
        normalized.contains('どのような情報') ||
        normalized.contains('具体的に教えて') ||
        normalized.contains('知りたいことを具体的') ||
        normalized.contains('何かお手伝い') ||
        normalized.contains('どんな情報が知りたい');
  }

  bool _isEmptyBulletLine(String line) {
    return RegExp(r'^([*＊・\-—–•●○#\s])+$').hasMatch(line);
  }

  Future<void> _cancel() async {
    _cancelRequested = true;
    await _genAiRuntime.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = _chatText('停止リクエストを送信しました…', 'Sent stop request...');
    });
  }

  int _responseTokenBudget({
    required String promptText,
    required List<ChatAttachment> attachments,
    required int preflightMaxTokens,
    required _ModelChoice choice,
    int? modelSizeBytes,
  }) {
    final compactPrompt = promptText.replaceAll(RegExp(r'\s+'), '');
    final resolvedModelSizeBytes = modelSizeBytes ?? _loadedModelSizeBytes;
    final isGenAiModel = _isGenAiModelChoice(choice);
    final asksForDetail = RegExp(
      r'詳しく|詳細|説明|解説|なぜ|理由|手順|比較|まとめて|長く',
    ).hasMatch(promptText);
    if (isGenAiModel) {
      final configuredLimit = _genAiOutputLimit(promptText, attachments);
      if (_isObviousLocalOnlyPrompt(promptText) && attachments.isEmpty) {
        return math.min(configuredLimit, 96);
      }
      if (attachments.isNotEmpty) {
        final maxForModel = _isMemoryHeavyGenAiChoice(choice) ? 768 : 1536;
        return (asksForDetail ? maxForModel : maxForModel ~/ 2).clamp(
          128,
          configuredLimit,
        );
      }
      if (compactPrompt.length <= 12 && !asksForDetail) {
        return math.min(configuredLimit, 128);
      }
      if (compactPrompt.length <= 40 && !asksForDetail) {
        return math.min(configuredLimit, 384);
      }
      if (_isMemoryHeavyGenAiChoice(choice)) {
        return (asksForDetail ? 768 : 512).clamp(128, configuredLimit);
      }
      return (asksForDetail ? 1536 : 768).clamp(128, configuredLimit);
    }
    if (resolvedModelSizeBytes != null &&
        resolvedModelSizeBytes >= 4 * 1024 * 1024 * 1024) {
      if (compactPrompt.length <= 12) {
        return preflightMaxTokens.clamp(16, 32);
      }
      if (compactPrompt.length <= 40) {
        return preflightMaxTokens.clamp(24, 64);
      }
      return asksForDetail
          ? preflightMaxTokens.clamp(64, 192)
          : preflightMaxTokens.clamp(32, 96);
    }
    if (resolvedModelSizeBytes != null &&
        resolvedModelSizeBytes >= 300 * 1024 * 1024) {
      if (compactPrompt.length <= 40 && !asksForDetail) {
        return preflightMaxTokens.clamp(48, 96);
      }
      return preflightMaxTokens.clamp(128, 512);
    }
    if (asksForDetail) {
      return preflightMaxTokens.clamp(128, 512);
    }
    if (attachments.isNotEmpty) {
      return preflightMaxTokens.clamp(128, 512);
    }
    if (compactPrompt.length <= 12) {
      return preflightMaxTokens.clamp(64, 256);
    }
    if (compactPrompt.length <= 40) {
      return preflightMaxTokens.clamp(96, 384);
    }
    return preflightMaxTokens.clamp(128, 512);
  }

  int _genAiContextTokensFor(
    _ModelChoice choice, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
    int? requestedMaxTokens,
  }) {
    final base = attachments.isNotEmpty
        ? _multimodalGenAiContextTokens
        : _isMemoryHeavyGenAiChoice(choice)
        ? _heavyGenAiContextTokens
        : _defaultGenAiContextTokens;
    return math.max(base, requestedMaxTokens ?? 0).clamp(512, 4096).toInt();
  }

  int _genAiOutputLimit(String promptText, List<ChatAttachment> attachments) {
    return _genAiConfig.maxTokens.clamp(2000, 10000).toInt();
  }

  bool _isGenAiModelChoice(_ModelChoice? choice) {
    final normalized = choice?.path.toLowerCase();
    return normalized != null && normalized.endsWith('.litertlm');
  }

  bool _shouldCacheGenAiChoice(_ModelChoice choice) {
    return false;
  }

  bool _isMemoryHeavyGenAiChoice(_ModelChoice choice) {
    final value = '${choice.id} ${choice.title} ${choice.path}'.toLowerCase();
    return (value.contains('e4b') && value.endsWith('.litertlm')) ||
        (_loadedModelPath == choice.path &&
            (_loadedModelSizeBytes ?? 0) >= _heavyGenAiModelBytes);
  }

  bool _isUnstableE2bLiteRtChoice(_ModelChoice choice) {
    final value = '${choice.id} ${choice.title} ${choice.path}'.toLowerCase();
    return value.contains('gemma-4-e2b') &&
        choice.path.toLowerCase().endsWith('.litertlm');
  }

  bool _isStableE4bLiteRtChoice(_ModelChoice choice) {
    final value = '${choice.id} ${choice.title} ${choice.path}'.toLowerCase();
    return value.contains('gemma-4-e4b') &&
        choice.path.toLowerCase().endsWith('.litertlm');
  }

  _ModelChoice? _stableGenAiChoice() {
    for (final choice in _modelChoices.where(_isGenAiModelChoice)) {
      if (!_isUnstableE2bLiteRtChoice(choice) &&
          !_isStableE4bLiteRtChoice(choice)) {
        return choice;
      }
    }
    for (final choice in _modelChoices.where(_isGenAiModelChoice)) {
      if (_isUnstableE2bLiteRtChoice(choice)) {
        return choice;
      }
    }
    for (final choice in _modelChoices.where(_isGenAiModelChoice)) {
      if (_isStableE4bLiteRtChoice(choice)) {
        return choice;
      }
    }
    return null;
  }

  int _stableGenAiTopK(_ModelChoice choice) {
    if (_isGenAiModelChoice(choice)) {
      return math.min(_genAiConfig.topK, 8);
    }
    return _genAiConfig.topK;
  }

  double _stableGenAiTopP(_ModelChoice choice) {
    if (_isGenAiModelChoice(choice)) {
      return math.min(_genAiConfig.topP, 0.82);
    }
    return _genAiConfig.topP;
  }

  double _stableGenAiTemperature(_ModelChoice choice) {
    if (_isGenAiModelChoice(choice)) {
      return math.min(_genAiConfig.temperature, 0.2);
    }
    return _genAiConfig.temperature;
  }

  bool _requiresGenAiModel(List<ChatAttachment> attachments) {
    return attachments.any(
      (attachment) =>
          attachment.type == ChatAttachmentType.image ||
          attachment.type == ChatAttachmentType.audio,
    );
  }

  _ModelChoice _resolveGenerationChoice(
    _ModelChoice selectedChoice,
    List<ChatAttachment> attachments,
  ) {
    if (selectedChoice.isSmokeModel) {
      return selectedChoice;
    }
    if (_isGenAiModelChoice(selectedChoice)) {
      return selectedChoice;
    }
    final multimodal = _requiresGenAiModel(attachments);
    if (!multimodal) {
      return selectedChoice;
    }
    final genAiChoices = _modelChoices.where(_isGenAiModelChoice).toList();
    if (genAiChoices.isEmpty) {
      return selectedChoice;
    }
    final preferred =
        _stableGenAiChoice() ??
        genAiChoices.firstWhere((choice) {
          final id = choice.id.toLowerCase();
          final title = choice.title.toLowerCase();
          final path = choice.path.toLowerCase();
          return id.contains('gemma') ||
              title.contains('gemma') ||
              path.contains('gemma');
        }, orElse: () => genAiChoices.first);
    debugPrint(
      'ESSENTIAL_PERF route_to_genai selected=${selectedChoice.id} effective=${preferred.id} multimodal=$multimodal',
    );
    return preferred;
  }

  int _runeLength(String value) {
    return value.runes.length;
  }

  String _takeRunes(String value, int maxCharacters) {
    if (maxCharacters <= 0) {
      return '';
    }
    if (_runeLength(value) <= maxCharacters) {
      return value;
    }
    return String.fromCharCodes(value.runes.take(maxCharacters));
  }

  Future<int?> _modelSizeBytes(String modelPath) async {
    try {
      return await File(modelPath).length();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _runSmokeFlow() async {
    await _chatReady;
    await _chatController.createSession(preferredModelId: _smokeModelId);
    final choice = _resolveSelectedChoice();
    if (choice == null) {
      debugPrint('ESSENTIAL_SMOKE_ERROR=No model available');
      return;
    }

    try {
      await _ensureModelLoaded(choice);
    } catch (_) {}

    if (!mounted || _status.startsWith('モデル準備に失敗')) {
      debugPrint('ESSENTIAL_SMOKE_ERROR=$_status');
      return;
    }

    final prompts = widget.smokePrompts.isNotEmpty
        ? widget.smokePrompts
        : <String>[
            widget.smokePrompt ?? 'Write one short sentence about a red kite.',
          ];
    for (var index = 0; index < prompts.length; index += 1) {
      final prompt = prompts[index].trim();
      if (prompt.isEmpty) {
        continue;
      }
      debugPrint('ESSENTIAL_SMOKE_CASE_START index=$index prompt=$prompt');
      _composerController.text = prompt;
      await _generate(attachments: _smokeAttachments(index));

      if (!mounted) {
        return;
      }

      final messages =
          _chatController.currentSession?.messages ?? <ChatMessage>[];
      final assistantMessages = messages
          .where((message) => message.role == ChatMessageRole.assistant)
          .toList();
      final latestAssistant = assistantMessages.isEmpty
          ? null
          : assistantMessages.last;

      if (_status == '応答が完了しました。' &&
          latestAssistant != null &&
          latestAssistant.text.isNotEmpty) {
        debugPrint(
          'ESSENTIAL_SMOKE_RESULT index=$index text=${latestAssistant.text}',
        );
      } else {
        final partialText = latestAssistant?.text ?? '';
        debugPrint(
          'ESSENTIAL_SMOKE_ERROR index=$index status=$_status partial=$partialText',
        );
        break;
      }
    }
  }

  Future<void> _discoverGenAiModels() async {
    final models = await _genAiRuntime.discoverModels();
    if (!mounted) {
      return;
    }
    setState(() {
      _discoveredGenAiModels = models;
    });
    unawaited(_warmSelectedGenAiModel());
  }

  Future<void> _warmSelectedGenAiModel({bool force = false}) async {
    if (_isGenerating || (_isPreparingModel && !force)) {
      return;
    }
    final choice = _resolveSelectedChoice();
    if (!_isGenAiModelChoice(choice)) {
      return;
    }
    if (!_shouldCacheGenAiChoice(choice!)) {
      return;
    }
    final path = choice.path;
    if (_warmedGenAiPath == path || _warmingGenAiPath == path) {
      return;
    }
    _warmingGenAiPath = path;
    try {
      final warmup = await _genAiRuntime
          .warmUp(
            modelPath: path,
            maxTokens: math.min(_genAiConfig.maxTokens, 1024),
            contextTokens: _genAiContextTokensFor(
              choice,
              requestedMaxTokens: math.min(_genAiConfig.maxTokens, 1024),
            ),
            topK: _stableGenAiTopK(choice),
            topP: _stableGenAiTopP(choice),
            temperature: _stableGenAiTemperature(choice),
            accelerator: _genAiConfig.accelerator,
            visionAccelerator: _genAiConfig.accelerator,
          )
          .timeout(const Duration(seconds: 30));
      _warmedGenAiPath = path;
      debugPrint(
        'ESSENTIAL_PERF genai_warmup_ms=${warmup?.loadAndSetupMs ?? 0} context_tokens=${warmup?.contextTokens ?? _genAiContextTokensFor(choice)} model=${choice.id}',
      );
      if (mounted && !_isGenerating) {
        setState(() {
          _status = _chatText(
            '${choice.title} を高速起動できる状態にしました。',
            '${choice.title} is ready for fast startup.',
          );
        });
      }
    } catch (error) {
      debugPrint('GenAI warmup failed: $error');
    } finally {
      if (_warmingGenAiPath == path) {
        _warmingGenAiPath = null;
      }
    }
  }

  List<ChatAttachment> _smokeAttachments(int index) {
    return <ChatAttachment>[
      for (final path in widget.smokeImagePaths)
        ChatAttachment(
          id: 'smoke-image-$index-$path',
          type: ChatAttachmentType.image,
          filePath: path,
          caption: 'Smoke image',
        ),
      for (final path in widget.smokeAudioPaths)
        ChatAttachment(
          id: 'smoke-audio-$index-$path',
          type: ChatAttachmentType.audio,
          filePath: path,
          caption: 'Smoke audio',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _chatController,
        widget.controller,
        widget.preferencesController,
      ]),
      builder: (context, _) {
        final session = _chatController.currentSession;
        final selectedChoice = _resolveSelectedChoice();
        final selectedAdapter = _resolveSelectedAdapter(selectedChoice);
        final choices = _modelChoices;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.appText('トーク', 'Chat')),
            leading: Builder(
              builder: (context) {
                return IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: context.appText('履歴', 'History'),
                );
              },
            ),
            actions: <Widget>[
              IconButton(
                onPressed: _openLiveFromChat,
                icon: const Icon(Icons.graphic_eq_rounded),
                tooltip: context.appText('Liveで話す', 'Talk in Live'),
              ),
              IconButton(
                onPressed: _showSharedMemorySheet,
                icon: Icon(
                  session?.sharedMemoryEnabled ?? true
                      ? Icons.memory_rounded
                      : Icons.memory_outlined,
                ),
                tooltip: context.appText('共有メモリー', 'Shared memory'),
              ),
              IconButton(
                onPressed: _showGenerationConfigDialog,
                icon: const Icon(Icons.tune_rounded),
                tooltip: context.appText('生成設定', 'Generation settings'),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _webSearchEnabled = !_webSearchEnabled;
                  });
                },
                icon: Icon(
                  _webSearchEnabled
                      ? Icons.travel_explore_rounded
                      : Icons.public_off_rounded,
                ),
                tooltip: _webSearchEnabled
                    ? context.appText('Web検索オン', 'Web search on')
                    : context.appText('Web検索オフ', 'Web search off'),
              ),
              IconButton(
                onPressed: _webSearchEnabled
                    ? () => widget.preferencesController
                          .updateLocationSearchEnabled(!_locationSearchEnabled)
                    : null,
                icon: Icon(
                  _locationSearchEnabled
                      ? Icons.my_location_rounded
                      : Icons.location_disabled_rounded,
                ),
                tooltip: _locationSearchEnabled
                    ? context.appText('位置情報検索オン', 'Location search on')
                    : context.appText('位置情報検索オフ', 'Location search off'),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _autoSpeakResponses = !_autoSpeakResponses;
                  });
                },
                icon: Icon(
                  _autoSpeakResponses
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                ),
                tooltip: _autoSpeakResponses
                    ? context.appText('読み上げオン', 'Speech on')
                    : context.appText('読み上げオフ', 'Speech off'),
              ),
            ],
          ),
          drawer: _ChatHistoryDrawer(
            controller: _chatController,
            fallbackModelId: selectedChoice?.id,
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: session == null
                      ? const SizedBox.shrink()
                      : session.messages.isEmpty
                      ? const SizedBox.shrink()
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is UserScrollNotification ||
                                notification is ScrollUpdateNotification) {
                              _userIsReadingHistory =
                                  notification.metrics.extentAfter > 180;
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            itemCount: session.messages.length,
                            itemBuilder: (context, index) {
                              final message = session.messages[index];
                              return ChatMessageBubble(
                                message: message,
                                pulse: _pulseController,
                              );
                            },
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: ChatInputBar(
                    controller: _composerController,
                    enabled: choices.isNotEmpty && !_isPreparingModel,
                    isGenerating: _isGenerating,
                    modelLabel: selectedChoice?.title ?? 'AIを追加',
                    adapterLabel: selectedAdapter?.displayName,
                    hasAvailableModels: choices.isNotEmpty,
                    onChooseModel: _showModelPicker,
                    onChooseAdapter: () => _showAdapterPicker(selectedChoice),
                    onOpenModels: widget.onOpenModels,
                    onSendText: _generate,
                    onSendMultimodal: (text, attachments) =>
                        _generate(textOverride: text, attachments: attachments),
                    onQuickAction: _runQuickAction,
                    onStop: _cancel,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openLiveFromChat() async {
    await _chatReady;
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceLiveScreen(
          chatController: _chatController,
          modelController: widget.controller,
          preferencesController: widget.preferencesController,
          runtimeHealthController: widget.runtimeHealthController,
          initialModelId: _resolveSelectedChoice()?.id,
        ),
      ),
    );
  }

  Future<void> _runQuickAction(String prompt) async {
    _composerController.text = prompt;
    _composerController.selection = TextSelection.collapsed(
      offset: _composerController.text.length,
    );
    await _generate();
  }

  Future<void> _showGenerationConfigDialog() async {
    var draft = _genAiConfig;
    final result = await showDialog<_GenAiGenerationConfig>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget slider({
              required String label,
              required String value,
              required double current,
              required double min,
              required double max,
              required int divisions,
              required ValueChanged<double> onChanged,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(label)),
                        Text(value),
                      ],
                    ),
                    Slider(
                      value: current.clamp(min, max).toDouble(),
                      min: min,
                      max: max,
                      divisions: divisions,
                      label: value,
                      onChanged: (next) {
                        setDialogState(() => onChanged(next));
                      },
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('Configurations'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      slider(
                        label: 'Max tokens',
                        value: draft.maxTokens.toString(),
                        current: draft.maxTokens.toDouble(),
                        min: 2000,
                        max: 10000,
                        divisions: 80,
                        onChanged: (value) =>
                            draft = draft.copyWith(maxTokens: value.round()),
                      ),
                      slider(
                        label: 'TopK',
                        value: draft.topK.toString(),
                        current: draft.topK.toDouble(),
                        min: 5,
                        max: 64,
                        divisions: 59,
                        onChanged: (value) =>
                            draft = draft.copyWith(topK: value.round()),
                      ),
                      slider(
                        label: 'TopP',
                        value: draft.topP.toStringAsFixed(2),
                        current: draft.topP,
                        min: 0,
                        max: 1,
                        divisions: 100,
                        onChanged: (value) => draft = draft.copyWith(
                          topP: double.parse(value.toStringAsFixed(2)),
                        ),
                      ),
                      slider(
                        label: 'Temperature',
                        value: draft.temperature.toStringAsFixed(2),
                        current: draft.temperature,
                        min: 0,
                        max: 2,
                        divisions: 200,
                        onChanged: (value) => draft = draft.copyWith(
                          temperature: double.parse(value.toStringAsFixed(2)),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Accelerator',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(
                            value: 'gpu',
                            icon: Icon(Icons.memory_rounded),
                            label: Text('GPU'),
                          ),
                          ButtonSegment<String>(
                            value: 'cpu',
                            icon: Icon(Icons.developer_board_rounded),
                            label: Text('CPU'),
                          ),
                        ],
                        selected: <String>{draft.accelerator},
                        onSelectionChanged: (selection) {
                          setDialogState(() {
                            draft = draft.copyWith(
                              accelerator: selection.first,
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(draft),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _isPreparingModel = true;
      _genAiConfig = result.copyWith(
        maxTokens: result.maxTokens.clamp(2000, 10000).toInt(),
        topK: result.topK.clamp(1, 64).toInt(),
      );
      _warmedGenAiPath = null;
      _status = _chatText('生成設定を適用中…', 'Applying generation settings...');
    });
    try {
      await _warmSelectedGenAiModel(force: true);
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingModel = false;
          _status = _chatText('生成設定を更新しました。', 'Updated generation settings.');
        });
      }
    }
  }

  Future<void> _showSharedMemorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: _chatController,
          builder: (context, _) {
            final session = _chatController.currentSession;
            final enabled = session?.sharedMemoryEnabled ?? true;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SwitchListTile(
                      value: enabled,
                      onChanged: (value) {
                        unawaited(
                          _chatController.setCurrentSharedMemoryEnabled(value),
                        );
                      },
                      secondary: const Icon(Icons.memory_rounded),
                      title: Text(
                        context.appText(
                          'このチャットで共有メモリーを使う',
                          'Use shared memory in this chat',
                        ),
                      ),
                      subtitle: Text(
                        context.appText(
                          'OFFにすると、このチャットでは共有メモリーの読み込みも書き込みも行いません。',
                          'When off, this chat will neither read from nor write to shared memory.',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            enabled
                                ? Icons.check_circle_rounded
                                : Icons.block_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              enabled
                                  ? context.appText(
                                      'このチャットの会話要約を端末内AIで共有メモリーへ反映します。',
                                      'On-device AI will reflect this chat summary into shared memory.',
                                    )
                                  : context.appText(
                                      'このチャット内では共有メモリーを使いません。',
                                      'This chat will not use shared memory.',
                                    ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_ModelChoice> get _modelChoices {
    final items = <_ModelChoice>[];
    final seenPaths = <String>{};
    for (final record in _chatModelRecords) {
      final genAiReplacement = _preferredGenAiModelFor(record.modelId);
      final effectivePath = genAiReplacement?.path ?? record.activePath;
      if (!_isLiteRtLmPath(effectivePath)) {
        continue;
      }
      final effectiveSizeBytes =
          genAiReplacement?.sizeBytes ?? record.sizeBytes;
      if (!seenPaths.add(effectivePath)) {
        continue;
      }
      items.add(
        _ModelChoice(
          id: record.modelId,
          adapterModelId: record.modelId,
          title: _friendlyChatModelTitle(record.modelId, record.displayName),
          subtitle: genAiReplacement == null
              ? 'チャットAI · ${_formatBytes(record.sizeBytes)}'
              : 'LiteRT-LM · ${_formatBytes(effectiveSizeBytes)}',
          path: effectivePath,
          isSmokeModel: false,
        ),
      );
    }

    for (final bundle in widget.controller.installedBundles) {
      for (final componentId in bundle.componentModelIds) {
        final component = widget.controller.componentInstallationFor(
          componentId,
        );
        if (component == null || !_isChatBundleComponent(component)) {
          continue;
        }
        final genAiReplacement = _preferredGenAiModelFor(component.modelId);
        final effectivePath = genAiReplacement?.path ?? component.activePath;
        if (!_isLiteRtLmPath(effectivePath)) {
          continue;
        }
        final effectiveSizeBytes =
            genAiReplacement?.sizeBytes ?? component.sizeBytes;
        if (!seenPaths.add(effectivePath)) {
          continue;
        }
        items.add(
          _ModelChoice(
            id: 'bundle:${bundle.bundleId}:${component.modelId}',
            adapterModelId: _adapterModelIdForComponent(component.modelId),
            title: _friendlyChatBundleTitle(
              bundle.displayName,
              component.modelId,
            ),
            subtitle:
                '${_friendlyChatModelTitle(component.modelId, component.modelId)} · ${genAiReplacement == null ? '機能セット' : 'LiteRT-LM ${_formatBytes(effectiveSizeBytes)}'}',
            path: effectivePath,
            isSmokeModel: false,
          ),
        );
      }
    }

    for (final model in _discoveredGenAiModels) {
      if (!seenPaths.add(model.path)) {
        continue;
      }
      items.add(
        _ModelChoice(
          id: model.id,
          adapterModelId: model.id,
          title: model.title.isEmpty ? 'Local GenAI model' : model.title,
          subtitle: 'LiteRT-LM · ${_formatBytes(model.sizeBytes)}',
          path: model.path,
          isSmokeModel: false,
        ),
      );
    }

    items.sort(
      (left, right) =>
          _modelChoicePriority(left).compareTo(_modelChoicePriority(right)),
    );

    if (widget.smokeModelPath != null) {
      items.insert(
        0,
        _ModelChoice(
          id: _smokeModelId,
          adapterModelId: _smokeModelId,
          title: 'Smoke model',
          subtitle: _modelPathController.text,
          path: _modelPathController.text,
          isSmokeModel: true,
        ),
      );
    }

    return items;
  }

  int _modelChoicePriority(_ModelChoice choice) {
    final value = '${choice.id} ${choice.title} ${choice.path}'.toLowerCase();
    if (value.contains('gemma-4-e2b') && value.endsWith('.litertlm')) {
      return 0;
    }
    if (value.contains('gemma-4-e2b')) {
      return 1;
    }
    if (value.contains('gemma-4-e4b') && value.endsWith('.litertlm')) {
      return 8;
    }
    if (value.contains('gemma-4-e4b')) {
      return 9;
    }
    if (value.contains('essential-mini')) {
      return 10;
    }
    return 5;
  }

  EssentialGenAiModel? _preferredGenAiModelFor(String modelId) {
    final normalizedModelId = modelId.toLowerCase();
    final target = switch (normalizedModelId) {
      'gemma-4-e2b-it' || 'gemma-4-e2b-litertlm-it' => 'gemma-4-e2b-it',
      'gemma-4-e4b-it' || 'gemma-4-e4b-litertlm-it' => 'gemma-4-e4b-it',
      _ => null,
    };
    if (target == null) {
      return null;
    }
    for (final model in _discoveredGenAiModels) {
      final normalizedPath = model.path.toLowerCase();
      if (normalizedPath.contains(target) &&
          normalizedPath.endsWith('.litertlm')) {
        return model;
      }
    }
    return null;
  }

  _ModelChoice? _resolveSelectedChoice() {
    final session = _chatController.currentSession;
    final choices = _modelChoices;
    if (choices.isEmpty) {
      return null;
    }

    final selectedModelId = session?.selectedModelId;
    if (selectedModelId != null) {
      for (final choice in choices) {
        if (choice.id == selectedModelId) {
          return choice;
        }
      }
    }

    return choices.first;
  }

  InstalledAdapterRecord? _resolveSelectedAdapter(_ModelChoice? choice) {
    if (choice == null || _selectedAdapterId == null) {
      return null;
    }
    final adapter = widget.controller.adapterInstallationFor(
      _selectedAdapterId!,
    );
    if (adapter == null || adapter.baseModelId != choice.adapterModelId) {
      return null;
    }
    return adapter;
  }

  bool _isChatBundleComponent(InstalledBundleComponentRecord component) {
    return _isSupportedChatModelId(component.modelId) &&
        component.type == 'base' &&
        (component.format == 'litertlm' ||
            _isLiteRtLmPath(component.activePath));
  }

  String _adapterModelIdForComponent(String componentModelId) {
    const suffix = '-base';
    if (componentModelId.endsWith(suffix)) {
      return componentModelId.substring(
        0,
        componentModelId.length - suffix.length,
      );
    }
    return componentModelId;
  }

  void _handleInventoryChanged() {
    if (!_chatController.isReady) {
      return;
    }

    final session = _chatController.currentSession;
    final choices = _modelChoices;
    if (choices.isEmpty) {
      if (session?.selectedModelId != null) {
        _chatController.clearUnavailableCurrentModel();
      }
      return;
    }

    final hasSelectedChoice = choices.any(
      (choice) => choice.id == session?.selectedModelId,
    );
    if (!hasSelectedChoice) {
      _chatController.updateCurrentModel(choices.first.id);
    }
    unawaited(_warmSelectedGenAiModel());
  }

  Future<String?> _handleFailureFallback({
    required String currentModelId,
    required String currentModelPath,
  }) async {
    final fallbackCandidates = _chatModelRecords
        .where((record) => record.activePath != currentModelPath)
        .toList();
    final fallback = widget.runtimeHealthController.pickFallbackInstalledModel(
      currentModelId: currentModelId,
      catalog: widget.controller.catalog,
      installedModels: fallbackCandidates,
    );
    if (fallback == null) {
      return null;
    }
    if (!_isHighAccuracyModelId(currentModelId) ||
        !await _confirmFallbackSwitch(
          message: '高精度AIの生成に失敗しました。このままでは端末が重くなる可能性があります。',
          fallbackModelName: fallback.displayName,
        )) {
      return '高精度AIのまま停止しました。端末が落ち着いてから再試行するか、手動で軽量モデルへ切り替えてください。';
    }
    _selectedAdapterId = null;
    await _chatController.updateCurrentModel(fallback.modelId);
    return '軽量モデル ${fallback.displayName} へ切り替えました。もう一度送信すると graceful degradation で再開できます。';
  }

  bool _isHighAccuracyModelId(String modelId) {
    final normalized = modelId.toLowerCase();
    return normalized.contains('e4b') && normalized.contains('litertlm');
  }

  Future<bool> _confirmFallbackSwitch({
    required String message,
    String? fallbackModelName,
  }) async {
    if (!mounted) {
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(
                context.appText('軽量モデルへ切り替えますか？', 'Switch to a lighter model?'),
              ),
              content: Text(
                context.appUsesEnglish
                    ? '$message\n\nSwitch target: ${fallbackModelName ?? 'an available lighter model'}'
                    : '$message\n\n切り替え先: ${fallbackModelName ?? '利用可能な軽量モデル'}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.appText('このまま停止', 'Stop')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(context.appText('切り替える', 'Switch')),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<List<ChatAttachment>> _enrichAttachments(
    List<ChatAttachment> attachments,
  ) async {
    final enriched = <ChatAttachment>[];
    for (final attachment in attachments) {
      switch (attachment.type) {
        case ChatAttachmentType.image:
          enriched.add(await _enrichImageAttachment(attachment));
        case ChatAttachmentType.audio:
          enriched.add(await _enrichAudioAttachment(attachment));
        case ChatAttachmentType.location:
          enriched.add(attachment);
      }
    }
    return enriched;
  }

  Future<ChatAttachment> _enrichImageAttachment(
    ChatAttachment attachment,
  ) async {
    return _copyAttachment(
      attachment,
      status: ChatAttachmentStatus.complete,
      progress: 1,
      analysisLabels: const <String>['画像を添付しました'],
    );
  }

  Future<ChatAttachment> _enrichAudioAttachment(
    ChatAttachment attachment,
  ) async {
    return _copyAttachment(
      attachment,
      status: ChatAttachmentStatus.complete,
      progress: 1,
      transcription:
          'この提出ビルドでは、録音ファイルの自動文字起こしではなく端末内SpeechRecognizerによるライブ音声入力を使用します。',
    );
  }

  Future<void> _speakIfEnabled(String text) async {
    final normalized = text.trim();
    if (!_autoSpeakResponses || normalized.isEmpty) {
      return;
    }
    await _speakWithNativeTts(normalized);
  }

  Future<void> _speakWithNativeTts(String text) async {
    try {
      await _nativeVoiceChannel.invokeMethod<void>('speak', <String, Object?>{
        'text': text,
        'language': _ttsLanguageForText(text),
      });
    } catch (_) {}
  }

  String _ttsLanguageForText(String text) {
    final asciiLetters = RegExp(r'[A-Za-z]').allMatches(text).length;
    final japanese = RegExp(
      r'[\u3040-\u30ff\u3400-\u9fff]',
    ).allMatches(text).length;
    return asciiLetters > japanese * 2 ? 'en-US' : 'ja-JP';
  }

  ChatAttachment _copyAttachment(
    ChatAttachment attachment, {
    String? caption,
    String? transcription,
    List<String>? analysisLabels,
    List<String>? detectedObjects,
    double? progress,
    ChatAttachmentStatus? status,
  }) {
    return ChatAttachment(
      id: attachment.id,
      type: attachment.type,
      filePath: attachment.filePath,
      location: attachment.location,
      caption: caption ?? attachment.caption,
      transcription: transcription ?? attachment.transcription,
      analysisLabels: analysisLabels ?? attachment.analysisLabels,
      detectedObjects: detectedObjects ?? attachment.detectedObjects,
      progress: progress ?? attachment.progress,
      status: status ?? attachment.status,
    );
  }

  String _newRequestId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  List<InstalledModelRecord> get _chatModelRecords {
    return widget.controller.installedModels.where(_isChatModelRecord).toList();
  }

  bool _isChatModelRecord(InstalledModelRecord record) {
    if (!_isSupportedChatModelId(record.modelId)) {
      return false;
    }
    return _isLiteRtLmPath(record.activePath);
  }

  bool _isLiteRtLmPath(String path) => path.toLowerCase().endsWith('.litertlm');

  void _scheduleScrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final nearBottom = position.extentAfter < 180;
      if (!force && _userIsReadingHistory && !nearBottom) {
        return;
      }
      _scrollController.animateTo(
        position.maxScrollExtent + 96,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      _userIsReadingHistory = false;
    });
  }

  Future<void> _showModelPicker() async {
    final selected = _resolveSelectedChoice();
    final picked = await showModalBottomSheet<_ModelChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final choices = _modelChoices;
        if (choices.isEmpty) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.appText(
                      '使えるチャットAIがありません',
                      'No chat AI is available',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.appText(
                      'AI追加画面でチャットAIを使えるようにすると、ここで切り替えできます。',
                      'Enable a chat AI from Add AI, then switch it here.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenModels();
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: Text(context.appText('AIを追加', 'Add AI')),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                child: Text(
                  context.appText('使うAIを選ぶ', 'Choose AI'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final choice in choices) ...<Widget>[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tileColor: selected?.id == choice.id
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  leading: Icon(
                    choice.isSmokeModel
                        ? Icons.science_rounded
                        : Icons.auto_awesome_rounded,
                  ),
                  title: Text(choice.title),
                  subtitle: Text(choice.subtitle),
                  trailing: selected?.id == choice.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(choice),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );

    if (picked == null) {
      return;
    }

    await _chatController.updateCurrentModel(picked.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = context.appUsesEnglish
          ? 'Switched to ${picked.title}.'
          : '${picked.title} にしました。';
      if (_resolveSelectedAdapter(picked) == null) {
        _selectedAdapterId = null;
      }
    });
    unawaited(_warmSelectedGenAiModel());
  }

  Future<void> _showAdapterPicker(_ModelChoice? choice) async {
    if (choice == null || choice.isSmokeModel) {
      return;
    }
    final adapters = widget.controller.installedAdaptersForModel(
      choice.adapterModelId,
    );
    if (adapters.isEmpty) {
      setState(() {
        _status = context.appUsesEnglish
            ? 'No installed adapter is available for ${choice.title}. Download a compatible adapter in model management.'
            : '${choice.title} に使えるインストール済み adapter がありません。モデル管理で対応 adapter をダウンロードしてください。';
      });
      return;
    }

    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                title: Text(context.appText('Adapterなし', 'No adapter')),
                subtitle: Text(
                  context.appText(
                    'ベースモデルのみで推論',
                    'Run with the base model only',
                  ),
                ),
                trailing: _selectedAdapterId == null
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(null),
              ),
              for (final adapter in adapters)
                ListTile(
                  title: Text(adapter.displayName),
                  subtitle: Text(
                    '${adapter.namespaceId} · ${adapter.compatibleQuantizations.join(", ")}',
                  ),
                  trailing: _selectedAdapterId == adapter.adapterId
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(adapter.adapterId),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedAdapterId = picked;
      _status = picked == null
          ? context.appText(
              'ベースモデルのみで推論します。',
              'Running with the base model only.',
            )
          : context.appText(
              'Adapter を次回推論に適用します。',
              'The adapter will be applied on the next inference.',
            );
    });
  }
}

const _smokeModelId = '__smoke_model__';

class _GenAiGenerationConfig {
  const _GenAiGenerationConfig({
    this.maxTokens = 4000,
    this.topK = 64,
    this.topP = 0.95,
    this.temperature = 1.0,
    this.accelerator = 'gpu',
  });

  final int maxTokens;
  final int topK;
  final double topP;
  final double temperature;
  final String accelerator;

  _GenAiGenerationConfig copyWith({
    int? maxTokens,
    int? topK,
    double? topP,
    double? temperature,
    String? accelerator,
  }) {
    return _GenAiGenerationConfig(
      maxTokens: maxTokens ?? this.maxTokens,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      temperature: temperature ?? this.temperature,
      accelerator: accelerator ?? this.accelerator,
    );
  }
}

class _PromptPlan {
  const _PromptPlan({
    required this.query,
    required this.shouldUseWeb,
    required this.shouldUseLocation,
  });

  final String query;
  final bool shouldUseWeb;
  final bool shouldUseLocation;
}

class _ModelChoice {
  const _ModelChoice({
    required this.id,
    required this.adapterModelId,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.isSmokeModel,
  });

  final String id;
  final String adapterModelId;
  final String title;
  final String subtitle;
  final String path;
  final bool isSmokeModel;
}

class _ChatHistoryDrawer extends StatelessWidget {
  const _ChatHistoryDrawer({
    required this.controller,
    required this.fallbackModelId,
  });

  final ChatController controller;
  final String? fallbackModelId;

  @override
  Widget build(BuildContext context) {
    final current = controller.currentSession;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.appText('チャット履歴', 'Chat history'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: () async {
                  await controller.createSession(
                    preferredModelId: fallbackModelId,
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.add_comment_rounded),
                label: Text(context.appText('新しいチャット', 'New chat')),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: controller.sessions.map((session) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: session.id == current?.id
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        session.messages.isEmpty
                            ? 'まだメッセージはありません'
                            : '${session.messages.length} メッセージ',
                      ),
                      onTap: () async {
                        await controller.selectSession(session.id);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      trailing: IconButton(
                        onPressed: () async {
                          await controller.deleteSession(
                            session.id,
                            fallbackModelId: fallbackModelId,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyChatModelTitle(String modelId, String fallback) {
  if (modelId == 'gemma-4-e4b-it') {
    return '高精度チャットAI';
  }
  if (modelId == 'gemma-4-e4b-litertlm-it') {
    return '高精度スマホ最適化チャットAI';
  }
  if (modelId == 'gemma-3n-e4b-it') {
    return '高精度マルチモーダルAI';
  }
  if (modelId == 'gemma-3n-e2b-it') {
    return '軽量マルチモーダルAI';
  }
  if (modelId == 'gemma-4-e2b-it') {
    return '軽めのチャットAI';
  }
  if (modelId == 'gemma-4-e2b-litertlm-it') {
    return 'スマホ最適化チャットAI';
  }
  if (modelId == 'essential-mini') {
    return '省スペースAI';
  }
  return fallback;
}

bool _isSupportedChatModelId(String modelId) {
  return modelId == 'essential-mini' ||
      modelId == 'gemma-3n-e2b-it' ||
      modelId == 'gemma-3n-e4b-it' ||
      modelId == 'gemma-4-e2b-it' ||
      modelId == 'gemma-4-e2b-litertlm-it' ||
      modelId == 'gemma-4-e4b-litertlm-it' ||
      modelId == 'gemma-4-e4b-it';
}

String _friendlyChatBundleTitle(String displayName, String modelId) {
  if (modelId == 'gemma-4-e4b-it') {
    return '高精度チャットセット';
  }
  if (modelId == 'gemma-4-e4b-litertlm-it') {
    return '高精度スマホ最適化チャットセット';
  }
  if (modelId == 'gemma-4-e2b-it') {
    return '軽めのチャットセット';
  }
  if (modelId == 'gemma-4-e2b-litertlm-it') {
    return 'スマホ最適化チャットセット';
  }
  if (modelId == 'essential-mini') {
    return 'お試しチャットセット';
  }
  return displayName;
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 MB';
  }
  final megabytes = bytes / (1024 * 1024);
  if (megabytes >= 1024) {
    return '${(megabytes / 1024).toStringAsFixed(1)} GB';
  }
  return '${megabytes.toStringAsFixed(1)} MB';
}
