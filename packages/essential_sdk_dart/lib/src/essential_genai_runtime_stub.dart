final class EssentialGenAiGenerationResult {
  const EssentialGenAiGenerationResult({
    required this.text,
    required this.modelPath,
    required this.latencyMs,
    required this.generationMs,
    this.loadAndSetupMs,
    this.firstTokenMs,
    this.accelerator,
    this.visionAccelerator,
  });

  final String text;
  final String modelPath;
  final int latencyMs;
  final int generationMs;
  final int? loadAndSetupMs;
  final int? firstTokenMs;
  final String? accelerator;
  final String? visionAccelerator;
}

final class EssentialGenAiWarmupResult {
  const EssentialGenAiWarmupResult({
    required this.modelPath,
    required this.loadAndSetupMs,
    required this.contextTokens,
    this.accelerator,
    this.visionAccelerator,
  });

  final String modelPath;
  final int loadAndSetupMs;
  final int contextTokens;
  final String? accelerator;
  final String? visionAccelerator;
}

final class EssentialGenAiModel {
  const EssentialGenAiModel({
    required this.id,
    required this.title,
    required this.path,
    required this.sizeBytes,
  });

  final String id;
  final String title;
  final String path;
  final int sizeBytes;
}

final class EssentialGenAiRuntime {
  const EssentialGenAiRuntime();

  Future<bool> get isAvailable async => false;

  Future<List<EssentialGenAiModel>> discoverModels() async {
    return const <EssentialGenAiModel>[];
  }

  Future<EssentialGenAiGenerationResult> generate({
    required String modelPath,
    required String prompt,
    List<String> imagePaths = const <String>[],
    List<String> audioPaths = const <String>[],
    int maxTokens = 512,
    int contextTokens = 4000,
    int topK = 64,
    double topP = 0.95,
    double temperature = 1.0,
    String accelerator = 'gpu',
    String visionAccelerator = 'gpu',
    bool enableThinking = false,
    String systemInstruction = '',
    String? requestId,
    void Function(String token)? onToken,
  }) async {
    throw UnsupportedError(
      'Essential GenAI runtime requires a Flutter platform channel.',
    );
  }

  Future<EssentialGenAiWarmupResult?> warmUp({
    required String modelPath,
    int maxTokens = 512,
    int contextTokens = 4000,
    int topK = 64,
    double topP = 0.95,
    double temperature = 1.0,
    String accelerator = 'gpu',
    String visionAccelerator = 'gpu',
    String? requestId,
  }) async {
    return null;
  }

  Future<void> releaseIdle({String? keepModelPath}) async {}

  Future<void> cancel() async {}
}
