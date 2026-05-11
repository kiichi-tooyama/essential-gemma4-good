import 'dart:async';

import 'essential_capability_registry.dart';
import 'audio/essential_audio_runtime.dart';
import 'audio/essential_audio_types.dart';
import 'essential_runtime.dart';
import 'essential_task_types.dart';
import 'essential_types.dart';
import 'vision/essential_vision_runtime.dart';
import 'vision/essential_vision_types.dart';

final class EssentialTaskRoutingDecision {
  const EssentialTaskRoutingDecision({
    required this.capability,
    required this.runtimeFamily,
    required this.runtimeAvailable,
    required this.fallbackRuntimeFamilies,
  });

  final EssentialCapabilityDescriptor capability;
  final EssentialRuntimeFamily runtimeFamily;
  final bool runtimeAvailable;
  final List<EssentialRuntimeFamily> fallbackRuntimeFamilies;
}

final class EssentialTaskRouter {
  const EssentialTaskRouter();

  EssentialTaskRoutingDecision route({
    required EssentialTaskRequest request,
    required EssentialCapabilityRegistry registry,
    required Map<EssentialRuntimeFamily, EssentialRuntime> runtimes,
  }) {
    final candidates = registry.findByTaskType(request.taskType);
    if (candidates.isEmpty) {
      throw EssentialException(
        EssentialErrorCode.unsupportedTaskType,
        'Unsupported task type: ${request.taskType.wireName}',
      );
    }

    final ranked = [...candidates]
      ..sort(
        (left, right) =>
            _score(right, request).compareTo(_score(left, request)),
      );
    final available = ranked
        .where((candidate) {
          final runtime = runtimes[candidate.runtimeFamily];
          return runtime?.isAvailable ?? false;
        })
        .toList(growable: false);
    final selected = available.isNotEmpty ? available.first : ranked.first;
    final fallbackFamilies = ranked
        .map((descriptor) => descriptor.runtimeFamily)
        .where((family) => family != selected.runtimeFamily)
        .toSet()
        .toList(growable: false);
    final runtime = runtimes[selected.runtimeFamily];
    return EssentialTaskRoutingDecision(
      capability: selected,
      runtimeFamily: selected.runtimeFamily,
      runtimeAvailable: runtime?.isAvailable ?? false,
      fallbackRuntimeFamilies: fallbackFamilies,
    );
  }

  int _score(
    EssentialCapabilityDescriptor descriptor,
    EssentialTaskRequest request,
  ) {
    var score = 0;
    if (request.realtimeHint && descriptor.realtimeSupported) {
      score += 100;
    }
    if (!request.realtimeHint &&
        descriptor.runtimeFamily == EssentialRuntimeFamily.onnx) {
      score += 25;
    }
    if (!request.realtimeHint &&
        descriptor.runtimeFamily == EssentialRuntimeFamily.llamaCpp) {
      score += 25;
    }
    final requestedFamily = request.modelRequirement.family;
    if (requestedFamily != null &&
        descriptor.runtimeFamily.wireName == requestedFamily) {
      score += 150;
    }
    if (request.stream && descriptor.streamingSupported) {
      score += 50;
    }
    if (descriptor.runtimeFamily == EssentialRuntimeFamily.mediaPipe) {
      score += request.realtimeHint ? 40 : -20;
    }
    if (descriptor.runtimeFamily == EssentialRuntimeFamily.llamaCpp &&
        (request.taskType == EssentialTaskType.textGeneration ||
            request.taskType == EssentialTaskType.locationContext ||
            request.taskType == EssentialTaskType.mapReasoning ||
            request.taskType == EssentialTaskType.multimodalChat ||
            request.taskType == EssentialTaskType.imageCaption)) {
      score += 80;
    }
    if (descriptor.runtimeFamily == EssentialRuntimeFamily.onnx &&
        request.taskType != EssentialTaskType.textGeneration &&
        request.taskType != EssentialTaskType.locationContext &&
        request.taskType != EssentialTaskType.mapReasoning &&
        request.taskType != EssentialTaskType.multimodalChat &&
        request.taskType != EssentialTaskType.imageCaption) {
      score += 80;
    }
    return score;
  }

  Future<EssentialTaskResponse> routeVisionTask(ImageTaskRequest request) {
    throw const EssentialException(
      EssentialErrorCode.invalidConfiguration,
      'Use EssentialTaskRouterFacade.routeVisionTask so the router has runtime context.',
    );
  }

