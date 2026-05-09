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
  static const List<MeetingSummaryTemplate> templates =
      <MeetingSummaryTemplate>[
        MeetingSummaryTemplate(
          id: 'meeting_minutes',
          title: '会議議事録',
          description: '議題、決定事項、TODOを整理',
          sections: <String>['概要', '決定事項', 'TODO', '未決事項'],
          promptHint: '会議の合意、未決事項、担当者、期限を読み手がそのまま実行できる粒度で整理する。',
        ),
        MeetingSummaryTemplate(
          id: 'interview',
          title: 'インタビュー',
          description: '質問、回答、示唆を抽出',
          sections: <String>['要点', '発言引用', '示唆', '次の質問'],
          promptHint: '質問と回答の対応、発言引用、インサイト、次に深掘りすべき質問を分ける。',
        ),
        MeetingSummaryTemplate(
          id: 'lecture',
          title: '講義メモ',
          description: '主な学び、用語、宿題を整理',
          sections: <String>['主な学び', 'キーワード', '宿題', '復習ポイント'],
        ),
        MeetingSummaryTemplate(
          id: 'sales',
          title: '商談記録',
          description: '課題、提案、温度感、次回アクション',
          sections: <String>['顧客課題', '提案内容', '温度感', '次回アクション'],
          promptHint: '顧客の課題、購入条件、反応温度、次回接点を営業担当が使える形にする。',
        ),
        MeetingSummaryTemplate(
          id: 'customer_research',
          title: '顧客ヒアリング',
          description: 'ニーズ、不満、購買条件を整理',
          sections: <String>['ニーズ', '不満', '条件', '発見'],
        ),
        MeetingSummaryTemplate(
          id: 'one_on_one',
          title: '1on1',
          description: '状態、悩み、支援、約束を整理',
          sections: <String>['状態', '悩み', '支援', '約束'],
        ),
        MeetingSummaryTemplate(
          id: 'recruiting',
          title: '採用面接',
          description: '経験、強み、懸念、評価を整理',
          sections: <String>['経験', '強み', '懸念', '評価'],
        ),
        MeetingSummaryTemplate(
          id: 'book',
          title: '読書メモ',
          description: '章立て、主張、引用、実践を整理',
          sections: <String>['主張', '重要引用', '学び', '実践'],
        ),
        MeetingSummaryTemplate(
          id: 'research',
          title: '研究メモ',
          description: '仮説、根拠、論点、次の調査',
          sections: <String>['仮説', '根拠', '論点', '次の調査'],
        ),
        MeetingSummaryTemplate(
          id: 'medical',
          title: '医療相談メモ',
          description: '症状、説明、確認事項を整理',
          sections: <String>['症状', '説明', '注意点', '確認事項'],
        ),
        MeetingSummaryTemplate(
          id: 'legal',
          title: '法律相談メモ',
          description: '事実、争点、助言、次の確認',
          sections: <String>['事実', '争点', '助言', '次の確認'],
        ),
        MeetingSummaryTemplate(
          id: 'project',
          title: 'プロジェクト進捗',
          description: '進捗、ブロッカー、判断、次工程',
          sections: <String>['進捗', 'ブロッカー', '判断', '次工程'],
        ),
        MeetingSummaryTemplate(
          id: 'spec_review',
          title: '仕様レビュー',
          description: '仕様、変更点、懸念、TODO',
          sections: <String>['仕様', '変更点', '懸念', 'TODO'],
        ),
        MeetingSummaryTemplate(
          id: 'code_review',
          title: 'コードレビュー',
          description: '指摘、リスク、修正方針、確認項目',
          sections: <String>['指摘', 'リスク', '修正方針', '確認項目'],
        ),
        MeetingSummaryTemplate(
          id: 'incident',
          title: '障害報告',
          description: '影響、原因、対応、再発防止',
          sections: <String>['影響', '原因', '対応', '再発防止'],
        ),
        MeetingSummaryTemplate(
          id: 'daily',
          title: '日報',
          description: '実施、成果、課題、明日',
          sections: <String>['実施', '成果', '課題', '明日'],
        ),
        MeetingSummaryTemplate(
          id: 'weekly',
          title: '週報',
          description: '週の成果、課題、来週計画',
          sections: <String>['成果', '課題', '来週計画', '相談'],
        ),
        MeetingSummaryTemplate(
          id: 'business_report',
          title: '営業報告',
          description: '案件、確度、阻害要因、次手',
          sections: <String>['案件', '確度', '阻害要因', '次手'],
        ),
        MeetingSummaryTemplate(
          id: 'user_test',
          title: 'ユーザー調査',
          description: '行動、発言、課題、改善案',
          sections: <String>['行動', '発言', '課題', '改善案'],
        ),
        MeetingSummaryTemplate(
          id: 'brainstorm',
          title: 'ブレスト',
          description: 'アイデア、分類、有望案、次の検証',
          sections: <String>['アイデア', '分類', '有望案', '次の検証'],
        ),
        MeetingSummaryTemplate(
          id: 'decision_log',
          title: '意思決定ログ',
          description: '選択肢、判断理由、決定、影響',
          sections: <String>['選択肢', '判断理由', '決定', '影響'],
        ),
        MeetingSummaryTemplate(
          id: 'todo_only',
          title: 'TODO抽出',
          description: '実行項目だけを整理',
          sections: <String>['TODO', '担当', '期限', '確認'],
        ),
        MeetingSummaryTemplate(
          id: 'decisions_only',
          title: '決定事項',
          description: '決まったことだけを抽出',
          sections: <String>['決定事項', '根拠', '影響', '周知先'],
        ),
        MeetingSummaryTemplate(
          id: 'risk',
          title: 'リスク分析',
          description: 'リスク、兆候、対策、責任者',
          sections: <String>['リスク', '兆候', '対策', '責任者'],
        ),
        MeetingSummaryTemplate(
          id: 'faq',
          title: 'FAQ生成',
          description: '質問と回答形式に変換',
          sections: <String>['FAQ', '補足', '不明点', '参照'],
        ),
        MeetingSummaryTemplate(
          id: 'keyword',
          title: 'キーワード中心',
          description: '重要語と説明を整理',
          sections: <String>['キーワード', '説明', '関連発言', '深掘り'],
        ),
        MeetingSummaryTemplate(
          id: 'chronological',
          title: '時系列要約',
          description: '時間ごとに整理',
          sections: <String>['タイムライン', '転換点', '結論', '次'],
        ),
        MeetingSummaryTemplate(
          id: 'speaker',
          title: '話者別要約',
          description: '話者ごとの主張とTODO',
          sections: <String>['話者別要点', '合意', '相違', 'TODO'],
          promptHint: '話者名ごとに主張、懸念、合意、依頼事項を分ける。',
        ),
        MeetingSummaryTemplate(
          id: 'sentiment',
          title: '感情分析',
          description: '満足度、モチベーション、懸念を整理',
          sections: <String>['満足度', 'モチベーション', '懸念', '根拠'],
        ),
        MeetingSummaryTemplate(
          id: 'motivation',
          title: 'モチベーション分析',
          description: '意欲の上下と要因を整理',
          sections: <String>['高い要因', '下がる要因', '支援', '次'],
        ),
        MeetingSummaryTemplate(
          id: 'opposition',
          title: '反対意見整理',
          description: '異論と論点を抽出',
          sections: <String>['反対意見', '理由', '対応案', '未解決'],
        ),
        MeetingSummaryTemplate(
          id: 'brief',
          title: '要点だけ',
          description: '短く結論だけ整理',
          sections: <String>['結論', '重要点', '次の一手'],
          promptHint: '冗長な説明を避け、短く結論と次の一手だけに絞る。',
        ),
        MeetingSummaryTemplate(
          id: 'detailed',
          title: '詳細ノート',
          description: '長めの学習/記録用ノート',
          sections: <String>['詳細', '背景', '具体例', '補足'],
          promptHint: '背景、前提、具体例、発言根拠を省略せず長めに整理する。',
        ),
        MeetingSummaryTemplate(
          id: 'share_email',
          title: '共有メール',
          description: 'そのまま送れる共有文',
          sections: <String>['件名', '本文', '依頼', '期限'],
        ),
        MeetingSummaryTemplate(
          id: 'social',
          title: '短文共有',
          description: '短く共有できる文章',
          sections: <String>['一言要約', '箇条書き', '次'],
        ),
        MeetingSummaryTemplate(
          id: 'study',
          title: '学習ノート',
          description: '主な学び、用語、問題を整理',
          sections: <String>['主な学び', '用語', '例', '復習問題'],
          promptHint: '学習者が復習できるように、用語説明、例、確認問題を含める。',
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
      summary: '発話内容の肯定語、懸念語、行動語、フィラー量から推定しています。音声専用モデルではなく端末内の軽量分析です。',
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

      addIfMatch('タイトル', session.title, 0);
      addIfMatch('要約', session.summary, 0);
      addIfMatch('文字起こし', session.transcription, 0);
      addIfMatch('整形文字起こし', session.cleanTranscription, 0);
      for (final entry in session.templateOutputs.entries) {
        addIfMatch('テンプレート', entry.value, 0);
      }
      for (final noteSet in session.noteSets) {
        addIfMatch('ノート', noteSet.title, 0);
        addIfMatch('ノート', noteSet.body, 0);
      }
      for (final entry in session.translations.entries) {
        addIfMatch('翻訳', entry.value, 0);
      }
      for (final keyword in session.keywords) {
        addIfMatch('キーワード', keyword, 0);
      }
      for (final tag in session.tags) {
        addIfMatch('タグ', tag, 0);
      }
      for (final bookmark in session.bookmarks) {
        addIfMatch('ブックマーク', bookmark.label, bookmark.startSeconds);
        addIfMatch('ブックマーク', bookmark.note, bookmark.startSeconds);
      }
      for (final segment in session.transcriptSegments) {
        addIfMatch('発言', segment.text, segment.startSeconds);
        addIfMatch(
          '話者',
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
      ..writeln('テンプレート名: ${template.title}')
      ..writeln('目的: ${template.description}');
    if (template.promptHint.trim().isNotEmpty) {
      buffer.writeln('重要方針: ${template.promptHint.trim()}');
    }
    buffer
      ..writeln('必ず次の見出しだけをこの順序で出力してください。')
      ..writeln();
    for (final section in template.sections) {
      buffer
        ..writeln('# $section')
        ..writeln('・この見出しに該当する内容を具体的に整理')
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
        section.contains('次') ||
        section.contains('宿題')) {
      return session.todos.trim().isEmpty ? '・未抽出' : session.todos.trim();
    }
    if (section.contains('キーワード') || section.contains('用語')) {
      return session.keywords.isEmpty
          ? '・未抽出'
          : '・${session.keywords.join('\n・')}';
    }
    if (section.contains('感情') ||
        section.contains('満足') ||
        section.contains('モチベーション') ||
        section.contains('懸念') ||
        section.contains('温度')) {
      final s = session.sentiment;
      return '・満足度 ${(s.satisfaction * 100).round()}%\n'
          '・モチベーション ${(s.motivation * 100).round()}%\n'
          '・懸念 ${(s.concern * 100).round()}%\n'
          '・${s.summary}';
    }
    if (normalized.contains('timeline') || section.contains('時系列')) {
      if (session.topicSegments.isEmpty) return '・未抽出';
      return session.topicSegments
          .map((topic) => '・${_formatTime(topic.startSeconds)} ${topic.title}')
          .join('\n');
    }
    if (section.contains('話者')) {
      if (session.transcriptSegments.isEmpty) return '・未抽出';
      final speakers = session.transcriptSegments
          .map((segment) => segment.speakerId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      return speakers.isEmpty
          ? '・話者情報なし'
          : speakers
                .map((id) => '・${session.speakerLabels[id] ?? id}')
                .join('\n');
    }
    return session.summary.trim().isEmpty
        ? '・${_snippet(session.cleanTranscription, '')}'
        : session.summary.trim();
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
