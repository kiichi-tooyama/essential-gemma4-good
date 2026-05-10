import 'dart:math' as math;

import 'meeting_models.dart';

class MeetingSummaryTemplate {
  const MeetingSummaryTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.sections,
    this.promptHint = '',
  });

  final String id;
  final String title;
  final String description;
  final List<String> sections;
  final String promptHint;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'sections': sections,
      'prompt_hint': promptHint,
    };
  }
}

class MeetingBookmark {
  const MeetingBookmark({
    required this.id,
    required this.startSeconds,
    required this.label,
    this.note = '',
    this.createdAt,
  });

  factory MeetingBookmark.fromJson(Map<String, dynamic> json) {
    return MeetingBookmark(
      id: json['id'] as String? ?? 'bookmark-${json.hashCode}',
      startSeconds: (json['start_seconds'] as num?)?.toDouble() ?? 0,
      label: json['label'] as String? ?? '重要',
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final double startSeconds;
  final String label;
  final String note;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'start_seconds': startSeconds,
      'label': label,
      'note': note,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }
}

class MeetingAudioOptions {
  const MeetingAudioOptions({
    this.voiceEnhancementEnabled = true,
    this.silenceSkipEnabled = false,
    this.fillerRemovalEnabled = true,
    this.playbackSpeed = 1,
  });

  factory MeetingAudioOptions.fromJson(Map<String, dynamic> json) {
    return MeetingAudioOptions(
      voiceEnhancementEnabled:
          json['voice_enhancement_enabled'] as bool? ?? true,
      silenceSkipEnabled: json['silence_skip_enabled'] as bool? ?? false,
      fillerRemovalEnabled: json['filler_removal_enabled'] as bool? ?? true,
      playbackSpeed: (json['playback_speed'] as num?)?.toDouble() ?? 1,
    );
  }

  final bool voiceEnhancementEnabled;
  final bool silenceSkipEnabled;
  final bool fillerRemovalEnabled;
  final double playbackSpeed;

  MeetingAudioOptions copyWith({
    bool? voiceEnhancementEnabled,
    bool? silenceSkipEnabled,
    bool? fillerRemovalEnabled,
    double? playbackSpeed,
  }) {
    return MeetingAudioOptions(
      voiceEnhancementEnabled:
          voiceEnhancementEnabled ?? this.voiceEnhancementEnabled,
      silenceSkipEnabled: silenceSkipEnabled ?? this.silenceSkipEnabled,
      fillerRemovalEnabled: fillerRemovalEnabled ?? this.fillerRemovalEnabled,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'voice_enhancement_enabled': voiceEnhancementEnabled,
      'silence_skip_enabled': silenceSkipEnabled,
      'filler_removal_enabled': fillerRemovalEnabled,
      'playback_speed': playbackSpeed,
    };
  }
}

class MeetingSentimentMetrics {
  const MeetingSentimentMetrics({
    this.satisfaction = 0,
    this.motivation = 0,
    this.concern = 0,
    this.summary = '',
  });

  factory MeetingSentimentMetrics.fromJson(Map<String, dynamic> json) {
    return MeetingSentimentMetrics(
      satisfaction: (json['satisfaction'] as num?)?.toDouble() ?? 0,
      motivation: (json['motivation'] as num?)?.toDouble() ?? 0,
      concern: (json['concern'] as num?)?.toDouble() ?? 0,
      summary: json['summary'] as String? ?? '',
    );
  }

  final double satisfaction;
  final double motivation;
  final double concern;
  final String summary;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'satisfaction': satisfaction,
      'motivation': motivation,
      'concern': concern,
      'summary': summary,
    };
  }
}

class MeetingSearchResult {
  const MeetingSearchResult({
    required this.session,
    required this.snippet,
    required this.startSeconds,
    required this.source,
  });

  final MeetingSession session;
  final String snippet;
  final double startSeconds;
  final String source;
}

