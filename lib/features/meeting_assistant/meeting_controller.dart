import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:essential_sdk_dart/essential_sdk_dart.dart' as essential;
import '../../app/app_language.dart';
import '../../app/app_preferences_controller.dart';
import 'meeting_models.dart';
import '../chat/chat_controller.dart';
import '../model_management/model_management_controller.dart';
import '../shared/audio_tools_service.dart';
import '../shared/web_research_service.dart';
import 'meeting_enhancements.dart';

class MeetingController extends ChangeNotifier {
  MeetingController({
    required this.modelController,
    ChatController? chatController,
    this.preferencesController,
  }) : chatController = chatController ?? ChatController(),
       super();

  final ModelManagementController modelController;
  final ChatController chatController;
  final AppPreferencesController? preferencesController;
  final AudioRecorder _micRecorder = AudioRecorder();
  static const MethodChannel _internalAudioChannel = MethodChannel(
    'essential/internal_audio',
  );
  static const MethodChannel _screenCaptureChannel = MethodChannel(
    'essential/screen_capture',
  );
  static const MethodChannel _meetingProcessingChannel = MethodChannel(
    'essential/meeting_processing',
  );
  static const MethodChannel _shareChannel = MethodChannel('essential/share');

  final essential.EssentialAudioRuntime _audioRuntime =
      essential.EssentialAudioRuntime();
  final essential.EssentialGenAiRuntime _genAiRuntime =
      essential.EssentialGenAiRuntime();
  final AudioToolsService _audioTools = const AudioToolsService();
  final WebResearchService _webResearch = WebResearchService();
  static const int _meetingContextTokens = 2048;
  static const int _meetingPromptTranscriptRunes = 2800;
  static const int _meetingTranscriptChunkRunes = 2400;
  static const int _meetingChunkSummaryRunes = 900;
  static const Duration _meetingAudioChunkDuration = Duration(minutes: 5);
  static const int _longMeetingAudioBytes = 48 * 1024 * 1024;

  essential.EssentialGenAiRuntime getGenAiRuntime() => _genAiRuntime;

  @visibleForTesting
  List<String> debugFormatTranscriptChunksForPrompt(
    List<MeetingTranscriptSegment> segments,
    String fallback,
  ) {
    return _formatTranscriptChunksForPrompt(segments, fallback);
  }

  @visibleForTesting
  Map<String, String> debugTranslationTargets() => _translationTargets();

  @visibleForTesting
  String debugPrimaryTranslationKey() => _primaryTranslationKey();

  bool _isReady = false;
  bool _isLoading = false;
  File? _storageFile;
  File? _speakerProfilesFile;
  List<MeetingSession> _sessions = <MeetingSession>[];
  List<String> _folders = <String>[];
  Map<String, String> _speakerProfileLabels = <String, String>{};
  final Set<String> _activeProcessingSessionIds = <String>{};

  bool get isReady => _isReady;
  bool get isLoading => _isLoading;
  List<MeetingSession> get sessions => List.unmodifiable(_sessions);
  List<String> get folders => List.unmodifiable(_folders);
  List<MeetingSummaryTemplate> get summaryTemplates =>
      MeetingTextProcessor.templates;
  bool get useEnglish => preferencesController?.useEnglish ?? false;
  AppLanguagePack get strings =>
      preferencesController?.languagePack ??
      const AppLanguagePack('ja', <String, String>{});

