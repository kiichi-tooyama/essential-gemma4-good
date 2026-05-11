import 'dart:convert';
import 'dart:io';

import 'package:essential_flutter/features/meeting_assistant/meeting_controller.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_models.dart';
import 'package:essential_flutter/features/model_management/model_management_controller.dart';
import 'package:essential_flutter/features/shared/audio_tools_service.dart';
import 'package:essential_flutter/features/shared/web_research_service.dart';
import 'package:essential_sdk_dart/essential_sdk_dart.dart' as essential;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'web works for multiple content categories',
    (tester) async {
      final service = WebResearchService();
      final queries = <String>[
        '今日の東京の天気 最新',
        'Apple 株価 現在',
        'OpenAI 最新ニュース',
        '大阪万博 2026 最新情報',
      ];

      for (final query in queries) {
        final result = await service.research(query);
        debugPrint(
          'ESSENTIAL_WEB_MULTI_RESULT query="$query" sources=${result.sources.length} '
          'first=${result.sources.isEmpty ? "" : result.sources.first.title} '
          'url=${result.sources.isEmpty ? "" : result.sources.first.url}',
        );
        expect(result.sources, isNotEmpty, reason: query);
        expect(
          result.sources.any((source) => source.url.trim().isNotEmpty),
          isTrue,
          reason: query,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'lightweight chat models generate natural short answers or are fallback candidates',
    (tester) async {
      await _seedModelsFromLocalTmp();
      final modelController = ModelManagementController.createDefault();
      await modelController.initialize();
      final chatModelIds = <String>['gemma-4-e2b-litertlm-it'];

      for (final modelId in chatModelIds) {
        final text = await _generateShortModelAnswer(modelController, modelId);
        _expectNaturalOrFallbackCandidate(modelId, text);
      }
    },
    timeout: const Timeout(Duration(minutes: 18)),
  );

  testWidgets(
    'all chat bundle models generate short answers',
    (tester) async {
      await _seedModelsFromLocalTmp();
      final modelController = ModelManagementController.createDefault();
      await modelController.initialize();
      final chatModelIds = <String>[
        'gemma-4-e2b-litertlm-it',
        'gemma-4-e4b-litertlm-it',
      ];

      for (final modelId in chatModelIds) {
        final text = await _generateShortModelAnswer(modelController, modelId);
        expect(text, isNotEmpty, reason: modelId);
        _expectNaturalOrFallbackCandidate(modelId, text);
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  testWidgets(
    'meeting assistant processes 366 mp3',
    (tester) async {
      await _seedModelsFromLocalTmp();
      const mp3Path = '/sdcard/Download/366.mp3';
      expect(File(mp3Path).existsSync(), isTrue, reason: '$mp3Path missing');

      final normalized = await const AudioToolsService().normalizeToSpeechWav(
        mp3Path,
        maxDuration: const Duration(seconds: 45),
      );
      final header = await File(normalized).openRead(0, 12).first;
      debugPrint(
        'ESSENTIAL_366_NORMALIZE_RESULT source=$mp3Path normalized=$normalized '
        'size=${File(normalized).lengthSync()}',
      );
      expect(String.fromCharCodes(header.take(4)), 'RIFF');
      expect(String.fromCharCodes(header.skip(8).take(4)), 'WAVE');

      final modelController = ModelManagementController.createDefault();
      await modelController.initialize();
      final meetingController = MeetingController(
        modelController: modelController,
      );
      addTearDown(meetingController.dispose);
      await meetingController.initialize();
      await meetingController.processMeeting(
        normalized,
        false,
        recordingSource: 'import_with_transcript',
        initialTranscription:
            'This meeting transcript is supplied with the imported audio. '
            'The speaker explains Essential as a local Gemma 4 LiteRT-LM '
            'assistant that other apps can call through an API. It accepts '
            'text, voice, image, and transcript inputs, can use web search '
            'and current location, and can return text or spoken answers.',
      );

      var remainingSeconds = 900;
      while (remainingSeconds > 0 &&
          meetingController.sessions.isNotEmpty &&
          meetingController.sessions.first.status == MeetingStatus.processing) {
        await Future<void>.delayed(const Duration(seconds: 1));
        remainingSeconds -= 1;
      }

      final session = meetingController.sessions.first;
      debugPrint(
        'ESSENTIAL_366_MEETING_RESULT status=${session.status.name} '
        'summaryChars=${session.summary.runes.length} '
        'transcriptionChars=${session.transcription.runes.length} '
        'todoChars=${session.todos.runes.length} '
        'translations=${session.translations.keys.join(",")}',
      );
      debugPrint(
        'ESSENTIAL_366_TRANSCRIPTION_HEAD=${_takeRunes(session.transcription, 240)}',
      );
      debugPrint(
        'ESSENTIAL_366_SUMMARY_HEAD=${_takeRunes(session.summary, 240)}',
      );

      expect(session.status, MeetingStatus.completed);
      expect(session.transcription.trim(), isNotEmpty);
      expect(session.summary.trim(), isNotEmpty);
      expect(session.translations['en']?.trim(), isNotEmpty);
      expect(session.translations['zh']?.trim(), isNotEmpty);
      expect(session.translations['ko']?.trim(), isNotEmpty);

      final answer = await meetingController.askMeetingQuestion(
        session,
        'この音声内容を踏まえて、次に確認すべきことを短く整理して。',
        useWeb: true,
      );
      debugPrint('ESSENTIAL_366_MEETING_QA=$answer');
      expect(answer.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<void> _seedModelsFromLocalTmp() async {
  final source = Directory('/data/local/tmp/essential_model_seed');
  if (!source.existsSync()) {
    debugPrint('ESSENTIAL_MODEL_SEED_SKIPPED source_missing=${source.path}');
    return;
  }
  final support = await getApplicationSupportDirectory();
  final target = Directory(path.join(support.path, 'essential_models'));
  final metadata = File(path.join(target.path, 'metadata.json'));
  if (metadata.existsSync()) {
    try {
      final payload =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      final installations =
          payload['installations'] as List<dynamic>? ?? const <dynamic>[];
      if (installations.length >= 8) {
        debugPrint('ESSENTIAL_MODEL_SEED_READY existing=${target.path}');
        return;
      }
    } catch (_) {}
  }
  if (target.existsSync()) {
    await target.delete(recursive: true);
  }
  await _copyDirectory(source, target);
  debugPrint('ESSENTIAL_MODEL_SEED_COPIED target=${target.path}');
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: false)) {
    final name = path.basename(entity.path);
    final nextPath = path.join(target.path, name);
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(nextPath));
    } else if (entity is File) {
      await entity.copy(nextPath);
    }
  }
}

String _takeRunes(String text, int count) {
  if (text.runes.length <= count) {
    return text;
  }
  return String.fromCharCodes(text.runes.take(count));
}

Future<String> _generateShortModelAnswer(
  ModelManagementController modelController,
  String modelId,
) async {
  final component = modelController.componentInstallationFor(modelId);
  final direct = modelController.installationFor(modelId);
  final modelPath = component?.activePath ?? direct?.activePath;
  debugPrint('ESSENTIAL_MODEL_SMOKE_START id=$modelId path=$modelPath');
  expect(modelPath, isNotNull, reason: '$modelId is not installed');
  expect(modelPath!.toLowerCase().endsWith('.litertlm'), isTrue);

  final runtime = essential.EssentialGenAiRuntime();
  try {
    final result = await runtime
        .generate(
          requestId: 'smoke-$modelId-${DateTime.now().microsecondsSinceEpoch}',
          modelPath: modelPath,
          prompt: '今回のユーザー入力:\nWeb検索機能は何に使いますか？ 一文だけで自然に答えてください。',
          systemInstruction:
              'あなたはEssentialです。自然な日本語で、質問に直接答えてください。'
              '内部メモ、プロンプト形式、役割名、特殊トークン、前置き、確認質問を書かないでください。'
              '同じ文を繰り返さず、答えだけを書いてください。',
          maxTokens: 96,
          contextTokens: 4000,
          topK: 8,
          topP: 0.82,
          temperature: 0.15,
          accelerator: 'gpu',
        )
        .timeout(const Duration(minutes: 6));
    final text = _cleanLlamaSmokeOutput(result.text);
    debugPrint('ESSENTIAL_MODEL_SMOKE_RESULT id=$modelId text=$text');
    expect(text, isNotEmpty, reason: modelId);
    return text;
  } finally {
    try {
      await runtime.releaseIdle().timeout(const Duration(seconds: 20));
    } catch (error) {
      debugPrint('ESSENTIAL_MODEL_SMOKE_DISPOSE_FAILED id=$modelId $error');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

void _expectNaturalOrFallbackCandidate(String modelId, String text) {
  if (_looksLikeNaturalShortAnswer(text)) {
    return;
  }
  final isKnownLightweightModel =
      modelId.contains('gemma-4-e2b') || modelId.contains('essential-mini');
  debugPrint('ESSENTIAL_MODEL_SMOKE_FALLBACK_CANDIDATE id=$modelId text=$text');
  expect(isKnownLightweightModel, isTrue, reason: text);
  expect(_looksLikeFallbackCandidate(text), isTrue, reason: text);
}

bool _looksLikeNaturalShortAnswer(String text) {
  final normalized = text.trim();
  if (normalized.runes.length < 8 || normalized.runes.length > 260) {
    return false;
  }
  final lower = normalized.toLowerCase();
  if (lower.contains('http') ||
      lower.contains('google translate') ||
      lower.contains('sample conversation') ||
      lower.contains('interlocutor') ||
      lower.contains('japanese:') ||
      lower.contains('english:') ||
      lower.contains('do not translate the prompt') ||
      lower.contains('answer only the user question') ||
      lower.contains('<start_of_turn>') ||
      lower.contains('<|turn>') ||
      lower.contains('<turn|>') ||
      lower.contains('<|assistant|>') ||
      lower.contains('<|user|>') ||
      lower.contains('</s>')) {
    return false;
  }
  if (RegExp(
    r'^(user|assistant|model|system)\s*[:：]?',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return false;
  }
  if (normalized.contains('質問に必要な内容だけ') || normalized.contains('一文で答えてください')) {
    return false;
  }
  if (normalized.contains('思考過程') ||
      normalized.contains('役割名') ||
      normalized.contains('内部メモ') ||
      normalized.contains('話者ラベル')) {
    return false;
  }
  if (_hasRepeatedContent(normalized)) {
    return false;
  }
  if (RegExp(r'[ぁ-んァ-ン一-龥]$').hasMatch(normalized) &&
      !RegExp(r'[。.!！?？]$').hasMatch(normalized) &&
      normalized.runes.length > 36) {
    return false;
  }
  return normalized.contains('検索') || normalized.contains('情報');
}

bool _looksLikeFallbackCandidate(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return true;
  }
  final lower = normalized.toLowerCase();
  return lower.contains('<end_of') ||
      lower.contains('<start_of') ||
      lower.contains('<|turn>') ||
      lower.contains('<turn|>') ||
      lower.contains('<|') ||
      normalized.contains('思考過程') ||
      normalized.contains('役割名') ||
      normalized.contains('内部メモ') ||
      normalized.contains('話者ラベル') ||
      (normalized.contains('承知') && normalized.contains('どのような')) ||
      lower.contains('sample conversation') ||
      lower.contains('interlocutor') ||
      normalized.contains('質問を質問') ||
      normalized.contains('質問を、その質問') ||
      _hasRepeatedContent(normalized) ||
      (RegExp(r'[ぁ-んァ-ン一-龥]$').hasMatch(normalized) &&
          !RegExp(r'[。.!！?？]$').hasMatch(normalized) &&
          normalized.runes.length > 36);
}

bool _hasRepeatedContent(String text) {
  final segments = text
      .split(RegExp(r'[、。,.!！?？\n]+'))
      .map((segment) => segment.replaceAll(RegExp(r'[*_「」『』\s]'), ''))
      .where((segment) => segment.runes.length >= 6)
      .toList(growable: false);
  final counts = <String, int>{};
  for (final segment in segments) {
    final count = (counts[segment] ?? 0) + 1;
    if (count >= 3) {
      return true;
    }
    counts[segment] = count;
  }
  return false;
}

String _cleanLlamaSmokeOutput(String text) {
  final cleanedLines = <String>[];
  final seen = <String>{};
  for (final rawLine in text.trim().split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final normalized = line
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[、。,.!！?？:：;；「」『』"“”]+'), '');
    if (seen.contains(normalized) ||
        line.contains('質問に必要な内容だけ') ||
        line.contains('一文で答えてください') ||
        line.toLowerCase().contains('do not translate the prompt') ||
        line.toLowerCase().contains('answer only the user question')) {
      continue;
    }
    seen.add(normalized);
    cleanedLines.add(line);
  }
  return cleanedLines.join('\n').trim();
}
