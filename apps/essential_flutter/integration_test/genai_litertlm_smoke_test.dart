import 'dart:io';

import 'package:essential_sdk_dart/essential_sdk_dart.dart' as essential;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LiteRT-LM E2B is discoverable and generates a short answer',
    (tester) async {
      final modelPath = _directLiteRtLmModelPath('gemma-4-E2B-it.litertlm');
      final e4bModelPath = _directLiteRtLmModelPath('gemma-4-E4B-it.litertlm');
      debugPrint('ESSENTIAL_GENAI_SEED path=$modelPath');

      final runtime = essential.EssentialGenAiRuntime();
      final models = await runtime.discoverModels();
      for (final model in models) {
        debugPrint(
          'ESSENTIAL_GENAI_MODEL id=${model.id} title=${model.title} '
          'size=${model.sizeBytes} path=${model.path}',
        );
      }
      expect(
        models.any((model) => model.path == modelPath),
        isTrue,
        reason: 'LiteRT-LM model was not discovered.',
      );
      expect(
        models.any((model) => model.path == e4bModelPath),
        isTrue,
        reason: 'E4B LiteRT-LM model was not discovered.',
      );

      final warmup = await runtime
          .warmUp(
            modelPath: modelPath,
            maxTokens: 4000,
            contextTokens: 4000,
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            accelerator: 'gpu',
          )
          .timeout(const Duration(minutes: 5));
      debugPrint(
        'ESSENTIAL_GENAI_WARMUP loadAndSetupMs=${warmup?.loadAndSetupMs} contextTokens=${warmup?.contextTokens}',
      );

      final result = await runtime
          .generate(
            modelPath: modelPath,
            prompt: '日本語で一文だけ答えてください。Web検索機能は何に使いますか？',
            maxTokens: 64,
            contextTokens: 4000,
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            accelerator: 'gpu',
          )
          .timeout(const Duration(minutes: 10));
      final text = _cleanOutput(result.text);
      debugPrint(
        'ESSENTIAL_GENAI_RESULT chars=${text.runes.length} '
        'latencyMs=${result.latencyMs} loadAndSetupMs=${result.loadAndSetupMs} firstTokenMs=${result.firstTokenMs} generationMs=${result.generationMs} text=$text',
      );
      expect(text, isNotEmpty);
      expect(text.contains('Web') || text.contains('検索'), isTrue);

      final highAccuracy = await runtime
          .generate(
            modelPath: e4bModelPath,
            prompt: '日本語で短く一文だけ答えてください。高精度AIの利点は？',
            maxTokens: 32,
            contextTokens: 4000,
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            accelerator: 'gpu',
          )
          .timeout(const Duration(minutes: 10));
      final highAccuracyText = _cleanOutput(highAccuracy.text);
      debugPrint(
        'ESSENTIAL_GENAI_E4B_RESULT chars=${highAccuracyText.runes.length} '
        'latencyMs=${highAccuracy.latencyMs} loadAndSetupMs=${highAccuracy.loadAndSetupMs} '
        'firstTokenMs=${highAccuracy.firstTokenMs} generationMs=${highAccuracy.generationMs} text=$highAccuracyText',
      );
      expect(highAccuracyText, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

String _directLiteRtLmModelPath(String fileName) {
  final source = File('/data/local/tmp/essential_genai_seed/$fileName');
  expect(source.existsSync(), isTrue, reason: '${source.path} missing');
  return source.path;
}

String _cleanOutput(String text) {
  return text
      .replaceAll('<end_of_turn>', '')
      .replaceAll('<turn|>', '')
      .replaceAll('</s>', '')
      .replaceAll(RegExp(r'<\|/?(?:user|assistant|system|turn)\|?>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