  Future<void> initialize() async {
    if (_isReady || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    final dir = await getApplicationSupportDirectory();
    _storageFile = File(path.join(dir.path, 'essential_meetings.json'));
    _speakerProfilesFile = File(
      path.join(dir.path, 'essential_meeting_speakers.json'),
    );

    await _loadSessions();
    await _loadSpeakerProfiles();

    await modelController.initialize();
    await chatController.initialize();
    await _audioRuntime.initialize();
    _isLoading = false;
    _isReady = true;
    notifyListeners();

    _resumeInterruptedProcessingSessions();
  }

  Future<void> _persist() async {
    if (_storageFile == null) return;
    await _storageFile!.parent.create(recursive: true);
    final data = <String, dynamic>{
      'sessions': _sessions.map((e) => e.toJson()).toList(),
      'folders': _folders,
    };
    final tempFile = File(
      '${_storageFile!.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tempFile.writeAsString(jsonEncode(data), flush: true);
    await tempFile.rename(_storageFile!.path);
  }

  Future<void> _loadSessions() async {
    final storageFile = _storageFile;
    if (storageFile == null || !await storageFile.exists()) return;
    try {
      final raw = utf8.decode(
        await storageFile.readAsBytes(),
        allowMalformed: true,
      );
      final jsonText = _extractFirstJsonObject(raw);
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final list = data['sessions'] as List<dynamic>? ?? <dynamic>[];
      _sessions =
          list
              .map((e) => MeetingSession.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final storedFolders = (data['folders'] as List<dynamic>? ?? <dynamic>[])
          .map((row) => row.toString().trim())
          .where((row) => row.isNotEmpty)
          .toSet();
      final sessionFolders = _sessions
          .map((session) => session.folderId.trim())
          .where((folder) => folder.isNotEmpty);
      _folders = <String>{...storedFolders, ...sessionFolders}.toList()..sort();
      if (jsonText != raw) {
        await _persist();
      }
    } catch (e) {
      debugPrint('Error loading meetings: $e');
    }
  }

  Future<void> _loadSpeakerProfiles() async {
    final file = _speakerProfilesFile;
    if (file == null || !await file.exists()) return;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _speakerProfileLabels = Map<String, String>.from(
        data['labels'] as Map<String, dynamic>? ?? <String, dynamic>{},
      );
    } catch (error) {
      debugPrint('Error loading meeting speaker profiles: $error');
    }
  }

  Future<void> _persistSpeakerProfiles() async {
    final file = _speakerProfilesFile;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tempFile.writeAsString(
      jsonEncode(<String, Object?>{'labels': _speakerProfileLabels}),
      flush: true,
    );
    await tempFile.rename(file.path);
  }

  String _extractFirstJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) {
      throw const FormatException('Meeting storage has no JSON object.');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < raw.length; i++) {
      final codeUnit = raw.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (codeUnit == 0x5c) {
          escaped = true;
        } else if (codeUnit == 0x22) {
          inString = false;
        }
        continue;
      }
      if (codeUnit == 0x22) {
        inString = true;
      } else if (codeUnit == 0x7b) {
        depth++;
      } else if (codeUnit == 0x7d) {
        depth--;
        if (depth == 0) {
          return raw.substring(start, i + 1);
        }
      }
    }
    throw const FormatException('Meeting storage JSON object is incomplete.');
  }

  void _resumeInterruptedProcessingSessions() {
    final processingSessions = _sessions
        .where((session) => session.status == MeetingStatus.processing)
        .toList(growable: false);
    for (final session in processingSessions) {
      _setProcessingStage(
        session.id,
        strings.t('meeting.stage.resuming'),
        strings.t('meeting.stage.resumingDetail'),
      );
      unawaited(_processSession(session.id));
    }
  }

  void _updateSession(
    String id,
    MeetingSession Function(MeetingSession) updater,
  ) {
    final index = _sessions.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sessions[index] = updater(_sessions[index]);
      notifyListeners();
      _persist();
    }
  }

  void _setProcessingStage(String id, String stage, [String detail = '']) {
    _updateSession(
      id,
      (session) =>
          session.copyWith(processingStage: stage, processingDetail: detail),
    );
    unawaited(_startBackgroundProcessing(stage, detail));
  }

  Future<void> _startBackgroundProcessing(String stage, String detail) async {
    try {
      await _meetingProcessingChannel.invokeMethod<void>(
        'start',
        <String, Object?>{'stage': stage, 'detail': detail},
      );
    } catch (error) {
      debugPrint('Meeting foreground service start error: $error');
    }
  }

  Future<void> _stopBackgroundProcessingIfIdle() async {
    if (_sessions.any(
      (session) => session.status == MeetingStatus.processing,
    )) {
      return;
    }
    try {
      await _meetingProcessingChannel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Meeting foreground service stop error: $error');
    }
  }

  Future<void> _notifyProcessingFinished(MeetingSession session) async {
    try {
      await _meetingProcessingChannel.invokeMethod<void>(
        'complete',
        <String, Object?>{'title': session.title, 'sessionId': session.id},
      );
    } catch (error) {
      debugPrint('Meeting completion notification error: $error');
    }
  }

  Future<void> _notifyProcessingFailed(String detail) async {
    try {
      await _meetingProcessingChannel.invokeMethod<void>(
        'failed',
        <String, Object?>{'detail': detail},
      );
    } catch (error) {
      debugPrint('Meeting failure notification error: $error');
    }
  }

  Future<void> startMicRecording() async {
    if (!await _micRecorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final file = path.join(
      dir.path,
      'meeting_mic_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await _micRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: file,
    );
  }

  Future<String?> stopMicRecording() async {
    return await _micRecorder.stop();
  }

  Future<bool> startInternalRecording() async {
    try {
      final perm = await _screenCaptureChannel.invokeMethod<bool>(
        'requestPermission',
      );
      if (perm != true) return false;
      await _internalAudioChannel.invokeMethod<void>('start');
      return true;
    } catch (e) {
      debugPrint('Internal audio start error: $e');
      return false;
    }
  }

  Future<String?> stopInternalRecording() async {
    try {
      return await _internalAudioChannel.invokeMethod<String>('stop');
    } catch (e) {
      debugPrint('Internal audio stop error: $e');
      return null;
    }
  }

  Future<void> importMeetingAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        unawaited(processMeeting(path, false, recordingSource: 'import'));
      }
    } catch (e) {
      debugPrint('File pick error: $e');
    }
  }

  Future<void> processMeeting(
    String audioPath,
    bool isInternal, {
    String? recordingSource,
    String? initialTranscription,
    List<MeetingBookmark> initialBookmarks = const <MeetingBookmark>[],
  }) async {
    final session = MeetingSession(
      id: 'meeting-${DateTime.now().millisecondsSinceEpoch}',
      title: '処理中の会議...',
      createdAt: DateTime.now(),
      audioPath: audioPath,
      status: MeetingStatus.processing,
      isInternalAudio: isInternal,
      recordingSource:
          recordingSource ?? (isInternal ? 'internal_audio' : 'mic'),
      sharedMemoryEnabled: chatController.currentSharedMemoryEnabled,
      processingStage: '音声準備中',
      processingDetail: '会議音声を解析しやすい形式へ変換しています',
      transcription: initialTranscription?.trim() ?? '',
      bookmarks: initialBookmarks,
    );
    _sessions = <MeetingSession>[session, ..._sessions];
    notifyListeners();
    await _persist();

    unawaited(_processSession(session.id));
  }

  Future<void> setSharedMemoryEnabled(String sessionId, bool enabled) async {
    _updateSession(
      sessionId,
      (session) => session.copyWith(sharedMemoryEnabled: enabled),
    );
    await _persist();
  }

  List<MeetingSearchResult> searchMeetings(String query) {
    return MeetingTextProcessor.search(_sessions, query);
  }

  Future<void> setSessionTemplate(String sessionId, String templateId) async {
    final template = MeetingTextProcessor.templateById(templateId);
    _updateSession(
      sessionId,
      (session) => session.copyWith(
        templateId: templateId,
        templateOutputs: <String, String>{
          ...session.templateOutputs,
          templateId: '${template.title}を生成しています...',
        },
      ),
    );
    await _persist();
    final session = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw StateError('Meeting session not found: $sessionId'),
    );
    try {
      final output = await _generateTemplateOutput(session, template);
      _updateSession(
        sessionId,
        (latest) => latest.copyWith(
          templateOutputs: <String, String>{
            ...latest.templateOutputs,
            templateId: output,
          },
        ),
      );
    } catch (error) {
      final fallback = MeetingTextProcessor.templateOutput(template, session);
      _updateSession(
        sessionId,
        (latest) => latest.copyWith(
          templateOutputs: <String, String>{
            ...latest.templateOutputs,
            templateId: 'テンプレート生成に失敗しました。既存内容から暫定整理しています。\n\n$fallback',
          },
        ),
      );
    }
    await _persist();
  }

  Future<void> setSessionFolder(String sessionId, String folderId) async {
    final cleanFolderId = folderId.trim();
    if (cleanFolderId.isNotEmpty) {
      _rememberFolder(cleanFolderId);
    }
    _updateSession(
      sessionId,
      (session) => session.copyWith(folderId: cleanFolderId),
    );
    await _persist();
  }

  Future<void> createFolder(String folderId) async {
    final cleanFolderId = folderId.trim();
    if (cleanFolderId.isEmpty) {
      return;
    }
    _rememberFolder(cleanFolderId);
    await _persist();
  }

  void _rememberFolder(String folderId) {
    if (_folders.contains(folderId)) {
      return;
    }
    _folders = <String>[..._folders, folderId]..sort();
    notifyListeners();
  }

  Future<void> setSessionTags(String sessionId, List<String> tags) async {
    final normalized = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    _updateSession(sessionId, (session) => session.copyWith(tags: normalized));
    await _persist();
  }

  Future<void> regenerateTranslations(
    String sessionId, {
    String summaryOverride = '',
  }) async {
    final session = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw StateError('Meeting session not found: $sessionId'),
    );
    final summaryText = _bestSummaryForTranslation(session, summaryOverride);
    if (summaryText.trim().isEmpty) {
      throw StateError(
        useEnglish ? 'There is no summary to translate.' : '翻訳する要約がありません。',
      );
    }
    final model = _preferredChatModel();
    final translations = await _generateMeetingTranslations(
      model,
      summaryText,
      sessionId: sessionId,
      current: const <String, String>{},
    );
    _updateSession(
      sessionId,
      (latest) => latest.copyWith(
        translation: translations[_primaryTranslationKey()],
        translations: translations,
        processingStage: strings.t('meeting.stage.complete'),
        processingDetail: '',
      ),
    );
    await _persist();
  }

  Future<void> addBookmark(
    String sessionId,
    double startSeconds, {
    String label = '重要',
    String note = '',
  }) async {
    _updateSession(
      sessionId,
      (session) => session.copyWith(
        bookmarks: <MeetingBookmark>[
          ...session.bookmarks,
          MeetingBookmark(
            id: 'bookmark-${DateTime.now().microsecondsSinceEpoch}',
            startSeconds: startSeconds,
            label: label,
            note: note,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    await _persist();
  }

  Future<void> setAudioOptions(
    String sessionId,
    MeetingAudioOptions options,
  ) async {
    _updateSession(
      sessionId,
      (session) => session.copyWith(audioOptions: options),
    );
    await _persist();
  }

  Future<void> toggleTodo(String sessionId, String todoId) async {
    _updateSession(
      sessionId,
      (session) => session.copyWith(
        todoItems: session.todoItems
            .map(
              (item) => item.id == todoId
                  ? item.copyWith(completed: !item.completed)
                  : item,
            )
            .toList(growable: false),
      ),
    );
    await _persist();
  }

  Future<void> _processSession(String sessionId) async {
    if (!_activeProcessingSessionIds.add(sessionId)) {
      debugPrint(
        'Meeting processing skipped: session already active $sessionId',
      );
      return;
    }
    try {
      final session = _sessions.firstWhere(
        (s) => s.id == sessionId,
        orElse: () => throw StateError('Meeting session not found: $sessionId'),
      );
      await _startBackgroundProcessing(
        session.processingStage.isEmpty ? '会議を処理中' : session.processingStage,
        session.processingDetail.isEmpty
            ? 'バックグラウンドで処理を続けています'
            : session.processingDetail,
      );
      _setProcessingStage(sessionId, '音声変換中', 'Whisper用の16kHz WAVへ変換しています');
      final normalizedAudioPath = await _audioTools.normalizeToSpeechWav(
        session.audioPath,
      );
      final audioChunks = await _splitMeetingAudio(normalizedAudioPath);
      final isLongMeeting =
          audioChunks.length > 1 ||
          File(normalizedAudioPath).lengthSync() > _longMeetingAudioBytes;
      _setProcessingStage(
        sessionId,
        '音声補正中',
        isLongMeeting ? '長時間会議のため重い音声補正を省略しています' : '声を聞き取りやすくし、無音区間を解析しています',
      );
      final processedAudioPath = isLongMeeting
          ? normalizedAudioPath
          : await _preprocessMeetingAudio(
              normalizedAudioPath,
              session.audioOptions,
            );
      final processedAudioChunks = isLongMeeting
          ? audioChunks
          : <String>[processedAudioPath];
      final audioAnalysis = isLongMeeting
          ? const <String, Object?>{}
          : await _safeAnalyzeAudio(processedAudioPath);
      _setProcessingStage(sessionId, '文字起こし中', '端末内WhisperでMP3音声をテキスト化しています');
      final stt = session.transcription.trim().isNotEmpty
          ? _transcriptionFromSession(session)
          : await _transcribeMeetingAudio(
              processedAudioChunks,
              sessionId: sessionId,
            );
      final transcription = stt.text;
      final cleanTranscription = MeetingTextProcessor.cleanTranscript(
        transcription,
      );
      final keywords = MeetingTextProcessor.extractKeywords(
        '$cleanTranscription $transcription',
      );
      final sentiment = _mergeAudioSentiment(
        MeetingTextProcessor.analyzeSentiment(cleanTranscription),
        audioAnalysis,
      );
      final transcriptSegments = _segmentsWithSpeakerHints(stt.segments);
      final speakerLabels = _labelsForSegments(transcriptSegments);
      _setProcessingStage(
        sessionId,
        strings.t('meeting.stage.summarizing'),
        strings.t('meeting.stage.summarizingDetail'),
      );
      if (_shouldUseDeterministicMeetingFallback(transcription)) {
        final summaryText = _fallbackMeetingSummary(transcription);
        final todos = _fallbackMeetingTodos(transcription);
        final translations = _fallbackMeetingTranslations(summaryText);
        final topicSegments = _fallbackTopicSegments(transcriptSegments);
        final noteSets = _buildFallbackNoteSets(
          summaryText,
          todos,
          cleanTranscription,
        );
        final askSuggestions = _buildAskSuggestions(summaryText, todos);
        final mindMap = _buildFallbackMindMap(
          summaryText,
          todos,
          topicSegments,
        );
        final templateOutputs = _buildTemplateOutputs(
          session.copyWith(
            summary: summaryText,
            todos: todos,
            transcription: transcription,
            cleanTranscription: cleanTranscription,
            transcriptSegments: transcriptSegments,
            speakerLabels: speakerLabels,
            topicSegments: topicSegments,
            noteSets: noteSets,
            askSuggestions: askSuggestions,
            mindMap: mindMap,
            keywords: keywords,
            sentiment: sentiment,
          ),
        );
        _updateSession(
          sessionId,
          (s) => s.copyWith(
            status: MeetingStatus.completed,
            summary: summaryText,
            todos: todos,
            todoItems: MeetingTodoItem.fromText(todos),
            translation: translations[_primaryTranslationKey()],
            translations: translations,
            transcription: transcription,
            transcriptSegments: transcriptSegments,
            speakerLabels: speakerLabels,
            topicSegments: topicSegments,
            noteSets: noteSets,
            askSuggestions: askSuggestions,
            mindMap: mindMap,
            keywords: keywords,
            sentiment: sentiment,
            cleanTranscription: cleanTranscription,
            templateOutputs: templateOutputs,
            audioPath: processedAudioPath,
            title: _deriveTitleFromSummary(summaryText),
            processingStage: strings.t('meeting.stage.complete'),
            processingDetail: '',
          ),
        );
        final completed = _sessions.firstWhere((s) => s.id == sessionId);
        await _notifyProcessingFinished(completed);
        await _persist();
        await _stopBackgroundProcessingIfIdle();
        return;
      }

      final model = _preferredChatModel();
      final sharedMemory = session.sharedMemoryEnabled
          ? chatController.buildSharedMemoryPromptContext(
              respectCurrentSessionToggle: false,
            )
          : '';
      final transcriptForModel = await _prepareTranscriptForMeetingAnalysis(
        model,
        transcriptSegments,
        cleanTranscription,
        sessionId: sessionId,
      );
      final analysisPrompt = strings
          .t('meeting.prompt.analysis')
          .replaceAll('{languageClause}', strings.t('meeting.prompt.language'))
          .replaceAll(
            '{sharedMemory}',
            sharedMemory.isNotEmpty ? '\n$sharedMemory\n' : '',
          )
          .replaceAll('{transcript}', transcriptForModel);
      final analysis = await _generateText(
        model,
        analysisPrompt,
        maxTokens: 1050,
      );

      var summaryText = _extractSection(analysis, '要約') == ''
          ? analysis
          : _extractSection(analysis, '要約');
      var todos = _extractSection(analysis, 'TODO');
      if (!_looksUsefulMeetingText(summaryText)) {
        summaryText = _fallbackMeetingSummary(cleanTranscription);
      }
      if (!_looksUsefulTodoText(todos)) {
        todos = await _generateMeetingTodos(
          model,
          transcriptForModel,
          summaryText,
          sessionId: sessionId,
        );
      }
      if (!_looksUsefulTodoText(todos)) {
        todos = _fallbackMeetingTodos(cleanTranscription);
      }
      final topicSegments = _parseTopicSegments(
        _extractSection(analysis, 'タイムライン'),
        transcriptSegments,
      );
      final noteSets = <MeetingNoteSet>[
        MeetingNoteSet(title: 'Overview', body: summaryText),
        MeetingNoteSet(
          title: 'Discussion points',
          body: _extractSection(analysis, '論点'),
        ),
        MeetingNoteSet(
          title: 'Decisions',
          body: _extractSection(analysis, '決定事項'),
        ),
      ].where((noteSet) => noteSet.body.trim().isNotEmpty).toList();
      final effectiveNoteSets = noteSets.isEmpty
          ? _buildFallbackNoteSets(summaryText, todos, cleanTranscription)
          : noteSets;
      final askSuggestions = _parseBulletLines(
        _extractSection(analysis, 'Ask'),
      );
      final effectiveAskSuggestions = askSuggestions.isEmpty
          ? _buildAskSuggestions(summaryText, todos)
          : askSuggestions.take(6).toList();
      var mindMap = _parseMindMap(_extractSection(analysis, 'MindMap'));
      if (!_hasUsefulMindMap(mindMap)) {
        mindMap = await _generateMeetingMindMap(
          model,
          summaryText,
          todos,
          transcriptForModel,
          sessionId: sessionId,
        );
      }
      final effectiveMindMap = _hasUsefulMindMap(mindMap)
          ? mindMap
          : _buildFallbackMindMap(summaryText, todos, topicSegments);
      final translationSource = _buildTranslationSource(
        summaryText,
        todos,
        effectiveNoteSets,
      );
      final translations = await _generateMeetingTranslations(
        model,
        translationSource,
        sessionId: sessionId,
      );

      if (session.sharedMemoryEnabled) {
        _setProcessingStage(
          sessionId,
          strings.t('meeting.stage.sharedMemory'),
          strings.t('meeting.stage.sharedMemoryDetail'),
        );
        await chatController.summarizeAndWriteSharedMemorySection(
          '''会議:
要約:
$summaryText

TODO:
$todos

文字起こし:
${_takeRunes(transcription, 2400)}''',
          enabled: session.sharedMemoryEnabled,
          summarize: (prompt) => _generateText(model, prompt, maxTokens: 256),
        );
      }

      final completedDraft = session.copyWith(
        summary: summaryText,
        todos: todos,
        transcription: transcription,
        cleanTranscription: cleanTranscription,
        transcriptSegments: transcriptSegments,
        speakerLabels: speakerLabels,
        topicSegments: topicSegments,
        noteSets: effectiveNoteSets,
        askSuggestions: effectiveAskSuggestions,
        mindMap: effectiveMindMap,
        keywords: keywords,
        sentiment: sentiment,
      );
      final templateOutputs = _buildTemplateOutputs(completedDraft);

      _updateSession(
        sessionId,
        (s) => s.copyWith(
          status: MeetingStatus.completed,
          summary: summaryText,
          todos: todos,
          todoItems: MeetingTodoItem.fromText(todos),
          translation: translations[_primaryTranslationKey()],
          translations: translations,
          transcription: transcription,
          transcriptSegments: transcriptSegments,
          speakerLabels: speakerLabels,
          topicSegments: topicSegments,
          noteSets: effectiveNoteSets,
          askSuggestions: effectiveAskSuggestions,
          mindMap: effectiveMindMap,
          keywords: keywords,
          sentiment: sentiment,
          cleanTranscription: cleanTranscription,
          templateOutputs: templateOutputs,
          audioPath: processedAudioPath,
          title: _deriveTitleFromSummary(summaryText),
          processingStage: strings.t('meeting.stage.complete'),
          processingDetail: '',
        ),
      );
      final completed = _sessions.firstWhere((s) => s.id == sessionId);
      await _notifyProcessingFinished(completed);
      await _stopBackgroundProcessingIfIdle();
    } catch (e) {
      debugPrint('Meeting processing error: $e');
      if (_sessions.any((s) => s.id == sessionId)) {
        _updateSession(
          sessionId,
          (s) => s.copyWith(
            status: MeetingStatus.failed,
            processingStage: strings.t('meeting.stage.failed'),
            processingDetail: e.toString(),
          ),
        );
      }
      await _notifyProcessingFailed(e.toString());
    } finally {
      _activeProcessingSessionIds.remove(sessionId);
      await _stopBackgroundProcessingIfIdle();
      await _releaseMeetingGenAi();
    }
  }

  Future<String> askMeetingQuestion(
    MeetingSession session,
    String question, {
    bool useWeb = true,
  }) async {
    final webResult = useWeb
        ? await _webResearch.researchIfUseful(question)
        : const WebResearchResult(query: '', sources: <WebSource>[]);
    final sharedMemory = session.sharedMemoryEnabled
        ? chatController.buildSharedMemoryPromptContext(
            respectCurrentSessionToggle: false,
          )
        : '';
    final answer = await (() async {
      try {
        final model = _preferredChatModel();
        return await _generateText(
          model,
          '''以下の会議内容を理解した上で、質問に答えてください。
${sharedMemory.isNotEmpty ? '\n$sharedMemory\n' : ''}
${webResult.hasSources ? '\n${webResult.buildPromptContext()}\n' : ''}

# 会議要約
${session.summary}

# TODO
${session.todos}

# 文字起こし
${_formatTranscriptForPrompt(session.transcriptSegments, session.transcription)}

# 質問
$question

回答では必要に応じて [00:12] のような根拠時刻を入れてください。''',
          maxTokens: 256,
        ).timeout(const Duration(seconds: 90));
      } catch (error) {
        debugPrint('Meeting consultation GenAI fallback: $error');
        return _fallbackMeetingQuestionAnswer(session, question, webResult);
      }
    })();
    final now = DateTime.now();
    final persistedQuestion = MeetingConsultationMessage(
      id: 'meeting-consult-user-${now.microsecondsSinceEpoch}',
      text: question,
      isUser: true,
      createdAt: now,
    );
    final persistedAnswer = MeetingConsultationMessage(
      id: 'meeting-consult-ai-${now.microsecondsSinceEpoch}',
      text: answer,
      isUser: false,
      createdAt: DateTime.now(),
    );
    _updateSession(
      session.id,
      (s) => s.copyWith(
        webSources: webResult.hasSources ? webResult.sources : s.webSources,
        consultations: <MeetingConsultationMessage>[
          ...s.consultations,
          persistedQuestion,
          persistedAnswer,
        ],
      ),
    );
    await _persist();
    await _mirrorMeetingConsultationToTalk(session, question, answer);
    if (session.sharedMemoryEnabled) {
      await chatController.summarizeAndWriteSharedMemorySection(
        '''会議相談:
会議要約:
${session.summary}

質問:
$question

        回答:
$answer''',
        enabled: session.sharedMemoryEnabled,
        summarize: (prompt) async {
          try {
            return await _generateText(
              _preferredChatModel(),
              prompt,
              maxTokens: 256,
            );
          } catch (error) {
            debugPrint('Meeting consultation memory fallback: $error');
            return _takeRunes(prompt, 900);
          }
        },
      );
    }
    return answer;
  }

  String _fallbackMeetingQuestionAnswer(
    MeetingSession session,
    String question,
    WebResearchResult webResult,
  ) {
    final summary = _takeRunes(
      (session.summary.trim().isNotEmpty
              ? session.summary.trim()
              : session.cleanTranscription.trim().isNotEmpty
              ? session.cleanTranscription.trim()
              : session.transcription.trim())
          .replaceAll(RegExp(r'\s+'), ' '),
      360,
    );
    final todos = _parseBulletLines(session.todos).take(4).toList();
    final buffer = StringBuffer();
    if (useEnglish) {
      buffer.writeln(
        'I could not run the local chat model for this follow-up, so I answered from the processed meeting data.',
      );
      buffer.writeln();
      buffer.writeln('Question: $question');
      if (summary.isNotEmpty) {
        buffer.writeln('Meeting context: $summary');
      }
      if (todos.isNotEmpty) {
        buffer.writeln('Next checks:');
        for (final todo in todos) {
          buffer.writeln('- ${todo.replaceFirst(RegExp(r'^[-*・]\s*'), '')}');
        }
      }
      if (webResult.hasSources) {
        buffer.writeln(
          'Web sources were available: ${webResult.sources.length}.',
        );
      }
      return buffer.toString().trim();
    }
    buffer.writeln('ローカルチャットモデルで追加回答を生成できなかったため、処理済みの会議データから回答します。');
    buffer.writeln();
    buffer.writeln('質問: $question');
    if (summary.isNotEmpty) {
      buffer.writeln('会議の文脈: $summary');
    }
    if (todos.isNotEmpty) {
      buffer.writeln('次に確認すること:');
      for (final todo in todos) {
        buffer.writeln('- ${todo.replaceFirst(RegExp(r'^[-*・]\s*'), '')}');
      }
    }
    if (webResult.hasSources) {
      buffer.writeln('Web検索結果: ${webResult.sources.length}件を取得済みです。');
    }
    return buffer.toString().trim();
  }

  Future<void> _releaseMeetingGenAi() async {
    try {
      await _genAiRuntime.releaseIdle();
    } catch (error) {
      debugPrint('Meeting GenAI release error: $error');
    }
  }

  Future<void> _mirrorMeetingConsultationToTalk(
    MeetingSession session,
    String question,
    String answer,
  ) async {
    await chatController.initialize();
    await chatController.createSession();
    await chatController.addUserMessage('会議相談: ${session.title}\n\n$question');
    final assistantId = chatController.startAssistantMessage(
      progressLabel: '会議相談',
    );
    await chatController.completeAssistantMessage(
      assistantId,
      finalText: answer,
      webSources: session.webSources,
    );
  }

  _MeetingTranscription _transcriptionFromSession(MeetingSession session) {
    final text = session.transcription.trim();
    if (text.isEmpty) {
      throw StateError('文字起こしが空です。MP3/WAVを取り込む場合はWhisperモデルをインストールしてください。');
    }
    final segments = session.transcriptSegments.isNotEmpty
        ? session.transcriptSegments
        : <MeetingTranscriptSegment>[
            MeetingTranscriptSegment(
              text: text,
              startSeconds: 0,
              endSeconds: 0,
              confidence: 1,
            ),
          ];
    return _MeetingTranscription(text: text, segments: segments);
  }

  Future<_MeetingTranscription> _transcribe(String audioPath) async {
    final model = _installedAssetFor(const <String>[
      'whisper-medium',
      'whisper-small',
      'whisper-base',
      'whisper-tiny',
    ]);
    if (model == null) {
      throw StateError(
        'Whisper model is not installed. Install whisper-base or whisper-tiny before importing meeting MP3 files.',
      );
    }
    final response = await Isolate.run<Map<String, Object?>>(
      () => _runMeetingWhisperStt(<String, String>{
        'audioPath': audioPath,
        'modelPath': model.path,
      }),
    );
    final text = response['text']?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw StateError('文字起こし結果が空でした。');
    }
    final segments = (response['segments'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map>()
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          return MeetingTranscriptSegment(
            text: map['text'] as String? ?? '',
            startSeconds: (map['start_time'] as num?)?.toDouble() ?? 0,
            endSeconds: (map['end_time'] as num?)?.toDouble() ?? 0,
            confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
          );
        })
        .where((segment) => segment.text.trim().isNotEmpty)
        .toList();
    return _MeetingTranscription(text: text, segments: segments);
  }

  Future<List<String>> _splitMeetingAudio(String audioPath) async {
    try {
      final chunks = await _audioTools.splitSpeechWav(
        audioPath,
        chunkDuration: _meetingAudioChunkDuration,
      );
      return chunks.isEmpty ? <String>[audioPath] : chunks;
    } catch (error) {
      debugPrint('Meeting audio split skipped: $error');
      return <String>[audioPath];
    }
  }

  Future<_MeetingTranscription> _transcribeMeetingAudio(
    List<String> audioPaths, {
    required String sessionId,
  }) async {
    if (audioPaths.length <= 1) {
      return _transcribe(audioPaths.single);
    }
    final transcript = StringBuffer();
    final segments = <MeetingTranscriptSegment>[];
    for (var i = 0; i < audioPaths.length; i++) {
      _setProcessingStage(
        sessionId,
        '文字起こし中',
        '長時間会議を分割してWhisper処理しています (${i + 1}/${audioPaths.length})',
      );
      final chunk = await _transcribe(audioPaths[i]);
      final offsetSeconds = i * _meetingAudioChunkDuration.inSeconds.toDouble();
      final chunkText = chunk.text.trim();
      if (chunkText.isNotEmpty) {
        transcript.writeln(chunkText);
      }
      segments.addAll(_segmentsWithOffset(chunk.segments, offsetSeconds));
      final partialText = transcript.toString().trim();
      if (partialText.isNotEmpty && _sessions.any((s) => s.id == sessionId)) {
        _updateSession(
          sessionId,
          (session) => session.copyWith(
            transcription: partialText,
            transcriptSegments: segments,
            processingDetail: 'Whisper文字起こし ${i + 1}/${audioPaths.length} 完了',
          ),
        );
        await _persist();
      }
    }
    final text = transcript.toString().trim();
    if (text.isEmpty) {
      throw StateError('文字起こし結果が空でした。');
    }
    return _MeetingTranscription(text: text, segments: segments);
  }

  List<MeetingTranscriptSegment> _segmentsWithOffset(
    List<MeetingTranscriptSegment> segments,
    double offsetSeconds,
  ) {
    if (offsetSeconds <= 0) {
      return segments;
    }
    return segments
        .map(
          (segment) => MeetingTranscriptSegment(
            text: segment.text,
            startSeconds: segment.startSeconds + offsetSeconds,
            endSeconds: segment.endSeconds + offsetSeconds,
            speakerId: segment.speakerId,
            confidence: segment.confidence,
            speakerConfidence: segment.speakerConfidence,
          ),
        )
        .toList(growable: false);
  }

  Future<String> _preprocessMeetingAudio(
    String audioPath,
    MeetingAudioOptions options,
  ) async {
    try {
      return await _audioTools.preprocessForMeeting(
        audioPath,
        voiceEnhancement: options.voiceEnhancementEnabled,
      );
    } catch (error) {
      debugPrint('Meeting audio preprocess skipped: $error');
      return audioPath;
    }
  }

  Future<Map<String, Object?>> _safeAnalyzeAudio(String audioPath) async {
    try {
      return await _audioTools.analyzeAudio(audioPath);
    } catch (error) {
      debugPrint('Meeting audio analysis skipped: $error');
      return const <String, Object?>{};
    }
  }

  MeetingSentimentMetrics _mergeAudioSentiment(
    MeetingSentimentMetrics textSentiment,
    Map<String, Object?> audioAnalysis,
  ) {
    final speechRatio = (audioAnalysis['speech_ratio'] as num?)?.toDouble();
    final rms = (audioAnalysis['rms'] as num?)?.toDouble();
    if (speechRatio == null && rms == null) {
      return textSentiment;
    }
    final energyBoost = ((rms ?? 0.08) * 2.5).clamp(0.0, 0.2);
    final silenceConcern = speechRatio == null
        ? 0.0
        : (1 - speechRatio).clamp(0.0, 0.25);
    return MeetingSentimentMetrics(
      satisfaction: (textSentiment.satisfaction + energyBoost).clamp(0.0, 1.0),
      motivation: (textSentiment.motivation + energyBoost).clamp(0.0, 1.0),
      concern: (textSentiment.concern + silenceConcern).clamp(0.0, 1.0),
      summary:
          '${textSentiment.summary} 音量と無音比率も加味しています。'
          '${speechRatio == null ? '' : ' 発話比率 ${(speechRatio * 100).round()}%。'}',
    );
  }

  Map<String, String> _buildTemplateOutputs(MeetingSession session) {
    final template = MeetingTextProcessor.templateById(session.templateId);
    return <String, String>{
      template.id: MeetingTextProcessor.templateOutput(template, session),
    };
  }

  Future<String> _generateTemplateOutput(
    MeetingSession session,
    MeetingSummaryTemplate template,
  ) async {
    final model = _preferredChatModel();
    final prompt =
        '''${MeetingTextProcessor.buildTemplatePrompt(template)}

# 会議タイトル
${session.title}

# 既存要約
${session.summary}

# TODO
${session.todos}

# キーワード
${session.keywords.join('、')}

# 重要マーク
${session.bookmarks.map((b) => '[${_formatTimestamp(b.startSeconds)}] ${b.label}${b.note.trim().isEmpty ? '' : ': ${b.note}'}').join('\n')}

# 文字起こし
${_formatTranscriptForPrompt(session.transcriptSegments, session.cleanTranscription.isEmpty ? session.transcription : session.cleanTranscription)}

テンプレート「${template.title}」に完全に合わせて、上の文字起こしから生成し直してください。既存要約をそのまま貼らず、各見出しの目的に沿って再構成してください。''';
    final output = await _generateText(
      model,
      prompt,
      maxTokens: template.id == 'detailed' ? 1400 : 1000,
    );
    if (!_looksUsefulMeetingText(output) || output.runes.length < 40) {
      return MeetingTextProcessor.templateOutput(template, session);
    }
    return output;
  }

  Future<void> updateSpeakerLabel(
    String sessionId,
    String speakerId,
    String label,
  ) async {
    final cleanLabel = label.trim().isEmpty ? speakerId : label.trim();
    _updateSession(
      sessionId,
      (session) => session.copyWith(
        speakerLabels: <String, String>{
          ...session.speakerLabels,
          speakerId: cleanLabel,
        },
      ),
    );
    _speakerProfileLabels[speakerId] = cleanLabel;
    await _persist();
    await _persistSpeakerProfiles();
  }

  Future<void> renameSpeakerEverywhere(String speakerId, String label) async {
    final cleanLabel = label.trim().isEmpty ? speakerId : label.trim();
    _speakerProfileLabels[speakerId] = cleanLabel;
    _sessions = _sessions
        .map(
          (session) => session.copyWith(
            speakerLabels: <String, String>{
              ...session.speakerLabels,
              speakerId: cleanLabel,
            },
          ),
        )
        .toList(growable: false);
    notifyListeners();
    await _persist();
    await _persistSpeakerProfiles();
  }

  Future<void> shareMeetingMarkdown(MeetingSession session) async {
    await _shareChannel.invokeMethod<void>('sendText', <String, Object?>{
      'title': session.title,
      'text': buildMeetingMarkdown(session),
    });
  }

  String buildMeetingMarkdown(MeetingSession session) {
    final buffer = StringBuffer()
      ..writeln('# ${session.title}')
      ..writeln()
      ..writeln('- 作成日時: ${session.createdAt.toIso8601String()}')
      ..writeln('- 音声: ${session.audioPath}')
      ..writeln()
      ..writeln('## 要約')
      ..writeln(
        session.summary.trim().isEmpty ? '要約なし' : session.summary.trim(),
      )
      ..writeln()
      ..writeln('## TODO')
      ..writeln(session.todos.trim().isEmpty ? 'TODOなし' : session.todos.trim());
    if (session.topicSegments.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## タイムライン');
      for (final topic in session.topicSegments) {
        buffer.writeln(
          '- ${_formatTimestamp(topic.startSeconds)} ${topic.title}'
          '${topic.summary.trim().isEmpty ? '' : ' - ${topic.summary.trim()}'}',
        );
      }
    }
    if (session.transcriptSegments.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 文字起こし');
      for (final segment in session.transcriptSegments) {
        final speaker =
            session.speakerLabels[segment.speakerId] ??
            (segment.speakerId.isEmpty ? 'Speaker' : segment.speakerId);
        buffer.writeln(
          '- [${_formatTimestamp(segment.startSeconds)}] $speaker: ${segment.text.trim()}',
        );
      }
    } else {
      buffer
        ..writeln()
        ..writeln('## 文字起こし')
        ..writeln(session.transcription.trim());
    }
    return buffer.toString().trim();
  }

  _MeetingAsset _preferredChatModel() {
    return _installedAssetFor(const <String>[
          'gemma-4-e2b-litertlm-it',
          'gemma-4-e4b-litertlm-it',
        ]) ??
        (throw StateError('LiteRT-LM chat model bundle is not installed.'));
  }

  _MeetingAsset? _installedAssetFor(List<String> modelIds) {
    for (final modelId in modelIds) {
      final installation = modelController.installationFor(modelId);
      if (installation != null) {
        return _MeetingAsset(modelId, installation.activePath);
      }
      final component = modelController.componentInstallationFor(modelId);
      if (component != null) {
        return _MeetingAsset(modelId, component.activePath);
      }
    }
    return null;
  }

  Future<String> _generateText(
    _MeetingAsset model,
    String prompt, {
    int maxTokens = 1024,
  }) async {
    if (!model.path.toLowerCase().endsWith('.litertlm')) {
      throw StateError('会議アシスタントはLiteRT-LMモデルのみ対応しています。');
    }
    Future<essential.EssentialGenAiGenerationResult> run(String accelerator) {
      return _genAiRuntime.generate(
        requestId: 'meeting-${DateTime.now().microsecondsSinceEpoch}',
        modelPath: model.path,
        prompt: prompt,
        systemInstruction: strings.t('meeting.system'),
        maxTokens: maxTokens.clamp(64, 1600),
        contextTokens: _meetingContextTokens,
        topK: 8,
        topP: 0.82,
        temperature: 0.15,
        accelerator: accelerator,
      );
    }

    late final essential.EssentialGenAiGenerationResult response;
    try {
      response = await run('gpu');
    } on PlatformException catch (error) {
      final message = error.message ?? '';
      final shouldRetryOnCpu =
          error.code == 'genai_error' &&
          (message.contains('Failed to enqueue barrier') ||
              message.contains('Status Code: 13') ||
              message.contains('INTERNAL'));
      if (!shouldRetryOnCpu) {
        rethrow;
      }
      debugPrint('Meeting GenAI GPU unavailable, retrying on CPU: $message');
      response = await run('cpu');
    }
    return _cleanModelText(response.text);
  }

  Future<String> _prepareTranscriptForMeetingAnalysis(
    _MeetingAsset model,
    List<MeetingTranscriptSegment> segments,
    String fallback, {
    String? sessionId,
  }) async {
    final chunks = _formatTranscriptChunksForPrompt(segments, fallback);
    if (chunks.isEmpty) {
      return '';
    }
    if (chunks.length == 1) {
      return chunks.single;
    }

    final compressedChunks = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      if (sessionId != null) {
        _setProcessingStage(
          sessionId,
          strings.t('meeting.stage.summarizing'),
          '長い会議を分割して整理しています (${i + 1}/${chunks.length})',
        );
      }
      try {
        final compressed = await _generateText(
          model,
          '''次の会議文字起こしは全体の一部分です。後で全体を統合するため、事実だけを短く圧縮してください。

厳守事項:
- この部分で出た決定事項、TODO、論点、重要な固有名詞を残す
- 推測や補足説明を追加しない
- 8行以内
- 時刻がある場合は残す

# 文字起こし ${i + 1}/${chunks.length}
${chunks[i]}''',
          maxTokens: 360,
        );
        compressedChunks.add(
          '## 分割 ${i + 1}/${chunks.length}\n'
          '${_takeRunes(compressed.trim(), _meetingChunkSummaryRunes)}',
        );
      } catch (error) {
        debugPrint('Meeting chunk summarization fallback: $error');
        compressedChunks.add(
          '## 分割 ${i + 1}/${chunks.length}\n${_takeRunes(chunks[i], 700)}',
        );
      }
    }

    return _collapseChunkSummariesForMeetingAnalysis(
      model,
      compressedChunks,
      sessionId: sessionId,
    );
  }

  Future<String> _collapseChunkSummariesForMeetingAnalysis(
    _MeetingAsset model,
    List<String> compressedChunks, {
    String? sessionId,
  }) async {
    var current = compressedChunks;
    var pass = 1;
    while (current.join('\n\n').runes.length > _meetingPromptTranscriptRunes &&
        current.length > 1) {
      final next = <String>[];
      for (var i = 0; i < current.length; i += 3) {
        final group = current.skip(i).take(3).join('\n\n');
        if (sessionId != null) {
          _setProcessingStage(
            sessionId,
            strings.t('meeting.stage.summarizing'),
            '分割要約を統合しています (${(i ~/ 3) + 1}/${(current.length + 2) ~/ 3})',
          );
        }
        try {
          final merged = await _generateText(
            model,
            '''次の分割要約を、後続の会議全体要約に渡すために統合してください。

厳守事項:
- 情報を捨てず、重複だけ削る
- 決定事項、TODO、論点、固有名詞、時刻を優先する
- 10行以内

# 分割要約
$group''',
            maxTokens: 420,
          );
          next.add(
            '## 統合 $pass-${(i ~/ 3) + 1}\n'
            '${_takeRunes(merged.trim(), _meetingChunkSummaryRunes)}',
          );
        } catch (error) {
          debugPrint('Meeting chunk collapse fallback: $error');
          next.add(_takeRunes(group, _meetingChunkSummaryRunes));
        }
      }
      current = next;
      pass++;
    }
    final joined = current.join('\n\n').trim();
    if (joined.runes.length <= _meetingPromptTranscriptRunes) {
      return '# 分割済み文字起こし要約\n$joined';
    }
    return '# 分割済み文字起こし要約\n${_takeRunes(joined, _meetingPromptTranscriptRunes)}';
  }

  String _cleanModelText(String text) {
    final lines = text
        .split('\n')
        .where((line) => !_isInternalReasoningLine(line))
        .join('\n');
    return lines
        .replaceAll('<end_of_turn>', '')
        .replaceAll('<turn|>', '')
        .replaceAll('</s>', '')
        .replaceAll(RegExp(r'<\|/?(?:user|assistant|system)\|>'), '')
        .replaceAll(RegExp(r'<start_of_turn>(?:user|model|system)'), '')
        .split('\n')
        .map((line) => line.trimRight().replaceFirst(RegExp(r'^\s*\*\s+'), '・'))
        .where((line) => !RegExp(r'^([*＊・\-—–•●○#\s])+$').hasMatch(line.trim()))
        .join('\n')
        .trim();
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

  bool _looksUsefulMeetingText(String text) {
    final normalized = text.trim();
    if (normalized.runes.length < 8) {
      return false;
    }
    final lower = normalized.toLowerCase();
    if (lower.contains('翻译') ||
        normalized.contains('表示されます') ||
        normalized.contains('出力フォーマット') ||
        normalized.contains('この形式でも良いか') ||
        normalized.contains('改めてやり直します')) {
      return false;
    }
    return true;
  }

  bool _looksUsefulTodoText(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^(TODO|ToDo|タスク)?(なし|無し|ありません|特になし)$').hasMatch(compact)) {
      return true;
    }
    if (!_looksUsefulMeetingText(normalized)) {
      return false;
    }
    if (normalized.contains('人間が補足') ||
        normalized.contains('確認対象:') ||
        normalized.contains('必要な担当者・期限')) {
      return false;
    }
    return RegExp(
      r'(^|\n)\s*(?:[・\-]|\d+[.)．、]|TODO|担当|期限|次|確認|対応|実施|共有|作成|調整|連絡|決定)',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  Future<String> _generateMeetingTodos(
    _MeetingAsset model,
    String transcription,
    String summary, {
    String? sessionId,
  }) async {
    if (sessionId != null) {
      _setProcessingStage(
        sessionId,
        strings.t('meeting.stage.summarizing'),
        'TODOを個別に整理しています',
      );
    }
    final output = await _generateText(model, '''以下の会議内容からTODOだけを生成してください。

厳守事項:
- TODO本文だけを出力する
- 各行は「・担当: ... / 期限: ... / 内容: ...」または「・内容: ...」の形にする
- 会議内に実行項目が本当に無い場合だけ「TODOなし」と出力する
- 原文、説明、見出し、翻訳、MindMapを混ぜない

# 要約
$summary

# 文字起こし
${_takeRunes(transcription, _meetingPromptTranscriptRunes)}''', maxTokens: 420);
    return _cleanTodoText(output);
  }

  String _cleanTodoText(String text) {
    final cleaned = _cleanModelText(text)
        .replaceFirst(
          RegExp(r'^\s*#{1,3}\s*TODO\s*[:：]?\s*', caseSensitive: false),
          '',
        )
        .trim();
    final lines = cleaned
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(
          (line) => !RegExp(
            r'^(要約|MindMap|English|中文|한국어|翻訳)\s*[:：]?$',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .take(10)
        .toList(growable: false);
    return lines.join('\n').trim();
  }

  Future<Map<String, String>> _generateMeetingTranslations(
    _MeetingAsset model,
    String summaryText, {
    String? sessionId,
    Map<String, String> current = const <String, String>{},
  }) async {
    final translations = Map<String, String>.from(current);
    for (final entry in _translationTargets().entries) {
      if ((translations[entry.key] ?? '').trim().isEmpty) {
        if (sessionId != null) {
          _setProcessingStage(
            sessionId,
            strings.t('meeting.stage.translating'),
            strings
                .t('meeting.stage.translatingDetail')
                .replaceAll('{language}', entry.value),
          );
        }
        translations[entry.key] = _cleanTranslationText(
          await _generateText(
            model,
            strings
                .t('meeting.prompt.translate')
                .replaceAll('{language}', entry.value)
                .replaceAll('{summary}', summaryText),
            maxTokens: 256,
          ),
          entry.key,
        );
      }
      if (_needsTranslationRegeneration(
        entry.key,
        translations[entry.key] ?? '',
        summaryText,
      )) {
        if (sessionId != null) {
          _setProcessingStage(
            sessionId,
            strings.t('meeting.stage.translating'),
            strings
                .t('meeting.stage.retranslatingDetail')
                .replaceAll('{language}', entry.value),
          );
        }
        translations[entry.key] = _cleanTranslationText(
          await _generateText(
            model,
            strings
                .t('meeting.prompt.translateRetry')
                .replaceAll('{language}', entry.value)
                .replaceAll('{summary}', summaryText),
            maxTokens: 512,
          ),
          entry.key,
        );
      }
      if (_needsTranslationRegeneration(
        entry.key,
        translations[entry.key] ?? '',
        summaryText,
      )) {
        translations[entry.key] = _fallbackMeetingTranslations(
          summaryText,
        )[entry.key]!;
      }
    }
    return translations;
  }

  Map<String, String> _translationTargets() {
    return useEnglish
        ? const <String, String>{
            'ja': 'natural Japanese',
            'zh': 'Simplified Chinese only',
            'ko': '자연스러운 한국어',
          }
        : const <String, String>{
            'en': 'natural English',
            'zh': 'Simplified Chinese only',
            'ko': '자연스러운 한국어',
          };
  }

  String _primaryTranslationKey() => useEnglish ? 'ja' : 'en';

  bool _needsTranslationRegeneration(
    String language,
    String translation,
    String source,
  ) {
    final text = translation.trim();
    if (text.runes.length < 12) return true;
    if (text == source.trim()) return true;
    final lower = text.toLowerCase();
    if (text.contains('翻訳本文') ||
        text.contains('日本語の原文') ||
        text.contains('原文') ||
        text.contains('説明') ||
        text.contains('翻訳できません') ||
        text.contains('生成できません') ||
        lower.contains('source text') ||
        lower.contains('translated text') ||
        lower.contains('translation:') ||
        lower.contains('here is') ||
        lower.contains('confirmed from the transcript') ||
        lower.contains('could not be generated') ||
        lower.contains('could not translate') ||
        lower.contains('summary based on the transcription')) {
      return true;
    }
    if (RegExp(
      r'(^|\n)\s*#{1,3}\s*(要約|TODO|タイムライン|論点|決定事項|Ask|MindMap|English|日本語|中文|한국어)\b',
    ).hasMatch(text)) {
      return true;
    }
    final kanaChars = RegExp(r'[\u3040-\u30ff]').allMatches(text).length;
    final cjkChars = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
    final japaneseChars = kanaChars + cjkChars;
    final totalChars = text.runes.where((code) => code > 0x20).length;
    if (totalChars == 0) return true;
    if (language == 'en') {
      final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
      if (japaneseChars / totalChars > 0.08 || letters < 8) return true;
    }
    if (language == 'ja' && (japaneseChars / totalChars < 0.12)) return true;
    if (language == 'zh' && (cjkChars == 0 || kanaChars > 0)) return true;
    if (language == 'ko' && !RegExp(r'[\uac00-\ud7af]').hasMatch(text)) {
      return true;
    }
    return false;
  }

  String _cleanTranslationText(String text, String language) {
    var cleaned = _cleanModelText(
      text,
    ).replaceAll(RegExp(r'^\s*["“”]+|["“”]+\s*$'), '').trim();
    final preferredHeading = switch (language) {
      'en' => 'English',
      'ja' => '日本語',
      'zh' => '中文',
      'ko' => '한국어',
      _ => '',
    };
    final sectionMatch = RegExp(
      '#\\s*(?:$preferredHeading|English|日本語|中文|한국어)\\s*\\n([\\s\\S]*)',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (sectionMatch != null) {
      cleaned = sectionMatch.group(1)?.trim() ?? cleaned;
    }
    cleaned = cleaned
        .split('\n')
        .where((line) {
          final normalized = line.trim().toLowerCase();
          if (normalized.isEmpty) return true;
          if (RegExp(r'^#{1,3}\s*').hasMatch(normalized)) return false;
          if (normalized == 'translation' ||
              normalized == 'translated text' ||
              normalized == 'source text' ||
              normalized == '翻訳' ||
              normalized == '翻訳本文' ||
              normalized == '原文') {
            return false;
          }
          if (normalized.startsWith('here is') ||
              normalized.startsWith('translation:') ||
              normalized.startsWith('translated text:') ||
              normalized.startsWith('翻訳:') ||
              normalized.startsWith('翻訳本文:')) {
            return false;
          }
          return true;
        })
        .join('\n')
        .trim();
    return cleaned;
  }

  String _buildTranslationSource(
    String summary,
    String todos,
    List<MeetingNoteSet> noteSets,
  ) {
    final buffer = StringBuffer()
      ..writeln('要約')
      ..writeln(_takeRunes(summary.trim(), 1600));
    final decisions = noteSets
        .where((note) => note.title.contains('決定'))
        .map((note) => note.body.trim())
        .where((body) => body.isNotEmpty)
        .join('\n');
    if (decisions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('決定事項')
        ..writeln(_takeRunes(decisions, 700));
    }
    return _takeRunes(buffer.toString().trim(), 2600);
  }

  bool _shouldUseDeterministicMeetingFallback(String transcription) {
    return transcription.trim().runes.length < 2400;
  }

  String _fallbackMeetingSummary(String transcription) {
    final excerpt = _takeRunes(transcription.trim(), 420);
    if (useEnglish) {
      return 'Confirmed from the transcript:\n- $excerpt';
    }
    return '文字起こしから確認できた内容:\n- $excerpt';
  }

  String _fallbackMeetingTodos(String transcription) {
    final excerpt = _takeRunes(transcription.trim(), 180);
    if (useEnglish) {
      return '- Review the transcript and add any missing owner, deadline, and next action.\n'
          '- Review target: $excerpt';
    }
    return '- 文字起こし内容を確認し、必要な担当者・期限・次の行動を人間が補足する。\n'
        '- 確認対象: $excerpt';
  }

  List<MeetingTranscriptSegment> _segmentsWithSpeakerHints(
    List<MeetingTranscriptSegment> segments,
  ) {
    if (segments.isEmpty) {
      return const <MeetingTranscriptSegment>[];
    }
    var currentSpeaker = 1;
    var previousEnd = segments.first.startSeconds;
    var previousSignature = _speakerSignature(segments.first.text);
    final namedSpeakers = <String, int>{};
    return <MeetingTranscriptSegment>[
      for (var i = 0; i < segments.length; i++)
        () {
          final segment = segments[i];
          final namedSpeaker = _speakerNameHint(segment.text);
          if (namedSpeaker != null) {
            namedSpeakers.putIfAbsent(
              namedSpeaker,
              () => namedSpeakers.length + 1,
            );
            currentSpeaker = namedSpeakers[namedSpeaker]!.clamp(1, 6);
          }
          final gap = segment.startSeconds - previousEnd;
          final signature = _speakerSignature(segment.text);
          if (namedSpeaker == null &&
              i > 0 &&
              (gap > 1.8 || (signature - previousSignature).abs() > 3)) {
            currentSpeaker = currentSpeaker >= 4 ? 1 : currentSpeaker + 1;
          }
          previousEnd = segment.endSeconds <= 0
              ? segment.startSeconds
              : segment.endSeconds;
          previousSignature = signature;
          return MeetingTranscriptSegment(
            text: segment.text,
            startSeconds: segment.startSeconds,
            endSeconds: segment.endSeconds,
            confidence: segment.confidence,
            speakerId: namedSpeaker ?? 'Speaker $currentSpeaker',
            speakerConfidence: i == 0 ? 0.4 : 0.58,
          );
        }(),
    ];
  }

  int _speakerSignature(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return 0;
    final questionBias = clean.contains('？') || clean.contains('?') ? 2 : 0;
    final politeBias = RegExp(r'(です|ます|ました|でしょう|ください)').hasMatch(clean) ? 1 : 0;
    return (clean.runes.length ~/ 18) + questionBias + politeBias;
  }

  String? _speakerNameHint(String text) {
    final match = RegExp(
      r'([一-龥ぁ-んァ-ヶA-Za-z]{2,12})(?:さん|氏|くん|ちゃん)\s*(?:[:：、,]|が|は|から|の)?',
    ).firstMatch(text);
    final name = match?.group(1)?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    if (const <String>{'今日', '皆', 'みな', 'それ', 'こちら', 'お客'}.contains(name)) {
      return null;
    }
    return name;
  }

  Map<String, String> _labelsForSegments(
    List<MeetingTranscriptSegment> segments,
  ) {
    final labels = <String, String>{};
    for (final segment in segments) {
      if (segment.speakerId.trim().isEmpty) continue;
      labels[segment.speakerId] =
          _speakerProfileLabels[segment.speakerId] ?? segment.speakerId;
    }
    return labels;
  }

  String _formatTranscriptForPrompt(
    List<MeetingTranscriptSegment> segments,
    String fallback,
  ) {
    if (segments.isEmpty) {
      return _takeRunes(fallback, _meetingPromptTranscriptRunes);
    }
    final formatted = segments
        .take(90)
        .map(
          (segment) =>
              '[${_formatTimestamp(segment.startSeconds)}] '
              '${segment.speakerId.isEmpty ? 'Speaker' : segment.speakerId}: '
              '${segment.text.trim()}',
        )
        .join('\n');
    return _takeRunes(formatted, _meetingPromptTranscriptRunes);
  }

  List<String> _formatTranscriptChunksForPrompt(
    List<MeetingTranscriptSegment> segments,
    String fallback,
  ) {
    if (segments.isEmpty) {
      return _splitRunes(fallback.trim(), _meetingTranscriptChunkRunes);
    }
    final chunks = <String>[];
    final buffer = StringBuffer();
    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        chunks.add(text);
        buffer.clear();
      }
    }

    for (final segment in segments) {
      final line =
          '[${_formatTimestamp(segment.startSeconds)}] '
          '${segment.speakerId.isEmpty ? 'Speaker' : segment.speakerId}: '
          '${segment.text.trim()}';
      if (buffer.isNotEmpty &&
          buffer.length + line.length + 1 > _meetingTranscriptChunkRunes) {
        flush();
      }
      if (line.runes.length > _meetingTranscriptChunkRunes) {
        flush();
        chunks.addAll(_splitRunes(line, _meetingTranscriptChunkRunes));
      } else {
        buffer.writeln(line);
      }
    }
    flush();
    return chunks;
  }

  List<MeetingTopicSegment> _parseTopicSegments(
    String text,
    List<MeetingTranscriptSegment> transcriptSegments,
  ) {
    final parsed = <MeetingTopicSegment>[];
    for (final line in _parseBulletLines(text)) {
      final match = RegExp(
        r'^(\d{1,2}:\d{2}(?::\d{2})?)\s+(.+?)(?:\s+-\s+(.+))?$',
      ).firstMatch(line);
      if (match == null) {
        continue;
      }
      parsed.add(
        MeetingTopicSegment(
          startSeconds: _parseTimestamp(match.group(1) ?? '0:00'),
          title: (match.group(2) ?? '').trim(),
          summary: (match.group(3) ?? '').trim(),
        ),
      );
    }
    return parsed.isEmpty ? _fallbackTopicSegments(transcriptSegments) : parsed;
  }

  List<MeetingTopicSegment> _fallbackTopicSegments(
    List<MeetingTranscriptSegment> segments,
  ) {
    if (segments.isEmpty) {
      return const <MeetingTopicSegment>[];
    }
    final result = <MeetingTopicSegment>[];
    for (var i = 0; i < segments.length; i += 6) {
      final chunk = segments.skip(i).take(6).toList(growable: false);
      final text = chunk.map((segment) => segment.text).join(' ');
      result.add(
        MeetingTopicSegment(
          startSeconds: chunk.first.startSeconds,
          title: _takeRunes(text.replaceAll(RegExp(r'\s+'), ' ').trim(), 28),
          summary: _takeRunes(text.replaceAll(RegExp(r'\s+'), ' ').trim(), 90),
        ),
      );
    }
    return result.take(8).toList(growable: false);
  }

  List<MeetingNoteSet> _buildFallbackNoteSets(
    String summary,
    String todos,
    String transcription,
  ) {
    return <MeetingNoteSet>[
      MeetingNoteSet(title: useEnglish ? 'Overview' : '概要', body: summary),
      MeetingNoteSet(
        title: useEnglish ? 'Source notes' : '原文メモ',
        body: _takeRunes(transcription, 900),
      ),
    ].where((noteSet) => noteSet.body.trim().isNotEmpty).toList();
  }

  List<String> _buildAskSuggestions(String summary, String todos) {
    if (useEnglish) {
      return const <String>[
        'Summarize only the decisions from this meeting',
        'List next actions in priority order',
        'Show unresolved issues and points to confirm',
        'Draft a short update for stakeholders',
        'Identify risks and countermeasures from this meeting',
      ];
    }
    return const <String>[
      'この会議の決定事項だけを整理して',
      '次にやるべきことを優先順位順にして',
      '未決事項と確認が必要な点を教えて',
      '関係者へ送る短い共有文を作って',
      'この会議のリスクと対策を出して',
    ];
  }

  List<MeetingMindMapNode> _buildFallbackMindMap(
    String summary,
    String todos,
    List<MeetingTopicSegment> topicSegments,
  ) {
    final todoNodes = MeetingTodoItem.fromText(todos)
        .take(4)
        .map(
          (todo) => MeetingMindMapNode(
            label: _takeRunes(todo.text, 34),
            children: _extractOwnerFromTodo(todo.text).isEmpty
                ? const <MeetingMindMapNode>[]
                : <MeetingMindMapNode>[
                    MeetingMindMapNode(label: _extractOwnerFromTodo(todo.text)),
                  ],
          ),
        )
        .toList(growable: false);
    final summaryNodes = _parseBulletLines(summary)
        .take(4)
        .map((line) => MeetingMindMapNode(label: _takeRunes(line, 42)))
        .toList(growable: false);
    final children = <MeetingMindMapNode>[
      for (final topic in topicSegments.take(4))
        MeetingMindMapNode(
          label: topic.title,
          children: topic.summary.trim().isEmpty
              ? const <MeetingMindMapNode>[]
              : <MeetingMindMapNode>[
                  MeetingMindMapNode(
                    label: _takeRunes(topic.summary.trim(), 42),
                  ),
                ],
        ),
      if (todoNodes.isNotEmpty)
        MeetingMindMapNode(
          label: strings.t('meeting.todo'),
          children: todoNodes,
        ),
      if (summaryNodes.isNotEmpty)
        MeetingMindMapNode(
          label: strings.t('meeting.summary'),
          children: summaryNodes,
        ),
    ];
    return <MeetingMindMapNode>[
      MeetingMindMapNode(
        label: _deriveTitleFromSummary(summary),
        children: children,
      ),
    ];
  }

  Future<List<MeetingMindMapNode>> _generateMeetingMindMap(
    _MeetingAsset model,
    String summary,
    String todos,
    String transcription, {
    String? sessionId,
  }) async {
    if (sessionId != null) {
      _setProcessingStage(
        sessionId,
        strings.t('meeting.stage.summarizing'),
        'Organizing the mind map',
      );
    }
    final output = await _generateText(
      model,
      '''Generate only a mind map from this meeting.

Strict rules:
- Output 3 to 8 lines.
- Each line must use exactly: central topic > subtopic > key point
- Do not include headings, explanations, bullet marks, translations, or raw TODO text.
- Use the real meeting content and avoid repeating generic labels.

# Summary
$summary

# TODO
$todos

# Transcript
${_takeRunes(transcription, _meetingPromptTranscriptRunes)}''',
      maxTokens: 360,
    );
    return _parseMindMap(output);
  }

  bool _hasUsefulMindMap(List<MeetingMindMapNode> nodes) {
    if (nodes.isEmpty) {
      return false;
    }
    var usefulLabels = 0;
    void visit(MeetingMindMapNode node) {
      final label = node.label.trim();
      if (label.runes.length >= 3 &&
          !RegExp(
            r'^(会議|Meeting|中心トピック|子トピック|要点|MindMap)$',
            caseSensitive: false,
          ).hasMatch(label)) {
        usefulLabels++;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return usefulLabels >= 2;
  }

  String _extractOwnerFromTodo(String text) {
    final match = RegExp(
      r'(?:担当|owner|Owner|assignee)[:：]\s*([^、,。]+)',
    ).firstMatch(text);
    return match?.group(1)?.trim() ?? '';
  }

  List<String> _parseBulletLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim().replaceFirst(RegExp(r'^[・\-\*\d.、\s]+'), ''))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  List<MeetingMindMapNode> _parseMindMap(String text) {
    final root = _MutableMindMapNode('');
    for (final line in _parseBulletLines(text)) {
      final parts = line
          .replaceAll('＞', '>')
          .replaceAll('→', '>')
          .replaceAll('->', '>')
          .replaceAll('=>', '>')
          .split(RegExp(r'\s*(?:>|/|／|｜|\|)\s*'))
          .map((part) => part.trim())
          .map(
            (part) => part
                .replaceFirst(RegExp(r'^(中心トピック|子トピック|要点)\s*[:：]\s*'), '')
                .trim(),
          )
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) {
        continue;
      }
      _insertMindMapPath(root, parts.take(5).toList(growable: false));
    }
    if (root.children.isEmpty) {
      return const <MeetingMindMapNode>[];
    }
    if (root.children.length == 1) {
      return <MeetingMindMapNode>[root.children.first.toImmutable()];
    }
    return <MeetingMindMapNode>[
      MeetingMindMapNode(
        label: useEnglish ? 'Meeting' : '会議',
        children: root.children
            .take(8)
            .map((child) => child.toImmutable())
            .toList(growable: false),
      ),
    ];
  }

  void _insertMindMapPath(_MutableMindMapNode root, List<String> path) {
    var current = root;
    for (final label in path) {
      current = current.child(label);
    }
  }

  Map<String, String> _fallbackMeetingTranslations(String summaryText) {
    return <String, String>{
      'en':
          'The meeting content has been organized. Review the summary, action items, and transcript to confirm the important points.',
      'ja': '会議内容を整理しました。要約、TODO、原文記録を確認して重要な点を見直してください。',
      'zh': '会议内容已整理。请查看摘要、待办事项和原文记录确认重点。',
      'ko': '회의 내용이 정리되었습니다. 요약, 할 일, 원문 기록을 확인해 핵심 내용을 검토하세요.',
    };
  }

  String _bestSummaryForTranslation(
    MeetingSession session,
    String summaryOverride,
  ) {
    final candidates = <String>[
      summaryOverride,
      session.templateOutputs[session.templateId] ?? '',
      session.summary,
      session.todos,
      session.cleanTranscription,
      session.transcription,
    ];
    for (final candidate in candidates) {
      final cleaned = _cleanModelText(candidate).trim();
      if (cleaned.isNotEmpty) {
        return _takeRunes(cleaned, 2200);
      }
    }
    return '';
  }

  String _extractSection(String text, String heading) {
    final headings = <String>[
      '要約',
      'Summary',
      'TODO',
      'ToDo',
      'タイムライン',
      'Timeline',
      '論点',
      'Discussion Points',
      'Issues',
      '決定事項',
      'Decisions',
      'Ask',
      'MindMap',
      'Mind Map',
      'English',
      '中文',
      '한국어',
    ];
    final aliases = switch (heading) {
      '要約' => const <String>['要約', 'Summary'],
      'TODO' => const <String>['TODO', 'ToDo', 'To Do', 'タスク', 'アクションアイテム'],
      'タイムライン' => const <String>['タイムライン', 'Timeline'],
      '論点' => const <String>['論点', 'Discussion Points', 'Issues'],
      '決定事項' => const <String>['決定事項', 'Decisions'],
      'MindMap' => const <String>['MindMap', 'Mind Map', 'マインドマップ'],
      'English' => const <String>['English', '英語'],
      '中文' => const <String>['中文', '中国語', '简体中文'],
      '한국어' => const <String>['한국어', '韓国語'],
      _ => <String>[heading],
    };
    final headingPattern = aliases.map(RegExp.escape).join('|');
    final boundaryPattern = headings.map(RegExp.escape).join('|');
    final match = RegExp(
      '(?:^|\\n)\\s*(?:#{1,4}\\s*)?(?:$headingPattern)\\s*[:：]?\\s*(?:\\n|\\r\\n)([\\s\\S]*?)(?=\\n\\s*(?:#{1,4}\\s*)?(?:$boundaryPattern)\\s*[:：]?\\s*(?:\\n|\\r\\n)|\\z)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      return match.group(1)?.trim() ?? '';
    }
    final inlineMatch = RegExp(
      '(?:^|\\n)\\s*(?:#{1,4}\\s*)?(?:$headingPattern)\\s*[:：]\\s*([^\\n]+)',
      caseSensitive: false,
    ).firstMatch(text);
    return inlineMatch?.group(1)?.trim() ?? '';
  }

  String _deriveTitleFromSummary(String summary) {
    if (summary.isEmpty) return strings.t('meeting.uncategorized');
    final lines = summary.split('\n');
    for (final line in lines) {
      if (line.trim().isNotEmpty && !line.startsWith('#')) {
        var title = line.trim();
        if (title.length > 20) {
          title = '${title.substring(0, 20)}...';
        }
        return title;
      }
    }
    return strings.t('nav.meetings');
  }

  String _takeRunes(String text, int maxRunes) {
    if (text.runes.length <= maxRunes) {
      return text;
    }
    return String.fromCharCodes(text.runes.take(maxRunes));
  }

  List<String> _splitRunes(String text, int maxRunes) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }
    final result = <String>[];
    var current = StringBuffer();
    var currentRunes = 0;
    for (final line in normalized.split('\n')) {
      final lineRunes = line.runes.length;
      if (lineRunes > maxRunes) {
        if (currentRunes > 0) {
          result.add(current.toString().trim());
          current = StringBuffer();
          currentRunes = 0;
        }
        final runes = line.runes.toList(growable: false);
        for (var start = 0; start < runes.length; start += maxRunes) {
          result.add(
            String.fromCharCodes(runes.skip(start).take(maxRunes)).trim(),
          );
        }
        continue;
      }
      if (currentRunes > 0 && currentRunes + lineRunes + 1 > maxRunes) {
        result.add(current.toString().trim());
        current = StringBuffer();
        currentRunes = 0;
      }
      current.writeln(line);
      currentRunes += lineRunes + 1;
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) {
      result.add(tail);
    }
    return result;
  }

  String _formatTimestamp(double seconds) {
    final total = seconds.round().clamp(0, 24 * 60 * 60);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  double _parseTimestamp(String value) {
    final parts = value
        .split(':')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    if (parts.length == 3) {
      return (parts[0] * 3600 + parts[1] * 60 + parts[2]).toDouble();
    }
    if (parts.length == 2) {
      return (parts[0] * 60 + parts[1]).toDouble();
    }
    return 0;
  }

  @override
  void dispose() {
    unawaited(_releaseMeetingGenAi());
    unawaited(_audioRuntime.dispose());
    _micRecorder.dispose();
    super.dispose();
  }
}

class _MeetingAsset {
  const _MeetingAsset(this.id, this.path);

  final String id;
  final String path;
}

class _MutableMindMapNode {
  _MutableMindMapNode(this.label);

  final String label;
  final List<_MutableMindMapNode> children = <_MutableMindMapNode>[];

  _MutableMindMapNode child(String value) {
    final normalized = value.trim();
    for (final node in children) {
      if (node.label == normalized) {
        return node;
      }
    }
    final created = _MutableMindMapNode(normalized);
    children.add(created);
    return created;
  }

  MeetingMindMapNode toImmutable() {
    return MeetingMindMapNode(
      label: label,
      children: children
          .take(8)
          .map((child) => child.toImmutable())
          .toList(growable: false),
    );
  }
}

class _MeetingTranscription {
  const _MeetingTranscription({required this.text, required this.segments});

  final String text;
  final List<MeetingTranscriptSegment> segments;
}

Future<Map<String, Object?>> _runMeetingWhisperStt(
  Map<String, String> request,
) async {
  final audioPath = request['audioPath'] ?? '';
  final modelPath = request['modelPath'] ?? '';
  final runtime = essential.EssentialAudioRuntime();
  try {
    if (!runtime.isAvailable) {
      await runtime.initialize();
    }
    final response = await runtime.execute(
      essential.EssentialTaskRequest(
        id: 'meeting-stt-${DateTime.now().microsecondsSinceEpoch}',
        taskType: essential.EssentialTaskType.stt,
        payload: essential.EssentialAudioTaskPayload(audioFilePath: audioPath),
        modelRequirement: essential.EssentialModelRequirement(
          family: essential.EssentialRuntimeFamily.onnx.wireName,
          capability: essential.EssentialTaskType.stt.wireName,
          explicitModelPath: modelPath,
        ),
        metadata: const <String, Object?>{'language': 'auto'},
      ),
      essential.EssentialTaskRoutingDecision(
        capability: essential.EssentialCapabilityDescriptor(
          capabilityId: 'meeting.audio.whisper_file_stt',
          supportedTaskTypes: const <essential.EssentialTaskType>[
            essential.EssentialTaskType.stt,
          ],
          runtimeFamily: essential.EssentialRuntimeFamily.onnx,
          inputModalities: const <String>['audio'],
          outputModalities: const <String>['text'],
        ),
        runtimeFamily: essential.EssentialRuntimeFamily.onnx,
        runtimeAvailable: runtime.isAvailable,
        fallbackRuntimeFamilies: const <essential.EssentialRuntimeFamily>[],
      ),
    );
    return <String, Object?>{
      'text': response.result.text?.trim() ?? '',
      'segments': response.result.metadata['segments'],
    };
  } finally {
    await runtime.dispose();
  }
}
