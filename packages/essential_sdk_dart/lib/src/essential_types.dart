import 'dart:io';

import 'essential_llama_runtime.dart';

enum EssentialErrorCode {
  modelNotInstalled('MODEL_NOT_INSTALLED'),
  modelIncompatible('MODEL_INCOMPATIBLE'),
  adapterIncompatible('ADAPTER_INCOMPATIBLE'),
  deviceCapacityInsufficient('DEVICE_CAPACITY_INSUFFICIENT'),
  permissionDenied('PERMISSION_DENIED'),
  sessionCancelled('SESSION_CANCELLED'),
  runtimeUnavailable('RUNTIME_UNAVAILABLE'),
  invalidConfiguration('INVALID_CONFIGURATION'),
  requestTimedOut('REQUEST_TIMED_OUT'),
  unsupportedTaskType('UNSUPPORTED_TASK_TYPE'),
  payloadSchemaInvalid('PAYLOAD_SCHEMA_INVALID'),
  modalityPermissionDenied('MODALITY_PERMISSION_DENIED'),
  capabilityNotAvailable('CAPABILITY_NOT_AVAILABLE'),
  bundleDependencyMissing('BUNDLE_DEPENDENCY_MISSING'),
  realtimeNotSupported('REALTIME_NOT_SUPPORTED');

  const EssentialErrorCode(this.wireName);

  final String wireName;
}

class EssentialException implements Exception {
  const EssentialException(this.code, this.message, {this.cause});

  final EssentialErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'EssentialException(${code.wireName}): $message';
}

class EssentialInstalledModel {
  const EssentialInstalledModel({
    required this.modelId,
    required this.modelPath,
    this.family,
    this.capabilities = const <String>[],
    this.contextWindow,
    this.supportsAdapters = false,
  });

  final String modelId;
  final String modelPath;
  final String? family;
  final List<String> capabilities;
  final int? contextWindow;
  final bool supportsAdapters;

  bool get isInstalled => File(modelPath).existsSync();
}

class EssentialModelRequirement {
  const EssentialModelRequirement({
    this.modelId,
    this.family,
    this.capability,
    this.minContextWindow,
    this.maxLatencyMs,
    this.allowFallback = true,
    this.explicitModelPath,
  });

  const EssentialModelRequirement.anyCompatible({
    this.family,
    this.capability,
    this.minContextWindow,
    this.maxLatencyMs,
  }) : modelId = null,
       allowFallback = true,
       explicitModelPath = null;

  const EssentialModelRequirement.fixed(
    String this.modelId, {
    this.family,
    this.capability,
    this.minContextWindow,
    this.maxLatencyMs,
  }) : allowFallback = false,
       explicitModelPath = null;

  const EssentialModelRequirement.fallback(
    String this.modelId, {
    this.family,
    this.capability,
    this.minContextWindow,
    this.maxLatencyMs,
  }) : allowFallback = true,
       explicitModelPath = null;

  final String? modelId;
  final String? family;
  final String? capability;
  final int? minContextWindow;
  final int? maxLatencyMs;
  final bool allowFallback;
  final String? explicitModelPath;

  EssentialModelRequirement copyWith({
    String? modelId,
    String? family,
    String? capability,
    int? minContextWindow,
    int? maxLatencyMs,
    bool? allowFallback,
    String? explicitModelPath,
  }) {
    return EssentialModelRequirement(
      modelId: modelId ?? this.modelId,
      family: family ?? this.family,
      capability: capability ?? this.capability,
      minContextWindow: minContextWindow ?? this.minContextWindow,
      maxLatencyMs: maxLatencyMs ?? this.maxLatencyMs,
      allowFallback: allowFallback ?? this.allowFallback,
      explicitModelPath: explicitModelPath ?? this.explicitModelPath,
    );
  }
}

enum EssentialInputKind { text, image, audio, url, document, reference }

class EssentialInputAttachment {
  const EssentialInputAttachment({
    required this.kind,
    this.text,
    this.filePath,
    this.uri,
    this.mimeType,
    this.name,
    this.metadata = const <String, Object?>{},
  });

  const EssentialInputAttachment.text(
    String this.text, {
    this.name,
    this.metadata = const <String, Object?>{},
  }) : kind = EssentialInputKind.text,
       filePath = null,
       uri = null,
       mimeType = 'text/plain';

  const EssentialInputAttachment.imageFile(
    String this.filePath, {
    this.name,
    this.mimeType = 'image/*',
    this.metadata = const <String, Object?>{},
  }) : kind = EssentialInputKind.image,
       text = null,
       uri = null;

  const EssentialInputAttachment.audioFile(
    String this.filePath, {
    this.name,
    this.mimeType = 'audio/*',
    this.metadata = const <String, Object?>{},
  }) : kind = EssentialInputKind.audio,
       text = null,
       uri = null;

