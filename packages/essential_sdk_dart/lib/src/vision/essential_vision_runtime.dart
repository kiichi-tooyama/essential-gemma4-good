import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import '../essential_runtime.dart';
import '../essential_task_router.dart';
import '../essential_task_types.dart';
import '../essential_types.dart';
import 'essential_vision_ffi.dart';
import 'essential_vision_types.dart';

final class EssentialVisionRuntime extends EssentialBaseRuntime {
  EssentialVisionRuntime({EssentialVisionFfi? ffi}) : _ffi = ffi;

  EssentialVisionFfi? _ffi;
  Pointer<Void>? _context;
  Pointer<Void>? _session;
  String? _modelPath;
  ImageTaskType? _sessionTaskType;
  bool _available = false;

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.onnx;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> initialize() async {
    try {
      _ffi ??= EssentialVisionFfi();
      _context = _ffi!.createContext();
      _available = _context != nullptr;
    } catch (_) {
      _available = false;
    }
  }

  Future<VisionResult> runImageTask(
    ImageTaskRequest request, {
    required String modelPath,
    bool useGpu = false,
  }) async {
    final session = _ensureSession(
      modelPath: modelPath,
      taskType: request.taskType,
      useGpu: useGpu,
      topK: request is ImageClassificationRequest ? request.topK : 5,
      confidenceThreshold: request is ObjectDetectionRequest
          ? request.confidenceThreshold ?? 0.25
          : request is ImageClassificationRequest
          ? request.confidenceThreshold ?? 0.0
          : 0.25,
    );
    final result = _ffi!.runInference(
      session: session,
      imageBytes: request.imageData,
      metadata: request.metadata,
      taskType: request.taskType,
      format: _imageFormatToNative(request.metadata.format),
    );
    return VisionResult(
      requestId: request.requestId,
      taskType: request.taskType,
      imageMetadata: request.metadata,
      classifications: result.classifications,
      detections: result.detections,
      textBlocks: result.textBlocks,
      captionText: result.captionText,
      latencyMs: result.latencyMs,
      modelBundleUsed: result.modelBundleUsed,
      error: result.error,
    );
  }

