import 'dart:typed_data';

import 'essential_types.dart';

enum EssentialTaskType {
  textGeneration('text_generation'),
  imageClassification('image_classification'),
  objectDetection('object_detection'),
  imageSegmentation('image_segmentation'),
  ocr('ocr'),
  faceDetection('face_detection'),
  imageCaption('caption'),
  multimodalChat('multimodal_chat'),
  stt('stt'),
  tts('tts'),
  voiceCommand('voice_command'),
  audioClassification('audio_classification'),
  speakerRecognition('speaker_recognition'),
  locationContext('location_context'),
  mapReasoning('map_reasoning');

  const EssentialTaskType(this.wireName);

  final String wireName;
}

enum EssentialRuntimeFamily {
  llamaCpp('llama.cpp'),
  onnx('onnx'),
  tflite('tflite'),
  mediaPipe('mediapipe'),
  android('android');

  const EssentialRuntimeFamily(this.wireName);

  final String wireName;
}

enum EssentialTaskEventType {
  started('started'),
  partialResult('partial_result'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const EssentialTaskEventType(this.wireName);

  final String wireName;
}

enum EssentialTaskStatus {
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const EssentialTaskStatus(this.wireName);

  final String wireName;
}

abstract interface class EssentialTaskPayload {
  const EssentialTaskPayload();
}

final class EssentialTextTaskPayload implements EssentialTaskPayload {
  const EssentialTextTaskPayload({
    required this.prompt,
    this.maxTokens = 64,
    this.topK = 40,
    this.topP = 0.95,
    this.temperature = 0.8,
    this.seed = 42,
  });

  final String prompt;
  final int maxTokens;
  final int topK;
  final double topP;
  final double temperature;
  final int seed;
}

final class EssentialMultimodalTaskPayload implements EssentialTaskPayload {
  const EssentialMultimodalTaskPayload({
    required this.prompt,
    this.textInputs = const <String>[],
    this.imagePaths = const <String>[],
    this.audioPaths = const <String>[],
    this.urls = const <String>[],
    this.referenceDocuments = const <String, String>{},
    this.metadata = const <String, Object?>{},
  });

  final String prompt;
  final List<String> textInputs;
  final List<String> imagePaths;
  final List<String> audioPaths;
  final List<String> urls;
  final Map<String, String> referenceDocuments;
  final Map<String, Object?> metadata;
}

final class EssentialTensorTaskPayload implements EssentialTaskPayload {
  EssentialTensorTaskPayload({
    required Float32List data,
    required List<int> shape,
    this.labels = const <String>[],
    this.topK = 5,
    this.metadata = const <String, Object?>{},
  }) : data = Float32List.fromList(data),
       shape = List<int>.unmodifiable(shape);

  final Float32List data;
  final List<int> shape;
  final List<String> labels;
  final int topK;
  final Map<String, Object?> metadata;
}

final class EssentialLocationTaskPayload implements EssentialTaskPayload {
  const EssentialLocationTaskPayload({
    required this.prompt,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.nearbyPois = const <String>[],
  });

  final String prompt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final List<String> nearbyPois;
}

final class EssentialClassification {
  const EssentialClassification({
    required this.label,
    required this.index,
    required this.score,
  });

  final String label;
  final int index;
  final double score;
}

final class EssentialTaskResult {
  EssentialTaskResult({
    this.text,
    Float32List? tensorData,
    List<int> tensorShape = const <int>[],
    this.classifications = const <EssentialClassification>[],
    this.metadata = const <String, Object?>{},
  }) : tensorData = tensorData == null
           ? null
           : Float32List.fromList(tensorData),
       tensorShape = List<int>.unmodifiable(tensorShape);

  final String? text;
  final Float32List? tensorData;
  final List<int> tensorShape;
  final List<EssentialClassification> classifications;
  final Map<String, Object?> metadata;
}

final class EssentialTaskRequest {
  const EssentialTaskRequest({
    this.id,
    this.sessionId,
    required this.taskType,
    required this.payload,
    this.modelRequirement = const EssentialModelRequirement.anyCompatible(),
    this.stream = false,
    this.timeoutMs,
    this.realtimeHint = false,
    this.metadata = const <String, Object?>{},
  });

  final String? id;
  final String? sessionId;
  final EssentialTaskType taskType;
  final EssentialTaskPayload payload;
  final EssentialModelRequirement modelRequirement;
  final bool stream;
  final int? timeoutMs;
  final bool realtimeHint;
  final Map<String, Object?> metadata;

  EssentialTaskRequest copyWith({
    String? id,
    String? sessionId,
    EssentialTaskType? taskType,
    EssentialTaskPayload? payload,
    EssentialModelRequirement? modelRequirement,
    bool? stream,
    int? timeoutMs,
    bool? realtimeHint,
    Map<String, Object?>? metadata,
  }) {
    return EssentialTaskRequest(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      taskType: taskType ?? this.taskType,
      payload: payload ?? this.payload,
      modelRequirement: modelRequirement ?? this.modelRequirement,
      stream: stream ?? this.stream,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      realtimeHint: realtimeHint ?? this.realtimeHint,
      metadata: metadata ?? this.metadata,
    );
  }
}

final class EssentialTaskResponse {
  const EssentialTaskResponse({
    required this.requestId,
    required this.taskType,
    required this.status,
    required this.result,
    required this.runtimeFamily,
    required this.capabilityId,
    required this.modelUsed,
  });

  final String requestId;
  final EssentialTaskType taskType;
  final EssentialTaskStatus status;
  final EssentialTaskResult result;
  final EssentialRuntimeFamily runtimeFamily;
  final String capabilityId;
  final String modelUsed;
}

final class EssentialTaskEvent {
  const EssentialTaskEvent({
    required this.requestId,
    required this.taskType,
    required this.type,
    this.runtimeFamily,
    this.capabilityId,
    this.partialText,
    this.response,
    this.error,
  });

  final String requestId;
  final EssentialTaskType taskType;
  final EssentialTaskEventType type;
  final EssentialRuntimeFamily? runtimeFamily;
  final String? capabilityId;
  final String? partialText;
  final EssentialTaskResponse? response;
  final EssentialException? error;
}
