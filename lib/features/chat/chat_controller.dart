import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:essential_sdk_dart/essential_sdk_dart.dart' as essential;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../shared/web_research_service.dart';

enum ChatMessageRole { user, assistant }

enum ChatAttachmentType { image, audio, location }

enum ChatPromptFormat { generic, gemmaStartTurn, gemma4Turn, chatMl }

enum ChatAttachmentStatus { pending, processing, complete, failed }

class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    this.address,
    this.accuracy,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
    );
  }

  final double latitude;
  final double longitude;
  final String? address;
  final double? accuracy;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'accuracy': accuracy,
    };
  }
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.type,
    this.filePath,
    this.location,
    this.caption,
    this.transcription,
    this.analysisLabels = const <String>[],
    this.detectedObjects = const <String>[],
    this.progress = 1,
    this.status = ChatAttachmentStatus.complete,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String,
      type: ChatAttachmentType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => ChatAttachmentType.image,
      ),
      filePath: json['file_path'] as String?,
      location: json['location'] == null
          ? null
          : LocationData.fromJson(json['location'] as Map<String, dynamic>),
      caption: json['caption'] as String?,
      transcription: json['transcription'] as String?,
      analysisLabels: _cleanAttachmentLabels(
        (json['analysis_labels'] as List<dynamic>? ?? <dynamic>[])
            .cast<String>(),
      ),
      detectedObjects: _cleanAttachmentLabels(
        (json['detected_objects'] as List<dynamic>? ?? <dynamic>[])
            .cast<String>(),
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 1,
      status: ChatAttachmentStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => ChatAttachmentStatus.complete,
      ),
    );
  }

  final String id;
  final ChatAttachmentType type;
  final String? filePath;
  final LocationData? location;
  final String? caption;
  final String? transcription;
  final List<String> analysisLabels;
  final List<String> detectedObjects;
  final double progress;
  final ChatAttachmentStatus status;

  bool get isProcessing => status == ChatAttachmentStatus.processing;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'file_path': filePath,
      'location': location?.toJson(),
      'caption': caption,
      'transcription': transcription,
      'analysis_labels': analysisLabels,
      'detected_objects': detectedObjects,
      'progress': progress,
      'status': status.name,
    };
  }
}