  Future<EssentialTaskResponse> routeAudioTask(AudioTaskRequest request) {
    throw const EssentialException(
      EssentialErrorCode.invalidConfiguration,
      'Use EssentialTaskRouterFacade.routeAudioTask so the router has runtime context.',
    );
  }

  Stream<EssentialTaskEvent> streamVisionTask(ImageTaskRequest request) {
    return Stream<EssentialTaskEvent>.error(
      const EssentialException(
        EssentialErrorCode.invalidConfiguration,
        'Use EssentialTaskRouterFacade.streamVisionTask so the router has runtime context.',
      ),
    );
  }
}

final class EssentialTaskRouterFacade {
  EssentialTaskRouterFacade({
    required this.capabilityRegistry,
    required EssentialTaskRouter router,
    required Map<EssentialRuntimeFamily, EssentialRuntime> runtimes,
  }) : _router = router,
       _runtimes = runtimes;

  final EssentialCapabilityRegistry capabilityRegistry;
  final EssentialTaskRouter _router;
  final Map<EssentialRuntimeFamily, EssentialRuntime> _runtimes;
  final Map<String, EssentialRuntimeFamily> _requestsByRuntime =
      <String, EssentialRuntimeFamily>{};

  Future<void> initialize() async {
    for (final runtime in _runtimes.values) {
      await runtime.initialize();
    }
  }

  List<EssentialCapabilityDescriptor> listCapabilities({
    EssentialTaskType? taskType,
  }) {
    if (taskType == null) {
      return capabilityRegistry.all();
    }
    return capabilityRegistry.findByTaskType(taskType);
  }

  EssentialTaskRoutingDecision route(EssentialTaskRequest request) {
    return _router.route(
      request: request,
      registry: capabilityRegistry,
      runtimes: _runtimes,
    );
  }

  Future<EssentialTaskResponse> runTask(EssentialTaskRequest request) async {
    final decision = route(request);
    final runtime = _requireRuntime(decision);
    final requestId = runtime.ensureRequestId(request);
    _requestsByRuntime[requestId] = runtime.family;
    try {
      return await runtime.execute(
        request.copyWith(id: requestId, stream: false),
        decision,
      );
    } finally {
      _requestsByRuntime.remove(requestId);
    }
  }

  Future<EssentialTaskResponse> routeVisionTask(ImageTaskRequest request) {
    final taskType = _mapImageTaskType(request.taskType);
    return runTask(
      EssentialTaskRequest(
        id: request.requestId,
        taskType: taskType,
        payload: EssentialImageTaskPayload(
          imageData: request.imageData,
          metadata: request.metadata,
          prompt: request.prompt,
          options:
              request.options?.cast<String, Object?>() ??
              const <String, Object?>{},
        ),
        modelRequirement: request.modelPath == null
            ? EssentialModelRequirement.anyCompatible(
                family: EssentialRuntimeFamily.onnx.wireName,
                capability: taskType.wireName,
              )
            : EssentialModelRequirement(
                family: EssentialRuntimeFamily.onnx.wireName,
                capability: taskType.wireName,
                explicitModelPath: request.modelPath,
              ),
      ),
    );
  }

  Future<EssentialTaskResponse> routeAudioTask(AudioTaskRequest request) {
    final taskType = _mapAudioTaskType(request.taskType);
    final payload = switch (request) {
      SttTaskRequest stt => EssentialAudioTaskPayload(
        samples: stt.samples,
        audioFilePath: stt.audioFilePath,
        sampleRate: stt.sampleRate,
        channels: stt.channels,
        format: stt.format,
      ),
      TtsTaskRequest tts => EssentialTtsTaskPayload(text: tts.text),
      _ => throw const EssentialException(
        EssentialErrorCode.unsupportedTaskType,
        'Unsupported audio task request.',
      ),
    };
    return runTask(
      EssentialTaskRequest(
        id: request.requestId,
        taskType: taskType,
        payload: payload,
        modelRequirement: request.modelPath == null
            ? EssentialModelRequirement.anyCompatible(
                family: EssentialRuntimeFamily.android.wireName,
                capability: taskType.wireName,
              )
            : EssentialModelRequirement(
                family: EssentialRuntimeFamily.android.wireName,
                capability: taskType.wireName,
                explicitModelPath: request.modelPath,
              ),
        metadata: switch (request) {
          SttTaskRequest stt => <String, Object?>{
            'language': stt.language,
            'translate': stt.translate,
          },
          TtsTaskRequest tts => <String, Object?>{
            'voice_id': tts.config.voiceId,
            'speed': tts.config.speed,
            'pitch': tts.config.pitch,
            'sample_rate': tts.config.sampleRate,
          },
          _ => const <String, Object?>{},
        },
      ),
    );
  }

