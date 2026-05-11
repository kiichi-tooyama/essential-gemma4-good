import 'dart:io';

import 'package:essential_flutter/features/shared/audio_tools_service.dart';
import 'package:essential_flutter/features/shared/web_research_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('short news and current-location weather trigger web context', (
    tester,
  ) async {
    final service = WebResearchService();

    expect(service.shouldUseWeb('ニュースを教えて'), isTrue);
    expect(service.shouldUseWeb('現在地の天気は？'), isTrue);

    final locationOnlyContext = const WebResearchResult(
      query: '現在地の天気は？',
      sources: <WebSource>[],
      locationContext: '緯度 35.681236, 経度 139.767125, 精度 約20m',
    ).buildPromptContext();

    expect(locationOnlyContext, contains('ユーザーの現在地情報'));
    expect(locationOnlyContext, contains('35.681236'));
  });

  testWidgets('web research returns live sources', (tester) async {
    final result = await WebResearchService().research('今日の東京の天気 最新');
    debugPrint(
      'ESSENTIAL_WEB_RESEARCH_RESULT sources=${result.sources.length} '
      'first=${result.sources.isEmpty ? '' : result.sources.first.title}',
    );

    expect(result.sources, isNotEmpty);
    expect(result.sources.any((source) => source.url.isNotEmpty), isTrue);
  });

  testWidgets('mp3 audio normalizes to a wav file for meeting analysis', (
    tester,
  ) async {
    const mp3Path = '/data/local/tmp/essential-meeting-test.mp3';
    if (!File(mp3Path).existsSync()) {
      debugPrint('Skipping MP3 normalize test: $mp3Path not found.');
      return;
    }

    final wavPath = await const AudioToolsService().normalizeToSpeechWav(
      mp3Path,
    );
    final header = await File(wavPath).openRead(0, 12).first;
    debugPrint('ESSENTIAL_AUDIO_NORMALIZE_RESULT path=$wavPath');

    expect(wavPath.endsWith('.wav'), isTrue);
    expect(String.fromCharCodes(header.take(4)), 'RIFF');
    expect(String.fromCharCodes(header.skip(8).take(4)), 'WAVE');
  });
}