class MeetingTextProcessor {
  static const List<MeetingSummaryTemplate>
  templates = <MeetingSummaryTemplate>[
    MeetingSummaryTemplate(
      id: 'meeting_minutes',
      title: 'Meeting minutes',
      description: 'Agenda, decisions, and action items',
      sections: <String>[
        'Overview',
        'Decisions',
        'Action items',
        'Open issues',
      ],
      promptHint:
          'Organize agreements, open issues, owners, and deadlines so readers can act immediately.',
    ),
    MeetingSummaryTemplate(
      id: 'interview',
      title: 'Interview notes',
      description: 'Questions, answers, quotes, and insights',
      sections: <String>[
        'Key points',
        'Quotes',
        'Insights',
        'Follow-up questions',
      ],
      promptHint:
          'Separate questions, answers, quotes, insights, and useful follow-up questions.',
    ),
    MeetingSummaryTemplate(
      id: 'lecture',
      title: 'Lecture notes',
      description: 'Learnings, terms, homework, and review points',
      sections: <String>['Key learnings', 'Terms', 'Homework', 'Review points'],
    ),
    MeetingSummaryTemplate(
      id: 'sales',
      title: 'Sales notes',
      description: 'Customer pain points, proposal, sentiment, and next action',
      sections: <String>[
        'Customer needs',
        'Proposal',
        'Sentiment',
        'Next action',
      ],
    ),
    MeetingSummaryTemplate(
      id: 'customer_research',
      title: 'Customer research',
      description: 'Needs, complaints, buying criteria, and findings',
      sections: <String>['Needs', 'Complaints', 'Criteria', 'Findings'],
    ),
    MeetingSummaryTemplate(
      id: 'one_on_one',
      title: 'One-on-one',
      description: 'Status, concerns, support, and commitments',
      sections: <String>['Status', 'Concerns', 'Support', 'Commitments'],
    ),
    MeetingSummaryTemplate(
      id: 'recruiting',
      title: 'Recruiting interview',
      description: 'Experience, strengths, concerns, and evaluation',
      sections: <String>['Experience', 'Strengths', 'Concerns', 'Evaluation'],
    ),
    MeetingSummaryTemplate(
      id: 'book',
      title: 'Book notes',
      description: 'Structure, claims, quotes, and practice',
      sections: <String>['Claims', 'Important quotes', 'Learnings', 'Practice'],
    ),
    MeetingSummaryTemplate(
      id: 'research',
      title: 'Research notes',
      description: 'Hypothesis, evidence, discussion points, and next research',
      sections: <String>[
        'Hypothesis',
        'Evidence',
        'Discussion points',
        'Next research',
      ],
    ),
    MeetingSummaryTemplate(
      id: 'medical',
      title: 'Medical consultation notes',
      description: 'Symptoms, explanation, cautions, and confirmations',
      sections: <String>[
        'Symptoms',
        'Explanation',
        'Cautions',
        'Confirmations',
      ],
    ),
    MeetingSummaryTemplate(
      id: 'legal',
      title: 'Legal consultation notes',
      description: 'Facts, issues, advice, and next checks',
      sections: <String>['Facts', 'Issues', 'Advice', 'Next checks'],
    ),
    MeetingSummaryTemplate(
      id: 'project',
      title: 'Project progress',
      description: 'Progress, blockers, decisions, and next phase',
      sections: <String>['Progress', 'Blockers', 'Decisions', 'Next phase'],
    ),
    MeetingSummaryTemplate(
      id: 'spec_review',
      title: 'Spec review',
      description: 'Requirements, changes, concerns, and TODO',
      sections: <String>['Requirements', 'Changes', 'Concerns', 'TODO'],
    ),
    MeetingSummaryTemplate(
      id: 'code_review',
      title: 'Code review',
      description: 'Findings, risks, fix plan, and checks',
      sections: <String>['Findings', 'Risks', 'Fix plan', 'Checks'],
    ),
    MeetingSummaryTemplate(
      id: 'incident',
      title: 'Incident report',
      description: 'Impact, cause, response, and prevention',
      sections: <String>['Impact', 'Cause', 'Response', 'Prevention'],
    ),
    MeetingSummaryTemplate(
      id: 'daily',
      title: 'Daily report',
      description: 'Work done, outcomes, issues, and tomorrow',
      sections: <String>['Done', 'Outcomes', 'Issues', 'Tomorrow'],
    ),
    MeetingSummaryTemplate(
      id: 'weekly',
      title: 'Weekly report',
      description: 'Weekly outcomes, issues, and next plan',
      sections: <String>['Outcomes', 'Issues', 'Next week', 'Requests'],
    ),
    MeetingSummaryTemplate(
      id: 'business_report',
      title: 'Business report',
      description: 'Deals, confidence, blockers, and next step',
      sections: <String>['Deals', 'Confidence', 'Blockers', 'Next step'],
    ),
    MeetingSummaryTemplate(
      id: 'user_test',
      title: 'User test',
      description: 'Behavior, quotes, issues, and improvements',
      sections: <String>['Behavior', 'Quotes', 'Issues', 'Improvements'],
    ),
    MeetingSummaryTemplate(
      id: 'brainstorm',
      title: 'Brainstorm',
      description: 'Ideas, categories, promising options, and validation',
      sections: <String>[
        'Ideas',
        'Categories',
        'Promising options',
        'Validation',
      ],
    ),
    MeetingSummaryTemplate(
      id: 'decision_log',
      title: 'Decision log',
      description: 'Options, rationale, decision, and impact',
      sections: <String>['Options', 'Rationale', 'Decision', 'Impact'],
    ),
    MeetingSummaryTemplate(
      id: 'todo_only',
      title: 'Action items',
      description: 'Only executable tasks',
      sections: <String>['TODO', 'Owner', 'Deadline', 'Check'],
    ),
    MeetingSummaryTemplate(
      id: 'decisions_only',
      title: 'Decisions',
      description: 'Only confirmed decisions',
      sections: <String>['Decisions', 'Rationale', 'Impact', 'Notify'],
    ),
    MeetingSummaryTemplate(
      id: 'risk',
      title: 'Risk analysis',
      description: 'Risks, signals, countermeasures, and owner',
      sections: <String>['Risks', 'Signals', 'Countermeasures', 'Owner'],
    ),
    MeetingSummaryTemplate(
      id: 'faq',
      title: 'FAQ',
      description: 'Convert content into questions and answers',
      sections: <String>['FAQ', 'Notes', 'Unknowns', 'References'],
    ),
    MeetingSummaryTemplate(
      id: 'keyword',
      title: 'Keyword focus',
      description: 'Important terms and explanations',
      sections: <String>[
        'Keywords',
        'Explanations',
        'Related remarks',
        'Deep dive',
      ],
    ),
    MeetingSummaryTemplate(
      id: 'chronological',
      title: 'Chronological summary',
      description: 'Organize by time',
      sections: <String>['Timeline', 'Turning points', 'Conclusion', 'Next'],
    ),
    MeetingSummaryTemplate(
      id: 'speaker',
      title: 'Speaker summary',
      description: 'Claims and TODO by speaker',
      sections: <String>['Speaker points', 'Agreements', 'Differences', 'TODO'],
      promptHint:
          'Separate claims, concerns, agreements, and requests by speaker.',
    ),
    MeetingSummaryTemplate(
      id: 'sentiment',
      title: 'Sentiment analysis',
      description: 'Satisfaction, motivation, concerns, and evidence',
      sections: <String>['Satisfaction', 'Motivation', 'Concern', 'Evidence'],
    ),
    MeetingSummaryTemplate(
      id: 'motivation',
      title: 'Motivation analysis',
      description: 'Motivation changes and causes',
      sections: <String>[
        'Positive factors',
        'Negative factors',
        'Support',
        'Next',
      ],
    ),
    MeetingSummaryTemplate(
      id: 'opposition',
      title: 'Opposing views',
      description: 'Objections and discussion points',
      sections: <String>['Objections', 'Reasons', 'Responses', 'Unresolved'],
    ),
    MeetingSummaryTemplate(
      id: 'brief',
      title: 'Brief summary',
      description: 'Short conclusion only',
      sections: <String>['Conclusion', 'Key points', 'Next move'],
      promptHint:
          'Avoid long explanations and keep only the conclusion and next move.',
    ),
    MeetingSummaryTemplate(
      id: 'detailed',
      title: 'Detailed notes',
      description: 'Long-form notes for study or records',
      sections: <String>['Details', 'Background', 'Examples', 'Notes'],
    ),
    MeetingSummaryTemplate(
      id: 'share_email',
      title: 'Share email',
      description: 'A shareable email draft',
      sections: <String>['Subject', 'Body', 'Request', 'Deadline'],
    ),
    MeetingSummaryTemplate(
      id: 'social',
      title: 'Short share text',
      description: 'Short text for sharing',
      sections: <String>['One-line summary', 'Bullets', 'Next'],
    ),
    MeetingSummaryTemplate(
      id: 'study',
      title: 'Study notes',
      description: 'Learnings, terms, examples, and quiz',
      sections: <String>[
        'Key learnings',
        'Terms',
        'Examples',
        'Review questions',
      ],
    ),
  ];

