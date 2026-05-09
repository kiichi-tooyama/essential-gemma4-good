import 'package:flutter/services.dart';

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

  factory EssentialGenAiGenerationResult.fromJson(Map<Object?, Object?> json) {
    return EssentialGenAiGenerationResult(
      text: json['text'] as String? ?? '',
      modelPath: json['modelPath'] as String? ?? '',
      latencyMs: json['latencyMs'] as int? ?? 0,
      generationMs: json['generationMs'] as int? ?? 0,
      loadAndSetupMs: json['loadAndSetupMs'] as int?,
      firstTokenMs: json['firstTokenMs'] as int?,
      accelerator: json['accelerator'] as String?,
      visionAccelerator: json['visionAccelerator'] as String?,
    );
  }

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

  factory EssentialGenAiWarmupResult.fromJson(Map<Object?, Object?> json) {
    return EssentialGenAiWarmupResult(
      modelPath: json['modelPath'] as String? ?? '',
      loadAndSetupMs: json['loadAndSetupMs'] as int? ?? 0,
      contextTokens: json['contextTokens'] as int? ?? 0,
      accelerator: json['accelerator'] as String?,
      visionAccelerator: json['visionAccelerator'] as String?,
    );
  }

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

  factory EssentialGenAiModel.fromJson(Map<Object?, Object?> json) {
    return EssentialGenAiModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      path: json['path'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
    );
  }

  final String id;
  final String title;
  final String path;
  final int sizeBytes;
}

final class EssentialGenAiRuntime {
  EssentialGenAiRuntime({
    MethodChannel channel = const MethodChannel('essential/genai'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final Map<String, void Function(String token)> _tokenCallbacks =
      <String, void Function(String token)>{};

  Future<bool> get isAvailable async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<EssentialGenAiModel>> discoverModels() async {
    try {
      final response = await _channel.invokeMethod<List<Object?>>(
        'discoverModels',
      );
      return (response ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(EssentialGenAiModel.fromJson)
          .where((model) => model.path.isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const <EssentialGenAiModel>[];
    }
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
    final resolvedRequestId =
        requestId ?? 'genai-${DateTime.now().microsecondsSinceEpoch}';
    if (onToken != null) {
      _tokenCallbacks[resolvedRequestId] = onToken;
    }
    try {
      final response = await _channel
          .invokeMethod<Map<Object?, Object?>>('generate', <String, Object?>{
            'requestId': resolvedRequestId,
            'modelPath': modelPath,
            'prompt': prompt,
            'imagePaths': imagePaths,
            'audioPaths': audioPaths,
            'maxTokens': maxTokens,
            'contextTokens': contextTokens,
            'topK': topK,
            'topP': topP,
            'temperature': temperature,
            'accelerator': accelerator,
            'visionAccelerator': visionAccelerator,
            'enableThinking': enableThinking,
            'systemInstruction': systemInstruction,
          });
      if (response == null) {
        throw StateError('GenAI runtime returned an empty response.');
      }
      return EssentialGenAiGenerationResult.fromJson(response);
    } finally {
      _tokenCallbacks.remove(resolvedRequestId);
    }
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
    try {
      final response = await _channel
          .invokeMethod<Map<Object?, Object?>>('warmUp', <String, Object?>{
            'requestId':
                requestId ?? 'warm-${DateTime.now().microsecondsSinceEpoch}',
            'modelPath': modelPath,
            'maxTokens': maxTokens,
            'contextTokens': contextTokens,
            'topK': topK,
            'topP': topP,
            'temperature': temperature,
            'accelerator': accelerator,
            'visionAccelerator': visionAccelerator,
          });
      if (response == null) {
        return null;
      }
      return EssentialGenAiWarmupResult.fromJson(response);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> releaseIdle({String? keepModelPath}) async {
    try {
      await _channel.invokeMethod<void>('releaseIdle', <String, Object?>{
        'keepModelPath': keepModelPath,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'token') {
      return;
    }
    final args = call.arguments as Map<Object?, Object?>?;
    final requestId = args?['requestId'] as String?;
    final token = args?['token'] as String?;
    if (requestId == null || token == null) {
      return;
    }
    _tokenCallbacks[requestId]?.call(token);
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      return;
    }
  }
}