List<String> _cleanAttachmentLabels(List<String> labels) {
  return labels
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .where(
        (label) =>
            !label.contains('Exception') &&
            !label.contains('RUNTIME_UNAVAILABLE') &&
            !label.contains('runtime unavailable') &&
            !label.contains('Vision runtime'),
      )
      .toList(growable: false);
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.attachments = const <ChatAttachment>[],
    this.webSources = const <WebSource>[],
    this.progressLabel,
    this.isStreaming = false,
    this.isError = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: (json['role'] as String) == 'user'
          ? ChatMessageRole.user
          : ChatMessageRole.assistant,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      attachments: (json['attachments'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (dynamic row) =>
                ChatAttachment.fromJson(row as Map<String, dynamic>),
          )
          .toList(),
      webSources: (json['web_sources'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((row) => WebSource.fromJson(Map<String, dynamic>.from(row)))
          .where((source) => source.isUseful)
          .toList(),
      progressLabel: json['progress_label'] as String?,
      isStreaming: json['is_streaming'] as bool? ?? false,
      isError: json['is_error'] as bool? ?? false,
    );
  }

  final String id;
  final ChatMessageRole role;
  final String text;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final List<WebSource> webSources;
  final String? progressLabel;
  final bool isStreaming;
  final bool isError;

  ChatMessage copyWith({
    String? text,
    List<ChatAttachment>? attachments,
    List<WebSource>? webSources,
    Object? progressLabel = _unchanged,
    bool? isStreaming,
    bool? isError,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      attachments: attachments ?? this.attachments,
      webSources: webSources ?? this.webSources,
      progressLabel: progressLabel == _unchanged
          ? this.progressLabel
          : progressLabel as String?,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'role': role == ChatMessageRole.user ? 'user' : 'assistant',
      'text': text,
      'created_at': createdAt.toIso8601String(),
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'web_sources': webSources.map((item) => item.toJson()).toList(),
      'progress_label': progressLabel,
      'is_streaming': isStreaming,
      'is_error': isError,
    };
  }
}

const Object _unchanged = Object();

class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.selectedModelId,
    this.sharedMemoryEnabled = true,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rows = json['messages'] as List<dynamic>? ?? <dynamic>[];
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新しいチャット',
      updatedAt: DateTime.parse(json['updated_at'] as String),
      selectedModelId: json['selected_model_id'] as String?,
      sharedMemoryEnabled: json['shared_memory_enabled'] as bool? ?? true,
      messages: rows
          .map(
            (dynamic row) => ChatMessage.fromJson(row as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final String id;
  final String title;
  final DateTime updatedAt;
  final String? selectedModelId;
  final bool sharedMemoryEnabled;
  final List<ChatMessage> messages;

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    String? selectedModelId,
    bool clearSelectedModel = false,
    bool? sharedMemoryEnabled,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedModelId: clearSelectedModel
          ? null
          : selectedModelId ?? this.selectedModelId,
      sharedMemoryEnabled: sharedMemoryEnabled ?? this.sharedMemoryEnabled,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'updated_at': updatedAt.toIso8601String(),
      'selected_model_id': selectedModelId,
      'shared_memory_enabled': sharedMemoryEnabled,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }
}

class SharedMemoryItem {
  const SharedMemoryItem({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory SharedMemoryItem.fromJson(Map<String, dynamic> json) {
    return SharedMemoryItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ChatController extends ChangeNotifier {
  ChatController({this.taskRouter});

  static const int sharedMemoryPromptRuneLimit = 2000;
  static const int sharedMemoryStorageRuneLimit = 12000;
  static const int sharedMemoryCompressedRuneTarget = 6000;

  final essential.EssentialTaskRouterFacade? taskRouter;

  bool _isReady = false;
  bool _isLoading = false;
  File? _storageFile;
  List<ChatSession> _sessions = <ChatSession>[];
  final List<SharedMemoryItem> _sharedMemories = <SharedMemoryItem>[];
  String? _currentSessionId;

  bool get isReady => _isReady;

  bool get isLoading => _isLoading;

  List<ChatSession> get sessions {
    final sortedSessions = List<ChatSession>.from(_sessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<ChatSession>.unmodifiable(sortedSessions);
  }

  List<SharedMemoryItem> get sharedMemories =>
      List<SharedMemoryItem>.unmodifiable(_sharedMemories);

  bool get currentSharedMemoryEnabled =>
      currentSession?.sharedMemoryEnabled ?? true;

  ChatSession? get currentSession {
    final sessionId = _currentSessionId;
    if (sessionId == null) {
      return null;
    }
    for (final session in _sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  Future<void> initialize({String? initialModelId}) async {
    if (_isReady || _isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    final directory = await getApplicationSupportDirectory();
    _storageFile = File(
      path.join(directory.path, 'essential_chat_sessions.json'),
    );

    if (await _storageFile!.exists()) {
      final payload =
          jsonDecode(await _storageFile!.readAsString())
              as Map<String, dynamic>;
      final rows = payload['sessions'] as List<dynamic>? ?? <dynamic>[];
      final memoryRows =
          payload['shared_memories'] as List<dynamic>? ?? <dynamic>[];
      _sessions = rows
          .map(
            (dynamic row) => ChatSession.fromJson(row as Map<String, dynamic>),
          )
          .toList();
      _sharedMemories
        ..clear()
        ..addAll(
          memoryRows.map(
            (dynamic row) =>
                SharedMemoryItem.fromJson(row as Map<String, dynamic>),
          ),
        );
      _currentSessionId = payload['current_session_id'] as String?;
    }

    if (_sessions.isEmpty) {
      final session = _createSessionModel(initialModelId: initialModelId);
      _sessions = <ChatSession>[session];
      _currentSessionId = session.id;
      await _persist();
    } else if (_currentSessionId == null ||
        !_sessions.any((session) => session.id == _currentSessionId)) {
      _currentSessionId = _sessions.first.id;
    }

    _isLoading = false;
    _isReady = true;
    notifyListeners();
  }

  Future<void> createSession({String? preferredModelId}) async {
    final session = _createSessionModel(initialModelId: preferredModelId);
    _sessions = <ChatSession>[session, ..._sessions];
    _currentSessionId = session.id;
    notifyListeners();
    await _persist();
  }

  Future<void> selectSession(String sessionId) async {
    if (_currentSessionId == sessionId) {
      return;
    }
    _currentSessionId = sessionId;
    notifyListeners();
    await _persist();
  }

  Future<void> deleteSession(
    String sessionId, {
    String? fallbackModelId,
  }) async {
    _sessions = _sessions.where((session) => session.id != sessionId).toList();
    if (_sessions.isEmpty) {
      final replacement = _createSessionModel(initialModelId: fallbackModelId);
      _sessions = <ChatSession>[replacement];
      _currentSessionId = replacement.id;
    } else if (_currentSessionId == sessionId) {
      _currentSessionId = _sessions.first.id;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> updateCurrentModel(String? modelId) async {
    final session = currentSession;
    if (session == null || session.selectedModelId == modelId) {
      return;
    }
    _updateSession(
      session.id,
      (current) =>
          current.copyWith(selectedModelId: modelId, updatedAt: DateTime.now()),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> clearUnavailableCurrentModel() async {
    final session = currentSession;
    if (session == null || session.selectedModelId == null) {
      return;
    }
    _updateSession(
      session.id,
      (current) =>
          current.copyWith(clearSelectedModel: true, updatedAt: DateTime.now()),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setCurrentSharedMemoryEnabled(bool enabled) async {
    final session = currentSession;
    if (session == null || session.sharedMemoryEnabled == enabled) {
      return;
    }
    _updateSession(
      session.id,
      (current) => current.copyWith(
        sharedMemoryEnabled: enabled,
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> addSharedMemory(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (_hasSimilarSharedMemory(normalized)) {
      return;
    }
    _sharedMemories.insert(
      0,
      SharedMemoryItem(
        id: _buildId(),
        text: normalized,
        createdAt: DateTime.now(),
      ),
    );
    if (_sharedMemories.length > 80) {
      _sharedMemories.removeRange(80, _sharedMemories.length);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> updateSharedMemoryFromCurrentSession() async {
    await summarizeAndWriteSharedMemoryFromCurrentSession();
  }

  Future<void> summarizeAndWriteSharedMemoryFromCurrentSession({
    Future<String> Function(String prompt)? summarize,
  }) async {
    final session = currentSession;
    if (session == null || !session.sharedMemoryEnabled) {
      return;
    }
    final section = _sessionSectionForMemory(session);
    if (section.isEmpty) {
      return;
    }
    await summarizeAndWriteSharedMemorySection(
      section,
      enabled: session.sharedMemoryEnabled,
      summarize: summarize,
      fallbackLines: _memoryCandidatesForSession(session),
    );
  }

  Future<void> summarizeAndWriteSharedMemorySection(
    String section, {
    required bool enabled,
    Future<String> Function(String prompt)? summarize,
    List<String> fallbackLines = const <String>[],
  }) async {
    if (!enabled) {
      return;
    }
    final normalizedSection = section.trim();
    if (normalizedSection.isEmpty) {
      return;
    }
    var summary = '';
    if (summarize != null) {
      try {
        summary = (await summarize(
          _memorySummaryPrompt(normalizedSection),
        )).trim();
      } catch (error) {
        debugPrint('Shared memory AI summarization failed: $error');
      }
    }
    summary = _normalizeGeneratedMemory(summary);
    if (summary.isEmpty) {
      summary = fallbackLines.join('\n').trim();
    }
    if (summary.isEmpty) {
      summary = _takeRunes(normalizedSection, 1200);
    }
    if (summary.isEmpty ||
        _isLowValueSharedMemory(summary) ||
        _hasSimilarSharedMemory(summary)) {
      return;
    }
    _sharedMemories.insert(
      0,
      SharedMemoryItem(
        id: _buildId(),
        text: summary,
        createdAt: DateTime.now(),
      ),
    );
    await _compactSharedMemoryIfNeeded(summarize: summarize);
    notifyListeners();
    await _persist();
  }

  String buildSharedMemoryPromptContext({
    bool respectCurrentSessionToggle = true,
  }) {
    final session = currentSession;
    if (_sharedMemories.isEmpty) {
      return '';
    }
    if (respectCurrentSessionToggle &&
        (session == null || !session.sharedMemoryEnabled)) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln(
        '共有メモリーは過去の会話から圧縮された参考情報です。現在のユーザー発話ではありません。関連するときだけ静かに参考にし、挨拶・冒頭文・今回の依頼として扱わないでください。この欄自体は説明しないでください:',
      );
    for (final memory in _sharedMemories) {
      if (_isLowValueSharedMemory(memory.text)) {
        continue;
      }
      buffer.writeln('- ${memory.text}');
      if (buffer.toString().runes.length >= sharedMemoryPromptRuneLimit) {
        break;
      }
    }
    return _takeRunes(buffer.toString().trim(), sharedMemoryPromptRuneLimit);
  }

  Future<void> deleteSharedMemory(String id) async {
    _sharedMemories.removeWhere((memory) => memory.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> addUserMessage(String text) async {
    await addUserMultimodalMessage(text: text);
  }

  Future<void> addUserMultimodalMessage({
    String text = '',
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    final session = currentSession;
    if (session == null) {
      return;
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty && attachments.isEmpty) {
      return;
    }
    final message = ChatMessage(
      id: _buildId(),
      role: ChatMessageRole.user,
      text: trimmedText,
      attachments: attachments,
      createdAt: DateTime.now(),
    );

    _updateSession(session.id, (current) {
      final nextMessages = <ChatMessage>[...current.messages, message];
      return current.copyWith(
        title: _deriveTitle(current.title, nextMessages),
        updatedAt: DateTime.now(),
        messages: nextMessages,
      );
    });
    notifyListeners();
    await _persist();
  }

  Future<void> sendImageMessage(File image, {String? caption}) async {
    await addUserMultimodalMessage(
      text: caption ?? '',
      attachments: <ChatAttachment>[
        ChatAttachment(
          id: _buildId(),
          type: ChatAttachmentType.image,
          filePath: image.path,
          caption: caption,
          analysisLabels: const <String>['画像を添付しました'],
          status: ChatAttachmentStatus.complete,
          progress: 1,
        ),
      ],
    );
  }

  Future<void> sendAudioMessage(File audio) async {
    String? transcription;
    var status = ChatAttachmentStatus.complete;
    try {
      final response = await taskRouter?.routeAudioTask(
        essential.SttTaskRequest(
          requestId: _buildId(),
          audioFilePath: audio.path,
        ),
      );
      transcription = response?.result.text;
    } catch (_) {
      status = ChatAttachmentStatus.failed;
    }
    await addUserMultimodalMessage(
      text: transcription ?? '',
      attachments: <ChatAttachment>[
        ChatAttachment(
          id: _buildId(),
          type: ChatAttachmentType.audio,
          filePath: audio.path,
          transcription: transcription,
          status: status,
          progress: 1,
        ),
      ],
    );
  }

  Future<void> sendLocationMessage(LocationData location) async {
    await addUserMultimodalMessage(
      attachments: <ChatAttachment>[
        ChatAttachment(
          id: _buildId(),
          type: ChatAttachmentType.location,
          location: location,
          status: ChatAttachmentStatus.complete,
        ),
      ],
    );
  }

  Future<void> startVoiceConversation() async {
    await addUserMultimodalMessage(text: '音声会話を開始しました。');
  }

  Stream<String> streamMultimodalResponse(
    List<ChatAttachment> attachments,
    String text,
  ) async* {
    final prompt = StringBuffer(text.trim());
    for (final attachment in attachments) {
      prompt.write(
        '\n[${attachment.type.name}: ${attachment.filePath ?? attachment.location?.address ?? attachment.id}]',
      );
    }
    yield prompt.toString();
  }

  String startAssistantMessage({String progressLabel = '回答準備中'}) {
    final session = currentSession;
    if (session == null) {
      throw StateError('No chat session selected.');
    }

    final message = ChatMessage(
      id: _buildId(),
      role: ChatMessageRole.assistant,
      text: '',
      createdAt: DateTime.now(),
      progressLabel: progressLabel,
      isStreaming: true,
    );

    _updateSession(
      session.id,
      (current) => current.copyWith(
        updatedAt: DateTime.now(),
        messages: <ChatMessage>[...current.messages, message],
      ),
    );
    notifyListeners();
    return message.id;
  }

  void appendAssistantChunk(String messageId, String chunk) {
    final session = currentSession;
    if (session == null) {
      return;
    }
    _updateMessage(
      session.id,
      messageId,
      (message) => message.copyWith(text: '${message.text}$chunk'),
    );
    notifyListeners();
  }

  void updateAssistantProgress(String messageId, String label) {
    final session = currentSession;
    if (session == null) {
      return;
    }
    final normalized = label.trim();
    if (normalized.isEmpty) {
      return;
    }
    _updateMessage(
      session.id,
      messageId,
      (message) => message.copyWith(progressLabel: normalized),
    );
    notifyListeners();
  }

  void updateAssistantWebSources(String messageId, List<WebSource> webSources) {
    final session = currentSession;
    if (session == null || webSources.isEmpty) {
      return;
    }
    _updateMessage(
      session.id,
      messageId,
      (message) => message.copyWith(webSources: webSources),
    );
    notifyListeners();
  }

  void resetAssistantMessage(String messageId) {
    final session = currentSession;
    if (session == null) {
      return;
    }
    _updateMessage(
      session.id,
      messageId,
      (message) => message.copyWith(
        text: '',
        progressLabel: '再試行中',
        isStreaming: true,
        isError: false,
      ),
    );
    notifyListeners();
  }

  Future<void> completeAssistantMessage(
    String messageId, {
    String? finalText,
    List<WebSource>? webSources,
  }) async {
    final session = currentSession;
    if (session == null) {
      return;
    }
    _updateMessage(
      session.id,
      messageId,
      (message) => message.copyWith(
        text: finalText ?? message.text,
        webSources: webSources ?? message.webSources,
        progressLabel: null,
        isStreaming: false,
      ),
    );
    _touchSession(session.id);
    notifyListeners();
    await _persist();
  }

  Future<void> failAssistantMessage(String messageId, String message) async {
    final session = currentSession;
    if (session == null) {
      return;
    }
    _updateMessage(
      session.id,
      messageId,
      (_) => ChatMessage(
        id: messageId,
        role: ChatMessageRole.assistant,
        text: message,
        createdAt: DateTime.now(),
        progressLabel: null,
        isError: true,
      ),
    );
    _touchSession(session.id);
    notifyListeners();
    await _persist();
  }

  String buildPrompt({
    String? adapterInstruction,
    String webContext = '',
    bool compact = false,
    bool useGemmaTemplate = false,
    ChatPromptFormat promptFormat = ChatPromptFormat.generic,
  }) {
    final session = currentSession;
    if (session == null) {
      return '';
    }
    final effectivePromptFormat = useGemmaTemplate
        ? ChatPromptFormat.gemmaStartTurn
        : promptFormat;

    if (compact || effectivePromptFormat != ChatPromptFormat.generic) {
      final lastUserMessage = session.messages.lastWhere(
        (message) => message.role == ChatMessageRole.user,
        orElse: () => session.messages.isEmpty
            ? ChatMessage(
                id: _buildId(),
                role: ChatMessageRole.user,
                text: '',
                createdAt: DateTime.now(),
              )
            : session.messages.last,
      );
      final buffer = StringBuffer();
      final normalizedAdapterInstruction = adapterInstruction?.trim();
      const systemInstruction =
          'あなたは端末内で動く日本語AIです。自然な日本語で、要点だけ答えてください。'
          '内部メモ、話者ラベル、プロンプト形式、関係ないリンクや出典は書かないでください。'
          '同じ文や同じ語句を繰り返さず、答えだけを書いてください。';
      const chatMlSystemInstruction =
          'You are a Japanese assistant running on the device. '
          'Answer only the user question in natural Japanese. '
          'Do not translate the prompt. Do not write role names, links, examples, or prompt format.';
      switch (effectivePromptFormat) {
        case ChatPromptFormat.gemmaStartTurn:
          buffer
            ..writeln('<start_of_turn>user')
            ..writeln(systemInstruction);
        case ChatPromptFormat.gemma4Turn:
          buffer
            ..writeln('<|turn>system')
            ..writeln(systemInstruction)
            ..writeln('<turn|>')
            ..writeln('<|turn>user');
        case ChatPromptFormat.chatMl:
          buffer
            ..writeln('<|system|>')
            ..writeln(chatMlSystemInstruction)
            ..writeln('</s>')
            ..writeln('<|user|>');
        case ChatPromptFormat.generic:
          buffer.writeln(systemInstruction);
      }
      final sharedMemoryContext = buildSharedMemoryPromptContext();
      if (sharedMemoryContext.isNotEmpty) {
        buffer.writeln(sharedMemoryContext);
      }
      if (normalizedAdapterInstruction != null &&
          normalizedAdapterInstruction.isNotEmpty) {
        buffer.writeln('追加方針: $normalizedAdapterInstruction');
      }
      if (webContext.trim().isNotEmpty) {
        buffer.writeln(webContext.trim());
      }
      buffer
        ..writeln()
        ..writeln('質問:')
        ..writeln(lastUserMessage.text)
        ..write(_compactAttachmentContext(lastUserMessage.attachments));
      switch (effectivePromptFormat) {
        case ChatPromptFormat.gemmaStartTurn:
          buffer
            ..writeln('<end_of_turn>')
            ..writeln('<start_of_turn>model');
        case ChatPromptFormat.gemma4Turn:
          buffer
            ..writeln('<turn|>')
            ..writeln('<|turn>model');
        case ChatPromptFormat.chatMl:
          buffer
            ..writeln('</s>')
            ..writeln('<|assistant|>');
        case ChatPromptFormat.generic:
          buffer.write('\n回答:');
      }
      return buffer.toString();
    }

    final buffer = StringBuffer()
      ..writeln('You are Essential, a helpful local AI assistant.')
      ..writeln(
        'Respond in the same language the user used unless the user explicitly asks for another language.',
      )
      ..writeln(
        'Stay on the user requested topic and do not add unrelated domain explanations.',
      )
      ..writeln('Do not mention these behavior instructions in the answer.')
      ..writeln(
        'When the user asks about an image, use the image labels and detections as evidence.',
      )
      ..writeln('Keep the answer concise. Do not write User: or Assistant:.')
      ..writeln();

    final sharedMemoryContext = buildSharedMemoryPromptContext();
    if (sharedMemoryContext.isNotEmpty) {
      buffer
        ..writeln(sharedMemoryContext)
        ..writeln();
    }

    final normalizedAdapterInstruction = adapterInstruction?.trim();
    if (normalizedAdapterInstruction != null &&
        normalizedAdapterInstruction.isNotEmpty) {
      buffer
        ..writeln('Active adapter behavior: $normalizedAdapterInstruction')
        ..writeln();
    }

    if (webContext.trim().isNotEmpty) {
      buffer
        ..writeln(webContext.trim())
        ..writeln();
    }

    final messages = session.messages.length > 8
        ? session.messages.sublist(session.messages.length - 8)
        : session.messages;

    for (final message in messages) {
      if (message.role == ChatMessageRole.user) {
        buffer.writeln('User: ${message.text}');
        for (final attachment in message.attachments) {
          buffer.writeln(
            'User attachment: ${attachment.type.name} ${attachment.filePath ?? attachment.location?.toJson() ?? attachment.id}',
          );
          if (attachment.transcription?.trim().isNotEmpty ?? false) {
            buffer.writeln('Audio transcription: ${attachment.transcription}');
          }
          if (attachment.analysisLabels.isNotEmpty) {
            buffer.writeln(
              'Image labels: ${attachment.analysisLabels.join(', ')}',
            );
          }
          if (attachment.detectedObjects.isNotEmpty) {
            buffer.writeln(
              'Detected objects: ${attachment.detectedObjects.join(', ')}',
            );
          }
        }
      } else if (message.text.trim().isNotEmpty &&
          !message.isStreaming &&
          !message.isError) {
        buffer.writeln('Assistant: ${message.text}');
      }
    }

    buffer.write('Assistant:');
    return buffer.toString();
  }

  String _sessionSectionForMemory(ChatSession session) {
    final completeMessages = session.messages
        .where((message) => !message.isStreaming && !message.isError)
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);
    if (completeMessages.length < 2) {
      return '';
    }
    final start = completeMessages.length > 10
        ? completeMessages.length - 10
        : 0;
    final buffer = StringBuffer();
    for (final message in completeMessages.sublist(start)) {
      final role = message.role == ChatMessageRole.user ? 'User' : 'Assistant';
      buffer.writeln('$role: ${_takeRunes(message.text.trim(), 900)}');
    }
    return buffer.toString().trim();
  }

  String _memorySummaryPrompt(String section) {
    return '次の会話セクションから、今後のチャットで役に立つユーザーの好み、継続中の目的、重要な事実だけを日本語で短く要約してください。'
        '一時的な雑談、Web検索結果そのもの、AIの説明は保存しないでください。最大6項目、箇条書きのみ。\n\n$section';
  }

  String _normalizeGeneratedMemory(String text) {
    final normalized = text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.toLowerCase().contains('共有メモリー'))
        .take(8)
        .join('\n')
        .trim();
    return _takeRunes(normalized, 1200);
  }

  Future<void> _compactSharedMemoryIfNeeded({
    Future<String> Function(String prompt)? summarize,
  }) async {
    while (_sharedMemories.length > 24) {
      _sharedMemories.removeLast();
    }
    if (_sharedMemoryRuneLength() <= sharedMemoryStorageRuneLimit) {
      return;
    }
    final allMemory = _sharedMemories.map((memory) => memory.text).join('\n');
    var compact = '';
    if (summarize != null) {
      try {
        compact = await summarize(
          '次の共有メモリー全体を、重複を消して重要なユーザー情報だけに圧縮してください。'
          '日本語の箇条書きで、$sharedMemoryCompressedRuneTarget文字以内。\n\n$allMemory',
        );
      } catch (error) {
        debugPrint('Shared memory compaction failed: $error');
      }
    }
    compact = _normalizeGeneratedMemory(compact);
    if (compact.isEmpty) {
      compact = _takeRunes(allMemory, sharedMemoryCompressedRuneTarget);
    }
    _sharedMemories
      ..clear()
      ..add(
        SharedMemoryItem(
          id: _buildId(),
          text: compact,
          createdAt: DateTime.now(),
        ),
      );
  }

  int _sharedMemoryRuneLength() {
    return _sharedMemories.fold<int>(
      0,
      (total, memory) => total + memory.text.runes.length,
    );
  }

  List<String> _memoryCandidatesForSession(ChatSession session) {
    final candidates = <String>{};
    final userMessages = session.messages
        .where((message) => message.role == ChatMessageRole.user)
        .map((message) => message.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final recentMessages = userMessages.length > 8
        ? userMessages.sublist(userMessages.length - 8)
        : userMessages;

    for (final text in recentMessages) {
      final compact = text.replaceAll(' ', '');
      for (final label in const <String>[
        '小学生',
        '中学生',
        '高校生',
        '大学生',
        '専門学生',
        '社会人',
        '主婦',
        '会社員',
        '個人事業主',
        '経営者',
      ]) {
        if (compact.contains(label)) {
          candidates.add('ユーザーは$labelです。');
        }
      }

      final preference = _memorySentenceFromText(text);
      if (preference != null) {
        candidates.add(preference);
      }

      final searchMatch = RegExp(
        r'(.{1,48}?(?:探してる|探しています|探したい|探す|欲しい|知りたい|比較したい|検討している|検討中))',
      ).firstMatch(text);
      if (searchMatch != null) {
        candidates.add('ユーザーは${_normalizeMemoryText(searchMatch.group(1)!)}。');
      }
    }

    return candidates.take(8).toList(growable: false);
  }

  String? _memorySentenceFromText(String text) {
    final normalized = _normalizeMemoryText(text);
    if (normalized.length < 4 || normalized.length > 90) {
      return null;
    }
    final looksMemorable = RegExp(
      r'(好き|嫌い|苦手|得意|興味|志望|希望|優先|重視|探して|探し|欲しい|したい|してほしい|必要|困って|悩んで|高校生|大学生|中学生)',
    ).hasMatch(normalized);
    if (!looksMemorable) {
      return null;
    }
    final isQuestionOnly =
        normalized.endsWith('？') ||
        normalized.endsWith('?') ||
        normalized.contains('とは');
    if (isQuestionOnly && !RegExp(r'(探して|欲しい|したい|悩んで)').hasMatch(normalized)) {
      return null;
    }
    return 'ユーザー情報: $normalized。';
  }

  String _normalizeMemoryText(String text) {
    var normalized = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[。.!！?？]+$'), '')
        .trim();
    if (normalized.length > 90) {
      normalized = '${normalized.substring(0, 90)}…';
    }
    return normalized;
  }

  bool _hasSimilarSharedMemory(String text) {
    final normalized = _memoryComparableText(text);
    return _sharedMemories.any((memory) {
      final existing = _memoryComparableText(memory.text);
      return existing == normalized ||
          existing.contains(normalized) ||
          normalized.contains(existing);
    });
  }

  bool _isLowValueSharedMemory(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[\s　*＊・\-—–•●○#]+'), '')
        .replaceAll(RegExp(r'[。.!！?？]+'), '')
        .trim();
    if (normalized.isEmpty) {
      return true;
    }
    if (normalized.runes.length <= 26 &&
        RegExp(
          r'(挨拶|質問|知りたい|聞きたい|待っている|こんにちは|こんばんは|おはよう|hello|hi)',
          caseSensitive: false,
        ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(挨拶|質問や知りたいことの有無の確認|質問の有無の確認|質問を待っている状態)$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  String _memoryComparableText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'^(ユーザー情報:|ユーザーは)'), '')
        .replaceAll(RegExp(r'[。.!！?？]+$'), '');
  }

  String _compactAttachmentContext(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final attachment in attachments) {
      switch (attachment.type) {
        case ChatAttachmentType.image:
          if (attachment.analysisLabels.isNotEmpty) {
            buffer.writeln('添付画像の特徴: ${attachment.analysisLabels.join(', ')}');
          }
          if (attachment.detectedObjects.isNotEmpty) {
            buffer.writeln(
              '添付画像の検出結果: ${attachment.detectedObjects.join(', ')}',
            );
          }
          if (attachment.analysisLabels.isEmpty &&
              attachment.detectedObjects.isEmpty) {
            buffer.writeln('画像が添付されています。');
          }
        case ChatAttachmentType.audio:
          if (attachment.transcription?.trim().isNotEmpty ?? false) {
            buffer.writeln('添付音声の文字起こし: ${attachment.transcription}');
          } else {
            buffer.writeln('音声が添付されています。');
          }
        case ChatAttachmentType.location:
          final location = attachment.location;
          if (location != null) {
            buffer.writeln(
              '添付位置情報: 緯度 ${location.latitude}, 経度 ${location.longitude}',
            );
          }
      }
    }
    return buffer.toString();
  }

  ChatSession _createSessionModel({String? initialModelId}) {
    return ChatSession(
      id: _buildId(),
      title: '新しいチャット',
      updatedAt: DateTime.now(),
      selectedModelId: initialModelId,
      sharedMemoryEnabled: true,
      messages: const <ChatMessage>[],
    );
  }

  void _updateSession(
    String sessionId,
    ChatSession Function(ChatSession current) transform,
  ) {
    _sessions = _sessions.map((session) {
      if (session.id != sessionId) {
        return session;
      }
      return transform(session);
    }).toList();
  }

  void _updateMessage(
    String sessionId,
    String messageId,
    ChatMessage Function(ChatMessage current) transform,
  ) {
    _updateSession(
      sessionId,
      (session) => session.copyWith(
        messages: session.messages.map((message) {
          if (message.id != messageId) {
            return message;
          }
          return transform(message);
        }).toList(),
      ),
    );
  }

  void _touchSession(String sessionId) {
    _updateSession(
      sessionId,
      (session) => session.copyWith(updatedAt: DateTime.now()),
    );
  }

  String _deriveTitle(String currentTitle, List<ChatMessage> messages) {
    if (currentTitle != '新しいチャット') {
      return currentTitle;
    }

    final firstUserMessage = messages.firstWhere(
      (message) => message.role == ChatMessageRole.user,
      orElse: () => ChatMessage(
        id: '',
        role: ChatMessageRole.user,
        text: '',
        createdAt: DateTime.now(),
      ),
    );
    final source = firstUserMessage.text.trim();
    if (source.isEmpty) {
      return currentTitle;
    }
    return source.length > 18 ? '${source.substring(0, 18)}…' : source;
  }

  String _buildId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _persist() async {
    final file = _storageFile;
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'current_session_id': _currentSessionId,
        'sessions': _sessions.map((session) => session.toJson()).toList(),
        'shared_memories': _sharedMemories
            .map((memory) => memory.toJson())
            .toList(),
      }),
    );
  }
}

String _takeRunes(String text, int count) {
  if (text.runes.length <= count) {
    return text;
  }
  return String.fromCharCodes(text.runes.take(count));
}