  static MeetingSummaryTemplate templateById(String id) {
    return templates.firstWhere(
      (template) => template.id == id,
      orElse: () => templates.first,
    );
  }

  static String cleanTranscript(String text) {
    final filler = RegExp(
      r'(^|\s|、|。)(えーと|えっと|えー|あのー|あの|そのー|その|まあ|なんか|こう|ええと)(?=\s|、|。|$)',
    );
    return text
        .replaceAll(filler, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*([、。])\s*'), r'$1')
        .trim();
  }

  static List<String> extractKeywords(String text, {int limit = 12}) {
    final counts = <String, int>{};
    final matches = RegExp(r'[一-龥ぁ-んァ-ンーA-Za-z0-9]{2,}').allMatches(text);
    for (final match in matches) {
      final word = match.group(0) ?? '';
      final candidates = word.split(
        RegExp(r'(について|しました|します|です|ます|から|まで|の|を|に|が|は|で|と|へ)'),
      );
      for (final candidate in candidates) {
        if (_stopWords.contains(candidate) || candidate.runes.length < 2) {
          continue;
        }
        counts[candidate] = (counts[candidate] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return b.key.runes.length.compareTo(a.key.runes.length);
      });
    return entries.take(limit).map((entry) => entry.key).toList();
  }

  static MeetingSentimentMetrics analyzeSentiment(String text) {
    final positive = _countAny(text, _positiveWords);
    final negative = _countAny(text, _negativeWords);
    final action = _countAny(text, _actionWords);
    final filler = _countAny(text, _fillerWords);
    final total = math.max(1, positive + negative + action + filler);
    final satisfaction = ((positive + 1) / (positive + negative + 2)).clamp(
      0.0,
      1.0,
    );
    final motivation = ((action + positive + 1) / (total + 2)).clamp(0.0, 1.0);
    final concern = ((negative + filler) / (total + 1)).clamp(0.0, 1.0);
    return MeetingSentimentMetrics(
      satisfaction: satisfaction,
      motivation: motivation,
      concern: concern,
      summary:
          'Estimated from positive terms, concern terms, action terms, and filler frequency in the transcript.',
    );
  }

  static List<MeetingSearchResult> search(
    List<MeetingSession> sessions,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <MeetingSearchResult>[];
    }
    final results = <MeetingSearchResult>[];
    for (final session in sessions) {
      void addIfMatch(String source, String value, double startSeconds) {
        final lower = value.toLowerCase();
        if (!lower.contains(normalized)) {
          return;
        }
        results.add(
          MeetingSearchResult(
            session: session,
            snippet: _snippet(value, normalized),
            startSeconds: startSeconds,
            source: source,
          ),
        );
      }

      addIfMatch('Title', session.title, 0);
      addIfMatch('Summary', session.summary, 0);
      addIfMatch('Transcript', session.transcription, 0);
      addIfMatch('Clean transcript', session.cleanTranscription, 0);
      for (final entry in session.templateOutputs.entries) {
        addIfMatch('Template', entry.value, 0);
      }
      for (final noteSet in session.noteSets) {
        addIfMatch('Notes', noteSet.title, 0);
        addIfMatch('Notes', noteSet.body, 0);
      }
      for (final entry in session.translations.entries) {
        addIfMatch('Translation', entry.value, 0);
      }
      for (final keyword in session.keywords) {
        addIfMatch('Keyword', keyword, 0);
      }
      for (final tag in session.tags) {
        addIfMatch('Tag', tag, 0);
      }
      for (final bookmark in session.bookmarks) {
        addIfMatch('Bookmark', bookmark.label, bookmark.startSeconds);
        addIfMatch('Bookmark', bookmark.note, bookmark.startSeconds);
      }
      for (final segment in session.transcriptSegments) {
        addIfMatch('Utterance', segment.text, segment.startSeconds);
        addIfMatch(
          'Speaker',
          session.speakerLabels[segment.speakerId] ?? segment.speakerId,
          segment.startSeconds,
        );
      }
    }
    results.sort((a, b) => b.session.createdAt.compareTo(a.session.createdAt));
    return results;
  }

  static String buildTemplatePrompt(MeetingSummaryTemplate template) {
    final buffer = StringBuffer()
      ..writeln('Template: ${template.title}')
      ..writeln('Purpose: ${template.description}');
    if (template.promptHint.trim().isNotEmpty) {
      buffer.writeln('Important guidance: ${template.promptHint.trim()}');
    }
    buffer
      ..writeln('Output only the following headings in this order.')
      ..writeln();
    for (final section in template.sections) {
      buffer
        ..writeln('# $section')
        ..writeln('- Organize concrete content for this heading.')
        ..writeln();
    }
    return buffer.toString().trim();
  }

  static String templateOutput(
    MeetingSummaryTemplate template,
    MeetingSession session,
  ) {
    final buffer = StringBuffer();
    for (final section in template.sections) {
      buffer
        ..writeln('## $section')
        ..writeln(_sectionText(section, session))
        ..writeln();
    }
    return buffer.toString().trim();
  }

  static String _sectionText(String section, MeetingSession session) {
    final normalized = section.toLowerCase();
    if (section.contains('TODO') ||
        normalized.contains('action') ||
        normalized.contains('next') ||
        normalized.contains('homework')) {
      return session.todos.trim().isEmpty
          ? '- Not extracted'
          : session.todos.trim();
    }
    if (normalized.contains('keyword') || normalized.contains('term')) {
      return session.keywords.isEmpty
          ? '- Not extracted'
          : '- ${session.keywords.join('\n- ')}';
    }
    if (normalized.contains('sentiment') ||
        normalized.contains('satisfaction') ||
        normalized.contains('motivation') ||
        normalized.contains('concern')) {
      final s = session.sentiment;
      return '- Satisfaction ${(s.satisfaction * 100).round()}%\n'
          '- Motivation ${(s.motivation * 100).round()}%\n'
          '- Concern ${(s.concern * 100).round()}%\n'
          '- ${_englishSentimentSummary(s.summary)}';
    }
    if (normalized.contains('timeline') ||
        normalized.contains('chronological')) {
      if (session.topicSegments.isEmpty) return '- Not extracted';
      return session.topicSegments
          .map((topic) => '- ${_formatTime(topic.startSeconds)} ${topic.title}')
          .join('\n');
    }
    if (normalized.contains('speaker')) {
      if (session.transcriptSegments.isEmpty) return '- Not extracted';
      final speakers = session.transcriptSegments
          .map((segment) => segment.speakerId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      return speakers.isEmpty
          ? '- No speaker information'
          : speakers
                .map((id) => '- ${session.speakerLabels[id] ?? id}')
                .join('\n');
    }
    return session.summary.trim().isEmpty
        ? '- ${_snippet(session.cleanTranscription, '')}'
        : session.summary.trim();
  }

  static String _englishSentimentSummary(String summary) {
    final trimmed = summary.trim();
    if (trimmed.isEmpty || RegExp(r'[\u3040-\u30ff]').hasMatch(trimmed)) {
      return 'Estimated from positive terms, concern terms, action terms, and filler frequency in the transcript.';
    }
    return trimmed;
  }

  static String _snippet(String value, String query) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.runes.length <= 120) {
      return compact;
    }
    final lower = compact.toLowerCase();
    final index = query.isEmpty ? 0 : lower.indexOf(query.toLowerCase());
    final start = math.max(0, index < 0 ? 0 : index - 36);
    final end = math.min(compact.length, start + 120);
    return compact.substring(start, end).trim();
  }

