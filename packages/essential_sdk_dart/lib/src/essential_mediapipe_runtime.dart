import 'dart:async';

import 'essential_runtime.dart';
import 'essential_task_router.dart';
import 'essential_task_types.dart';

final class EssentialMediaPipeRuntime extends EssentialBaseRuntime {
  EssentialMediaPipeRuntime({this.available = true});

  final bool available;

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.mediaPipe;

  @override
  bool get isAvailable => available;

  @override
  Future<void> initialize() async {}

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async {
    final payload = request.payload;
    final metadata = <String, Object?>{
      'prepared': true,
      'runtime': family.wireName,
      'preprocessing_profile': decision.capability.preprocessingProfile,
      'postprocessing_profile': decision.capability.postprocessingProfile,
    };
    if (payload is EssentialTensorTaskPayload) {
      return EssentialTaskResponse(
        requestId: request.id!,
        taskType: request.taskType,
        status: EssentialTaskStatus.completed,
        result: EssentialTaskResult(
          tensorData: payload.data,
          tensorShape: payload.shape,
          metadata: metadata,
        ),
        runtimeFamily: family,
        capabilityId: decision.capability.capabilityId,
        modelUsed: request.modelRequirement.modelId ?? 'mediapipe-prep',
      );
    }
    return EssentialTaskResponse(
      requestId: request.id!,
      taskType: request.taskType,
      status: EssentialTaskStatus.completed,
      result: EssentialTaskResult(metadata: metadata),
      runtimeFamily: family,
      capabilityId: decision.capability.capabilityId,
      modelUsed: request.modelRequirement.modelId ?? 'mediapipe-prep',
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
    yield EssentialTaskEvent(
      requestId: request.id!,
      taskType: request.taskType,
      type: EssentialTaskEventType.completed,
      runtimeFamily: family,
      capabilityId: decision.capability.capabilityId,
      response: await execute(request, decision),
    );
  }

  @override
  Future<void> cancel(String requestId) async {}

  @override
  Future<void> dispose() async {}
}
