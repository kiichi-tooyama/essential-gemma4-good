import 'package:essential_sdk_dart/essential_sdk_dart.dart';

Future<void> main() async {
  final client = await EssentialClient.initialize(
    const EssentialConfiguration(
      defaultModelId: 'essential-mini',
      installedModels: <EssentialInstalledModel>[
        EssentialInstalledModel(
          modelId: 'essential-mini',
          modelPath: '/tmp/essential-mini.gguf',
          family: 'llama.cpp',
          contextWindow: 4096,
        ),
      ],
    ),
  );

  await for (final chunk in client.generateStream(
    const EssentialGenerateRequest(
      prompt: '端末内だけで応答して',
      modelRequirement: EssentialModelRequirement.fallback('essential-mini'),
      timeoutMs: 5000,
    ),
  )) {
    print(chunk.accumulatedText);
  }

  await client.dispose();
}