  static String _formatTime(double seconds) {
    final total = seconds.round().clamp(0, 24 * 60 * 60);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }

  static int _countAny(String text, List<String> words) {
    var count = 0;
    for (final word in words) {
      count += RegExp(RegExp.escape(word)).allMatches(text).length;
    }
    return count;
  }

  static const Set<String> _stopWords = <String>{
    'これ',
    'それ',
    'ため',
    'こと',
    'もの',
    'よう',
    'です',
    'ます',
    'した',
    'して',
    'ある',
    'いる',
    'ない',
    'この',
    'その',
    'あの',
  };

  static const List<String> _positiveWords = <String>[
    '良い',
    'いい',
    '賛成',
    'できる',
    '進める',
    '助かる',
    '嬉しい',
    '満足',
    '期待',
  ];

  static const List<String> _negativeWords = <String>[
    '懸念',
    '不安',
    '難しい',
    '問題',
    '遅れ',
    '困る',
    'リスク',
    '反対',
    '不足',
  ];

  static const List<String> _actionWords = <String>[
    'やる',
    '進める',
    '確認',
    '対応',
    '実施',
    '作る',
    '送る',
    '決める',
  ];

  static const List<String> _fillerWords = <String>[
    'えー',
    'えっと',
    'あの',
    'その',
    'なんか',
    'まあ',
  ];
}
