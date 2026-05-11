import 'package:essential_flutter/app/app_language.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_enhancements.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_controller.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_models.dart';
import 'package:essential_flutter/features/model_management/model_management_controller.dart';
import 'package:essential_flutter/app/app_preferences_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (call) async => switch (call.method) {
            'create' => 'test-recorder',
            'dispose' => null,
            _ => null,
          },
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          null,
        );
  });

  test('registers more than thirty summary templates', () {
    expect(MeetingTextProcessor.templates.length, greaterThanOrEqualTo(30));
    expect(
      MeetingTextProcessor.templates.map((template) => template.id).toSet(),
      hasLength(MeetingTextProcessor.templates.length),
    );
  });

  test('cleans fillers and extracts keywords', () {
    final cleaned = MeetingTextProcessor.cleanTranscript(
      'えー 今日は商談の確認をします。あのー 次回対応を決めます。',
    );
    expect(cleaned.contains('えー'), isFalse);
    expect(cleaned.contains('あのー'), isFalse);
    final keywords = MeetingTextProcessor.extractKeywords(cleaned);
    expect(keywords, contains('商談'));
    expect(keywords, contains('確認'));
  });

  test('search finds transcript segments with timestamps', () {
    final session = MeetingSession(
      id: 'm1',
      title: '商談',
      createdAt: DateTime(2026, 5, 2),
      audioPath: '/tmp/audio.wav',
      status: MeetingStatus.completed,
      transcriptSegments: const <MeetingTranscriptSegment>[
        MeetingTranscriptSegment(
          text: '予算折衝について話します',
          startSeconds: 67,
          endSeconds: 75,
        ),
      ],
    );
    final results = MeetingTextProcessor.search(<MeetingSession>[
      session,
    ], '予算');
    expect(results, hasLength(1));
    expect(results.single.startSeconds, 67);
  });

  test('search includes templates notes translations and speaker labels', () {
    final session = MeetingSession(
      id: 'm2',
      title: 'レビュー会議',
      createdAt: DateTime(2026, 5, 3),
      audioPath: '/tmp/audio.wav',
      status: MeetingStatus.completed,
      templateOutputs: const <String, String>{'code_review': '修正方針は入力検証を強化する'},
      noteSets: const <MeetingNoteSet>[
        MeetingNoteSet(title: '決定事項', body: '監査ログを追加する'),
      ],
      translations: const <String, String>{
        'en': 'Add audit logging and input validation.',
      },
      speakerLabels: const <String, String>{'Speaker 1': '田中'},
      transcriptSegments: const <MeetingTranscriptSegment>[
        MeetingTranscriptSegment(
          text: '検索対象の確認です',
          startSeconds: 12,
          endSeconds: 18,
          speakerId: 'Speaker 1',
        ),
      ],
    );

    expect(
      MeetingTextProcessor.search(<MeetingSession>[
        session,
      ], '入力検証').single.source,
      'テンプレート',
    );
    expect(
      MeetingTextProcessor.search(<MeetingSession>[
        session,
      ], '監査ログ').single.source,
      'ノート',
    );
    expect(
      MeetingTextProcessor.search(<MeetingSession>[
        session,
      ], 'audit').single.source,
      '翻訳',
    );
    expect(
      MeetingTextProcessor.search(<MeetingSession>[
        session,
      ], '田中').single.source,
      '話者',
    );
  });

  test('splits long meeting transcripts into bounded prompt chunks', () {
    final controller = MeetingController(
      modelController: ModelManagementController.createDefault(),
    );
    addTearDown(controller.dispose);

    final segments = List<MeetingTranscriptSegment>.generate(
      12,
      (index) => MeetingTranscriptSegment(
        text: List<String>.filled(
          18,
          '重要な論点と決定事項を含む長い発話です。担当者、期限、次の対応を全て残します。',
        ).join(),
        startSeconds: index * 60,
        endSeconds: index * 60 + 45,
        speakerId: 'Speaker ${(index % 3) + 1}',
      ),
    );

    final chunks = controller.debugFormatTranscriptChunksForPrompt(
      segments,
      '',
    );

    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks) {
      expect(chunk.runes.length, lessThanOrEqualTo(2400));
    }
    expect(chunks.join('\n'), contains('[00:00] Speaker 1'));
    expect(chunks.join('\n'), contains('[11:00] Speaker 3'));
  });

  test('formats thirty and sixty minute English meetings into chunks', () {
    final controller = MeetingController(
      modelController: ModelManagementController.createDefault(),
    );
    addTearDown(controller.dispose);

    List<MeetingTranscriptSegment> buildSegments(int minutes) {
      return List<MeetingTranscriptSegment>.generate(
        minutes,
        (index) => MeetingTranscriptSegment(
          text:
              'We discussed Pixel feature support, web search grounding, location-aware weather answers, product review comparison, meeting summary translation, and the next action owner for minute ${index + 1}.',
          startSeconds: index * 60,
          endSeconds: index * 60 + 50,
          speakerId: 'Speaker ${(index % 4) + 1}',
        ),
      );
    }

    for (final minutes in <int>[30, 60]) {
      final chunks = controller.debugFormatTranscriptChunksForPrompt(
        buildSegments(minutes),
        '',
      );
      expect(chunks, isNotEmpty);
      expect(chunks.join('\n'), contains('[00:00] Speaker 1'));
      expect(
        chunks.join('\n'),
        contains(minutes == 30 ? '[29:00]' : '[59:00]'),
      );
      for (final chunk in chunks) {
        expect(chunk.runes.length, lessThanOrEqualTo(2400));
      }
    }
  });

  test('English UI translates meeting summary to Japanese first', () async {
    final preferences = AppPreferencesController();
    await preferences.updateLanguagePreference(AppLanguagePreference.english);
    final controller = MeetingController(
      modelController: ModelManagementController.createDefault(),
      preferencesController: preferences,
    );
    addTearDown(controller.dispose);

    expect(controller.useEnglish, isTrue);
    expect(controller.debugPrimaryTranslationKey(), 'ja');
    expect(controller.debugTranslationTargets().keys, contains('ja'));
    expect(controller.debugTranslationTargets().keys, isNot(contains('en')));
  });

  test('Japanese UI keeps English Chinese and Korean translation targets', () {
    final controller = MeetingController(
      modelController: ModelManagementController.createDefault(),
    );
    addTearDown(controller.dispose);

    expect(controller.useEnglish, isFalse);
    expect(controller.debugPrimaryTranslationKey(), 'en');
    expect(
      controller.debugTranslationTargets().keys,
      containsAll(<String>['en', 'zh', 'ko']),
    );
  });
}