  int _imageFormatToNative(String? format) {
    return switch (format?.toLowerCase()) {
      'rgba' || 'rawrgba' || 'raw_rgba' => 1,
      'bgr' => 2,
      'gray' || 'grayscale' => 3,
      _ => 0,
    };
  }

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async {
    final payload = request.payload;
    if (payload is! EssentialImageTaskPayload) {
      throw const EssentialException(
        EssentialErrorCode.payloadSchemaInvalid,
        'Vision runtime requires EssentialImageTaskPayload.',
      );
    }
    final modelPath = request.modelRequirement.explicitModelPath;
    if (modelPath == null || modelPath.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'Vision task requires an explicit model path.',
      );
    }
    final imageRequest = payload.toImageTaskRequest(
      request.id!,
      request.taskType,
    );
    final vision = await runImageTask(
      imageRequest,
      modelPath: modelPath,
      useGpu: request.metadata['use_gpu'] as bool? ?? false,
    );
    return EssentialTaskResponse(
      requestId: request.id!,
      taskType: request.taskType,
      status: vision.error == null
          ? EssentialTaskStatus.completed
          : EssentialTaskStatus.failed,
      result: EssentialTaskResult(
        text: vision.captionText,
        classifications:
            vision.classifications
                ?.asMap()
                .entries
                .map(
                  (entry) => EssentialClassification(
                    label: entry.value.label,
                    index: int.tryParse(entry.value.labelId ?? '') ?? entry.key,
                    score: entry.value.confidence,
                  ),
                )
                .toList() ??
            const <EssentialClassification>[],
        metadata: <String, Object?>{
          'vision_result': vision.toJson(),
          'detections': vision.detections
              ?.map(
                (item) => <String, Object?>{
                  'label': item.label,
                  'label_id': item.labelId,
                  'confidence': item.confidence,
                  'box': item.box.toJson(),
                },
              )
              .toList(),
        },
      ),
      runtimeFamily: family,
      capabilityId: decision.capability.capabilityId,
      modelUsed: modelPath,
    );
  }

  @override
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async* {
    yield EssentialTaskEvent(
      requestId: request.id!,
      taskType: request.taskType,
      type: EssentialTaskEventType.started,
      runtimeFamily: family,
      capabilityId: decision.capability.capabilityId,
    );
    try {
      final response = await execute(request, decision);
      yield EssentialTaskEvent(
        requestId: request.id!,
        taskType: request.taskType,
        type: EssentialTaskEventType.completed,
        runtimeFamily: family,
        capabilityId: decision.capability.capabilityId,
        response: response,
      );
    } on EssentialException catch (error) {
      yield EssentialTaskEvent(
        requestId: request.id!,
        taskType: request.taskType,
        type: EssentialTaskEventType.failed,
        runtimeFamily: family,
        capabilityId: decision.capability.capabilityId,
        error: error,
      );
    }
  }

  @override
  Future<void> cancel(String requestId) async {}

  @override
  Future<void> dispose() async {
    final ffi = _ffi;
    if (ffi != null) {
      final session = _session;
      final context = _context;
      if (session != null) {
        ffi.destroySession(session);
      }
      if (context != null) {
        ffi.destroyContext(context);
      }
    }
    _session = null;
    _context = null;
    _available = false;
  }

  Pointer<Void> _ensureSession({
    required String modelPath,
    required ImageTaskType taskType,
    required bool useGpu,
    required int topK,
    required double confidenceThreshold,
  }) {
    final ffi = _ffi;
    final context = _context;
    if (ffi == null || context == null || context == nullptr) {
      throw const EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        'Vision runtime is not initialized.',
      );
    }
    if (_session != null &&
        _modelPath == modelPath &&
        _sessionTaskType == taskType) {
      return _session!;
    }
    if (_session != null) {
      ffi.destroySession(_session!);
    }
    _session = ffi.createSession(
      context: context,
      modelPath: modelPath,
      taskType: taskType,
      topK: topK,
      confidenceThreshold: confidenceThreshold,
      useGpu: useGpu,
    );
    if (_session == null || _session == nullptr) {
      throw const EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        'Vision runtime could not create a model session.',
      );
    }
    _modelPath = modelPath;
    _sessionTaskType = taskType;
    return _session!;
  }
}

final class EssentialImageTaskPayload implements EssentialTaskPayload {
  const EssentialImageTaskPayload({
    required this.imageData,
    required this.metadata,
    this.prompt,
    this.options = const <String, Object?>{},
  });

  final Uint8List imageData;
  final ImageMetadata metadata;
  final String? prompt;
  final Map<String, Object?> options;

  ImageTaskRequest toImageTaskRequest(
    String requestId,
    EssentialTaskType taskType,
  ) {
    return switch (taskType) {
      EssentialTaskType.imageClassification => ImageClassificationRequest(
        requestId: requestId,
        imageData: imageData,
        metadata: metadata,
        topK: options['top_k'] as int? ?? 5,
        confidenceThreshold: (options['confidence_threshold'] as num?)
            ?.toDouble(),
      ),
      EssentialTaskType.objectDetection => ObjectDetectionRequest(
        requestId: requestId,
        imageData: imageData,
        metadata: metadata,
        confidenceThreshold: (options['confidence_threshold'] as num?)
            ?.toDouble(),
        nmsThreshold: (options['nms_threshold'] as num?)?.toDouble(),
      ),
      EssentialTaskType.imageCaption => ImageCaptionRequest(
        requestId: requestId,
        imageData: imageData,
        metadata: metadata,
        prompt: prompt,
      ),
      EssentialTaskType.multimodalChat => MultimodalChatRequest(
        requestId: requestId,
        imageData: imageData,
        metadata: metadata,
        textPrompt: prompt ?? '',
      ),
      _ => ImageClassificationRequest(
        requestId: requestId,
        imageData: imageData,
        metadata: metadata,
      ),
    };
  }
}