  const EssentialInputAttachment.url(
    String this.uri, {
    this.name,
    this.metadata = const <String, Object?>{},
  }) : kind = EssentialInputKind.url,
       text = null,
       filePath = null,
       mimeType = 'text/uri-list';

  final EssentialInputKind kind;
  final String? text;
  final String? filePath;
  final String? uri;
  final String? mimeType;
  final String? name;
  final Map<String, Object?> metadata;
}

class EssentialReferenceDocument {
  const EssentialReferenceDocument({
    required this.title,
    this.text = '',
    this.uri,
    this.filePath,
    this.mimeType = 'text/plain',
    this.metadata = const <String, Object?>{},
  });

  final String title;
  final String text;
  final String? uri;
  final String? filePath;
  final String mimeType;
  final Map<String, Object?> metadata;
}

class EssentialRuntimeOptions {
  const EssentialRuntimeOptions({
    this.preferredModelId,
    this.webSearchEnabled = false,
    this.locationEnabled = false,
    this.sharedMemoryEnabled = false,
    bool? sharedMemoryReadEnabled,
    bool? sharedMemoryWriteEnabled,
    this.spokenOutputEnabled = false,
  }) : sharedMemoryReadEnabled = sharedMemoryReadEnabled ?? sharedMemoryEnabled,
       sharedMemoryWriteEnabled =
           sharedMemoryWriteEnabled ?? sharedMemoryEnabled;

  final String? preferredModelId;
  final bool webSearchEnabled;
  final bool locationEnabled;
  @Deprecated(
    'Use sharedMemoryReadEnabled and sharedMemoryWriteEnabled for per-request control.',
  )
  final bool sharedMemoryEnabled;
  final bool sharedMemoryReadEnabled;
  final bool sharedMemoryWriteEnabled;
  final bool spokenOutputEnabled;
}

class EssentialGenerateRequest {
  const EssentialGenerateRequest({
    this.id,
    this.sessionId,
    required this.prompt,
    this.systemInstruction = '',
    this.attachments = const <EssentialInputAttachment>[],
    this.referenceDocuments = const <EssentialReferenceDocument>[],
    this.modelRequirement = const EssentialModelRequirement.anyCompatible(),
    this.runtimeOptions = const EssentialRuntimeOptions(),
    this.maxTokens = 64,
    this.topK = 40,
    this.topP = 0.95,
    this.temperature = 0.8,
    this.seed = 42,
    this.timeoutMs,
  });

  final String? id;
  final String? sessionId;
  final String prompt;
  final String systemInstruction;
  final List<EssentialInputAttachment> attachments;
  final List<EssentialReferenceDocument> referenceDocuments;
  final EssentialModelRequirement modelRequirement;
  final EssentialRuntimeOptions runtimeOptions;
  final int maxTokens;
  final int topK;
  final double topP;
  final double temperature;
  final int seed;
  final int? timeoutMs;

  EssentialGenerateRequest copyWith({
    String? id,
    String? sessionId,
    String? prompt,
    String? systemInstruction,
    List<EssentialInputAttachment>? attachments,
    List<EssentialReferenceDocument>? referenceDocuments,
    EssentialModelRequirement? modelRequirement,
    EssentialRuntimeOptions? runtimeOptions,
    int? maxTokens,
    int? topK,
    double? topP,
    double? temperature,
    int? seed,
    int? timeoutMs,
  }) {
    return EssentialGenerateRequest(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      prompt: prompt ?? this.prompt,
      systemInstruction: systemInstruction ?? this.systemInstruction,
      attachments: attachments ?? this.attachments,
      referenceDocuments: referenceDocuments ?? this.referenceDocuments,
      modelRequirement: modelRequirement ?? this.modelRequirement,
      runtimeOptions: runtimeOptions ?? this.runtimeOptions,
      maxTokens: maxTokens ?? this.maxTokens,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      temperature: temperature ?? this.temperature,
      seed: seed ?? this.seed,
      timeoutMs: timeoutMs ?? this.timeoutMs,
    );
  }
}

class EssentialGenerateChunk {
  const EssentialGenerateChunk({
    required this.requestId,
    required this.delta,
    required this.accumulatedText,
    required this.modelUsed,
  });

  final String requestId;
  final String delta;
  final String accumulatedText;
  final String modelUsed;
}

class EssentialGenerateResult {
  const EssentialGenerateResult({
    required this.requestId,
    required this.text,
    required this.modelUsed,
    required this.finishReason,
  });

  final String requestId;
  final String text;
  final String modelUsed;
  final String finishReason;
}

class EssentialConfiguration {
  const EssentialConfiguration({
    this.installedModels = const <EssentialInstalledModel>[],
    this.defaultModelId,
    this.modelLoadOptions = const EssentialLlamaModelOptions(),
  });

  final List<EssentialInstalledModel> installedModels;
  final String? defaultModelId;
  final EssentialLlamaModelOptions modelLoadOptions;
}
