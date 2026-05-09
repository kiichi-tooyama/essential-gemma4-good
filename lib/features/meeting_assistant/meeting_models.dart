import '../shared/web_research_service.dart';
import 'meeting_enhancements.dart';

enum MeetingStatus {
  recording,
  processing, // Transcribing & Summarizing
  completed,
  failed,
}

class MeetingSession {
  MeetingSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.audioPath,
    required this.status,
    this.transcription = '',
    this.summary = '',
    this.translation = '',
    this.todos = '',
    List<MeetingTodoItem>? todoItems,
    this.translations = const <String, String>{},
    this.webSources = const <WebSource>[],
    this.consultations = const <MeetingConsultationMessage>[],
    this.durationSeconds = 0,
    this.isInternalAudio = false,
    String? recordingSource,
    this.sharedMemoryEnabled = true,
    this.processingStage = '',
    this.processingDetail = '',
    this.transcriptSegments = const <MeetingTranscriptSegment>[],
    this.topicSegments = const <MeetingTopicSegment>[],
    this.noteSets = const <MeetingNoteSet>[],
    this.askSuggestions = const <String>[],
    this.mindMap = const <MeetingMindMapNode>[],
    this.speakerLabels = const <String, String>{},
    this.templateId = 'meeting_minutes',
    this.templateOutputs = const <String, String>{},
    this.keywords = const <String>[],
    this.bookmarks = const <MeetingBookmark>[],
    this.folderId = '',
    this.tags = const <String>[],
    this.audioOptions = const MeetingAudioOptions(),
    this.sentiment = const MeetingSentimentMetrics(),
    this.cleanTranscription = '',
  }) : recordingSource =
           recordingSource ?? (isInternalAudio ? 'internal_audio' : 'import'),
       todoItems = todoItems ?? MeetingTodoItem.fromText(todos);

  factory MeetingSession.fromJson(Map<String, dynamic> json) {
    final rawTodos = json['todos'] as String? ?? '';
    return MeetingSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新しい会議',
      createdAt: DateTime.parse(json['created_at'] as String),
      audioPath: json['audio_path'] as String,
      status: MeetingStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MeetingStatus.completed,
      ),
      transcription: json['transcription'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      todos: rawTodos,
      todoItems: (json['todo_items'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (row) => MeetingTodoItem.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList()
          .ifEmpty(() => MeetingTodoItem.fromText(rawTodos)),
      translations: Map<String, String>.from(
        json['translations'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      webSources: (json['web_sources'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((row) => WebSource.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      consultations: (json['consultations'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (row) => MeetingConsultationMessage.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(),
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      isInternalAudio: json['is_internal_audio'] as bool? ?? false,
      recordingSource: json['recording_source'] as String?,
      sharedMemoryEnabled: json['shared_memory_enabled'] as bool? ?? true,
      processingStage: json['processing_stage'] as String? ?? '',
      processingDetail: json['processing_detail'] as String? ?? '',
      transcriptSegments:
          (json['transcript_segments'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map>()
              .map(
                (row) => MeetingTranscriptSegment.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(),
      topicSegments: (json['topic_segments'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (row) =>
                MeetingTopicSegment.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      noteSets: (json['note_sets'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((row) => MeetingNoteSet.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      askSuggestions: (json['ask_suggestions'] as List<dynamic>? ?? <dynamic>[])
          .map((row) => row.toString())
          .where((row) => row.trim().isNotEmpty)
          .toList(),
      mindMap: (json['mind_map'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (row) =>
                MeetingMindMapNode.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      speakerLabels: Map<String, String>.from(
        json['speaker_labels'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      templateId: json['template_id'] as String? ?? 'meeting_minutes',
      templateOutputs: Map<String, String>.from(
        json['template_outputs'] as Map<String, dynamic>? ??
            <String, dynamic>{},
      ),
      keywords: (json['keywords'] as List<dynamic>? ?? <dynamic>[])
          .map((row) => row.toString())
          .where((row) => row.trim().isNotEmpty)
          .toList(),
      bookmarks: (json['bookmarks'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (row) => MeetingBookmark.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      folderId: json['folder_id'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? <dynamic>[])
          .map((row) => row.toString())
          .where((row) => row.trim().isNotEmpty)
          .toList(),
      audioOptions: MeetingAudioOptions.fromJson(
        Map<String, dynamic>.from(
          json['audio_options'] as Map<dynamic, dynamic>? ??
              const <String, dynamic>{},
        ),
      ),
      sentiment: MeetingSentimentMetrics.fromJson(
        Map<String, dynamic>.from(
          json['sentiment'] as Map<dynamic, dynamic>? ??
              const <String, dynamic>{},
        ),
      ),
      cleanTranscription: json['clean_transcription'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final DateTime createdAt;
  final String audioPath;
  final MeetingStatus status;
  final String transcription;
  final String summary;
  final String translation;
  final String todos;
  final List<MeetingTodoItem> todoItems;
  final Map<String, String> translations;
  final List<WebSource> webSources;
  final List<MeetingConsultationMessage> consultations;
  final int durationSeconds;
  final bool isInternalAudio;
  final String recordingSource;
  final bool sharedMemoryEnabled;
  final String processingStage;
  final String processingDetail;
  final List<MeetingTranscriptSegment> transcriptSegments;
  final List<MeetingTopicSegment> topicSegments;
  final List<MeetingNoteSet> noteSets;
  final List<String> askSuggestions;
  final List<MeetingMindMapNode> mindMap;
  final Map<String, String> speakerLabels;
  final String templateId;
  final Map<String, String> templateOutputs;
  final List<String> keywords;
  final List<MeetingBookmark> bookmarks;
  final String folderId;
  final List<String> tags;
  final MeetingAudioOptions audioOptions;
  final MeetingSentimentMetrics sentiment;
  final String cleanTranscription;

  MeetingSession copyWith({
    String? audioPath,
    String? title,
    MeetingStatus? status,
    String? transcription,
    String? summary,
    String? translation,
    String? todos,
    List<MeetingTodoItem>? todoItems,
    Map<String, String>? translations,
    List<WebSource>? webSources,
    List<MeetingConsultationMessage>? consultations,
    int? durationSeconds,
    bool? isInternalAudio,
    String? recordingSource,
    bool? sharedMemoryEnabled,
    String? processingStage,
    String? processingDetail,
    List<MeetingTranscriptSegment>? transcriptSegments,
    List<MeetingTopicSegment>? topicSegments,
    List<MeetingNoteSet>? noteSets,
    List<String>? askSuggestions,
    List<MeetingMindMapNode>? mindMap,
    Map<String, String>? speakerLabels,
    String? templateId,
    Map<String, String>? templateOutputs,
    List<String>? keywords,
    List<MeetingBookmark>? bookmarks,
    String? folderId,
    List<String>? tags,
    MeetingAudioOptions? audioOptions,
    MeetingSentimentMetrics? sentiment,
    String? cleanTranscription,
  }) {
    return MeetingSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      audioPath: audioPath ?? this.audioPath,
      status: status ?? this.status,
      transcription: transcription ?? this.transcription,
      summary: summary ?? this.summary,
      translation: translation ?? this.translation,
      todos: todos ?? this.todos,
      todoItems: todoItems ?? this.todoItems,
      translations: translations ?? this.translations,
      webSources: webSources ?? this.webSources,
      consultations: consultations ?? this.consultations,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isInternalAudio: isInternalAudio ?? this.isInternalAudio,
      recordingSource: recordingSource ?? this.recordingSource,
      sharedMemoryEnabled: sharedMemoryEnabled ?? this.sharedMemoryEnabled,
      processingStage: processingStage ?? this.processingStage,
      processingDetail: processingDetail ?? this.processingDetail,
      transcriptSegments: transcriptSegments ?? this.transcriptSegments,
      topicSegments: topicSegments ?? this.topicSegments,
      noteSets: noteSets ?? this.noteSets,
      askSuggestions: askSuggestions ?? this.askSuggestions,
      mindMap: mindMap ?? this.mindMap,
      speakerLabels: speakerLabels ?? this.speakerLabels,
      templateId: templateId ?? this.templateId,
      templateOutputs: templateOutputs ?? this.templateOutputs,
      keywords: keywords ?? this.keywords,
      bookmarks: bookmarks ?? this.bookmarks,
      folderId: folderId ?? this.folderId,
      tags: tags ?? this.tags,
      audioOptions: audioOptions ?? this.audioOptions,
      sentiment: sentiment ?? this.sentiment,
      cleanTranscription: cleanTranscription ?? this.cleanTranscription,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'audio_path': audioPath,
      'status': status.name,
      'transcription': transcription,
      'summary': summary,
      'translation': translation,
      'todos': todos,
      'todo_items': todoItems.map((item) => item.toJson()).toList(),
      'translations': translations,
      'web_sources': webSources.map((source) => source.toJson()).toList(),
      'consultations': consultations
          .map((message) => message.toJson())
          .toList(),
      'duration_seconds': durationSeconds,
      'is_internal_audio': isInternalAudio,
      'recording_source': recordingSource,
      'shared_memory_enabled': sharedMemoryEnabled,
      'processing_stage': processingStage,
      'processing_detail': processingDetail,
      'transcript_segments': transcriptSegments
          .map((segment) => segment.toJson())
          .toList(),
      'topic_segments': topicSegments
          .map((segment) => segment.toJson())
          .toList(),
      'note_sets': noteSets.map((noteSet) => noteSet.toJson()).toList(),
      'ask_suggestions': askSuggestions,
      'mind_map': mindMap.map((node) => node.toJson()).toList(),
      'speaker_labels': speakerLabels,
      'template_id': templateId,
      'template_outputs': templateOutputs,
      'keywords': keywords,
      'bookmarks': bookmarks.map((bookmark) => bookmark.toJson()).toList(),
      'folder_id': folderId,
      'tags': tags,
      'audio_options': audioOptions.toJson(),
      'sentiment': sentiment.toJson(),
      'clean_transcription': cleanTranscription,
    };
  }
}

class MeetingTranscriptSegment {
  const MeetingTranscriptSegment({
    required this.text,
    required this.startSeconds,
    required this.endSeconds,
    this.speakerId = '',
    this.confidence = 0,
    this.speakerConfidence = 0,
  });

  factory MeetingTranscriptSegment.fromJson(Map<String, dynamic> json) {
    return MeetingTranscriptSegment(
      text: json['text'] as String? ?? '',
      startSeconds: (json['start_seconds'] as num?)?.toDouble() ?? 0,
      endSeconds: (json['end_seconds'] as num?)?.toDouble() ?? 0,
      speakerId: json['speaker_id'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      speakerConfidence: (json['speaker_confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  final String text;
  final double startSeconds;
  final double endSeconds;
  final String speakerId;
  final double confidence;
  final double speakerConfidence;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'speaker_id': speakerId,
      'confidence': confidence,
      'speaker_confidence': speakerConfidence,
    };
  }
}

class MeetingTopicSegment {
  const MeetingTopicSegment({
    required this.title,
    required this.startSeconds,
    this.summary = '',
  });

  factory MeetingTopicSegment.fromJson(Map<String, dynamic> json) {
    return MeetingTopicSegment(
      title: json['title'] as String? ?? '',
      startSeconds: (json['start_seconds'] as num?)?.toDouble() ?? 0,
      summary: json['summary'] as String? ?? '',
    );
  }

  final String title;
  final double startSeconds;
  final String summary;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'start_seconds': startSeconds,
      'summary': summary,
    };
  }
}

class MeetingNoteSet {
  const MeetingNoteSet({required this.title, required this.body});

  factory MeetingNoteSet.fromJson(Map<String, dynamic> json) {
    return MeetingNoteSet(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }

  final String title;
  final String body;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'title': title, 'body': body};
  }
}

class MeetingMindMapNode {
  const MeetingMindMapNode({
    required this.label,
    this.id = '',
    this.summary = '',
    this.startSeconds = 0,
    this.collapsed = false,
    this.children = const [],
  });

  factory MeetingMindMapNode.fromJson(Map<String, dynamic> json) {
    return MeetingMindMapNode(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      startSeconds: (json['start_seconds'] as num?)?.toDouble() ?? 0,
      collapsed: json['collapsed'] as bool? ?? false,
      children: (json['children'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (row) =>
                MeetingMindMapNode.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
    );
  }

  final String id;
  final String label;
  final String summary;
  final double startSeconds;
  final bool collapsed;
  final List<MeetingMindMapNode> children;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'summary': summary,
      'start_seconds': startSeconds,
      'collapsed': collapsed,
      'children': children.map((child) => child.toJson()).toList(),
    };
  }
}

class MeetingConsultationMessage {
  const MeetingConsultationMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.createdAt,
  });

  factory MeetingConsultationMessage.fromJson(Map<String, dynamic> json) {
    return MeetingConsultationMessage(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      isUser: json['is_user'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String text;
  final bool isUser;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'is_user': isUser,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class MeetingTodoItem {
  const MeetingTodoItem({
    required this.id,
    required this.text,
    this.completed = false,
  });

  factory MeetingTodoItem.fromJson(Map<String, dynamic> json) {
    return MeetingTodoItem(
      id: json['id'] as String? ?? 'todo-${json.hashCode}',
      text: json['text'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
    );
  }

  final String id;
  final String text;
  final bool completed;

  MeetingTodoItem copyWith({bool? completed}) {
    return MeetingTodoItem(
      id: id,
      text: text,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'text': text, 'completed': completed};
  }

  static List<MeetingTodoItem> fromText(String text) {
    final items = <MeetingTodoItem>[];
    var index = 0;
    for (final rawLine in text.split('\n')) {
      final cleaned = rawLine
          .replaceFirst(RegExp(r'^\s*[-*＊・•●○]\s*'), '')
          .replaceFirst(RegExp(r'^\s*[☐☑☒□■◻️✅]\s*'), '')
          .trim();
      if (cleaned.isEmpty ||
          RegExp(r'^([*＊・\-—–•●○#\s])+$').hasMatch(cleaned)) {
        continue;
      }
      items.add(MeetingTodoItem(id: 'todo-${index++}', text: cleaned));
    }
    return items;
  }
}

extension _IterableFallback<T> on List<T> {
  List<T> ifEmpty(List<T> Function() fallback) {
    return isEmpty ? fallback() : this;
  }
}