  Stream<EssentialTaskEvent> streamVisionTask(ImageTaskRequest request) {
    final taskType = _mapImageTaskType(request.taskType);
    return streamTask(
      EssentialTaskRequest(
        id: request.requestId,
        taskType: taskType,
        payload: EssentialImageTaskPayload(
          imageData: request.imageData,
          metadata: request.metadata,
          prompt: request.prompt,
          options:
              request.options?.cast<String, Object?>() ??
              const <String, Object?>{},
        ),
        stream: true,
        modelRequirement: request.modelPath == null
            ? EssentialModelRequirement.anyCompatible(
                family: EssentialRuntimeFamily.onnx.wireName,
                capability: taskType.wireName,
              )
            : EssentialModelRequirement(
                family: EssentialRuntimeFamily.onnx.wireName,
                capability: taskType.wireName,
                explicitModelPath: request.modelPath,
              ),
      ),
    );
  }

  Stream<EssentialTaskEvent> streamTask(EssentialTaskRequest request) {
    final decision = route(request);
    final runtime = _requireRuntime(decision);
    final requestId = runtime.ensureRequestId(request);
    _requestsByRuntime[requestId] = runtime.family;
    final stream = runtime.stream(
      request.copyWith(id: requestId, stream: true),
      decision,
    );
    return stream.transform(
      StreamTransformer<EssentialTaskEvent, EssentialTaskEvent>.fromHandlers(
        handleData: (event, sink) {
          sink.add(event);
          if (event.type == EssentialTaskEventType.completed ||
              event.type == EssentialTaskEventType.failed ||
              event.type == EssentialTaskEventType.cancelled) {
            _requestsByRuntime.remove(requestId);
          }
        },
        handleError: (error, stackTrace, sink) {
          _requestsByRuntime.remove(requestId);
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          _requestsByRuntime.remove(requestId);
          sink.close();
        },
      ),
    );
  }

  Future<bool> cancel(String requestId) async {
    final family = _requestsByRuntime[requestId];
    if (family == null) {
      return false;
    }
    final runtime = _runtimes[family];
    if (runtime == null) {
      return false;
    }
    await runtime.cancel(requestId);
    return true;
  }

  Future<void> dispose() async {
    for (final runtime in _runtimes.values) {
      await runtime.dispose();
    }
    _requestsByRuntime.clear();
  }

  EssentialRuntime _requireRuntime(EssentialTaskRoutingDecision decision) {
    final runtime = _runtimes[decision.runtimeFamily];
    if (runtime == null || !runtime.isAvailable) {
      throw EssentialException(
        EssentialErrorCode.capabilityNotAvailable,
        'Capability ${decision.capability.capabilityId} is not available on this device.',
      );
    }
    return runtime;
  }

  EssentialTaskType _mapImageTaskType(ImageTaskType taskType) {
    return switch (taskType) {
      ImageTaskType.imageClassification =>
        EssentialTaskType.imageClassification,
      ImageTaskType.objectDetection => EssentialTaskType.objectDetection,
      ImageTaskType.imageSegmentation => EssentialTaskType.imageSegmentation,
      ImageTaskType.ocr => EssentialTaskType.ocr,
      ImageTaskType.imageCaption => EssentialTaskType.imageCaption,
      ImageTaskType.faceDetection => EssentialTaskType.faceDetection,
      ImageTaskType.multimodalChat => EssentialTaskType.multimodalChat,
    };
  }

  EssentialTaskType _mapAudioTaskType(EssentialAudioTaskType taskType) {
    return switch (taskType) {
      EssentialAudioTaskType.stt => EssentialTaskType.stt,
      EssentialAudioTaskType.tts => EssentialTaskType.tts,
      EssentialAudioTaskType.voiceCommand => EssentialTaskType.voiceCommand,
      EssentialAudioTaskType.classification =>
        EssentialTaskType.audioClassification,
    };
  }
}
