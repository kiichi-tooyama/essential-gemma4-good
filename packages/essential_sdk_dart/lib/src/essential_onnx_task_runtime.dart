import 'dart:async';

import 'audio/essential_audio_runtime.dart';
import 'essential_runtime.dart';
import 'essential_task_router.dart';
import 'essential_task_types.dart';
import 'essential_types.dart';
import 'vision/essential_vision_runtime.dart';

final class EssentialOnnxTaskRuntime extends EssentialBaseRuntime {
  EssentialOnnxTaskRuntime({
    EssentialVisionRuntime? visionRuntime,
    EssentialAudioRuntime? audioRuntime,
  }) : _visionRuntime = visionRuntime ?? EssentialVisionRuntime(),
       _audioRuntime = audioRuntime ?? EssentialAudioRuntime();

  final EssentialVisionRuntime _visionRuntime;
  final EssentialAudioRuntime _audioRuntime;

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.onnx;

  @override
  bool get isAvailable =>
      _visionRuntime.isAvailable || _audioRuntime.isAvailable;

  @override
  Future<void> initialize() async {
    await Future.wait(<Future<void>>[
      _visionRuntime.initialize(),
      _audioRuntime.initialize(),
    ]);
  }

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) {
    return _selectRuntime(request).execute(request, decision);
  }

  @override
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) {
    return _selectRuntime(request).stream(request, decision);
  }

  @override
  Future<void> cancel(String requestId) async {
    await Future.wait(<Future<void>>[
      _visionRuntime.cancel(requestId),
      _audioRuntime.cancel(requestId),
    ]);
  }

  @override
  Future<void> dispose() async {
    await Future.wait(<Future<void>>[
      _visionRuntime.dispose(),
      _audioRuntime.dispose(),
    ]);
  }

  EssentialRuntime _selectRuntime(EssentialTaskRequest request) {
    switch (request.taskType) {
      case EssentialTaskType.imageClassification:
      case EssentialTaskType.objectDetection:
        return _requireAvailable(_visionRuntime, 'Vision');
      case EssentialTaskType.stt:
      case EssentialTaskType.tts:
        return _requireAvailable(_audioRuntime, 'Audio');
      case EssentialTaskType.imageCaption:
      case EssentialTaskType.multimodalChat:
      case EssentialTaskType.imageSegmentation:
      case EssentialTaskType.ocr:
      case EssentialTaskType.faceDetection:
      case EssentialTaskType.voiceCommand:
      case EssentialTaskType.audioClassification:
      case EssentialTaskType.speakerRecognition:
      case EssentialTaskType.textGeneration:
      case EssentialTaskType.locationContext:
      case EssentialTaskType.mapReasoning:
        throw EssentialException(
          EssentialErrorCode.unsupportedTaskType,
          'ONNX runtime does not support ${request.taskType.wireName} in this build.',
        );
    }
  }

  EssentialRuntime _requireAvailable(EssentialRuntime runtime, String label) {
    if (!runtime.isAvailable) {
      throw EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        '$label runtime is unavailable in this build.',
      );
    }
    return runtime;
  }
}
