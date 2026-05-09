import 'dart:async';
import 'dart:io';

import 'essential_llama_runtime.dart';
import 'essential_runtime.dart';
import 'essential_task_router.dart';
import 'essential_task_types.dart';
import 'essential_types.dart';

final class EssentialLlamaTaskRuntime extends EssentialBaseRuntime {
  EssentialLlamaTaskRuntime(this._configuration);

  final EssentialConfiguration _configuration;
  EssentialLlamaRuntime? _runtime;
  String? _loadedModelPath;
  String? _activeRequestId;
  final Set<String> _timedOutRequests = <String>{};

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.llamaCpp;

  @override
  bool get isAvailable => true;

  @override
  Future<void> initialize() async {
    _runtime ??= await EssentialLlamaRuntime.create();
  }

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async {
    final stream = this.stream(request, decision);
    EssentialTaskResponse? response;
    await for (final event in stream) {
      if (event.type == EssentialTaskEventType.completed) {
        response = event.response;
      }
    }
    if (response != null) {
      return response;
    }
    throw const EssentialException(
      EssentialErrorCode.runtimeUnavailable,
      'The llama runtime did not return a response.',
    );
  }

  @override
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async* {
    final runtime = _requireRuntime();
    final prompt = _resolvePrompt(request);
    final resolvedModel = _resolveModel(request.modelRequirement);
    await _ensureLoadedModel(resolvedModel);

    Timer? timeoutTimer;
    try {
      if (_activeRequestId != null) {
        throw const EssentialException(
          EssentialErrorCode.deviceCapacityInsufficient,
          'Only one llama.cpp inference request can run at a time.',
        );
      }
      _activeRequestId = request.id;
      if (request.timeoutMs != null && request.timeoutMs! > 0) {
        timeoutTimer = Timer(Duration(milliseconds: request.timeoutMs!), () {
          _timedOutRequests.add(request.id!);
          unawaited(cancel(request.id!));
        });
      }

      yield EssentialTaskEvent(
        requestId: request.id!,
        taskType: request.taskType,
        type: EssentialTaskEventType.started,
        runtimeFamily: family,
        capabilityId: decision.capability.capabilityId,
      );

      final payload = request.payload as EssentialTextTaskPayload;
      final generation = runtime.generate(
        prompt,
        sessionId: request.sessionId,
        options: EssentialLlamaGenerationOptions(
          maxTokens: payload.maxTokens,
          topK: payload.topK,
          topP: payload.topP,
          temperature: payload.temperature,
          seed: payload.seed,
        ),
      );

      var accumulated = '';
      await for (final token in generation.stream) {
        accumulated += token;
        yield EssentialTaskEvent(
          requestId: request.id!,
          taskType: request.taskType,
          type: EssentialTaskEventType.partialResult,
          runtimeFamily: family,
          capabilityId: decision.capability.capabilityId,
          partialText: accumulated,
        );
      }

      final finalText = await generation.completed;
      yield EssentialTaskEvent(
        requestId: request.id!,
        taskType: request.taskType,
        type: EssentialTaskEventType.completed,
        runtimeFamily: family,
        capabilityId: decision.capability.capabilityId,
        response: EssentialTaskResponse(
          requestId: request.id!,
          taskType: request.taskType,
          status: EssentialTaskStatus.completed,
          result: EssentialTaskResult(
            text: finalText,
            metadata: <String, Object?>{
              'selected_runtime': family.wireName,
              'capability_id': decision.capability.capabilityId,
            },
          ),
          runtimeFamily: family,
          capabilityId: decision.capability.capabilityId,
          modelUsed: resolvedModel.modelId,
        ),
      );
    } catch (error) {
      final mapped = _mapError(error, request.id);
      yield EssentialTaskEvent(
        requestId: request.id!,
        taskType: request.taskType,
        type: mapped.code == EssentialErrorCode.sessionCancelled
            ? EssentialTaskEventType.cancelled
            : EssentialTaskEventType.failed,
        runtimeFamily: family,
        capabilityId: decision.capability.capabilityId,
        error: mapped,
      );
      throw mapped;
    } finally {
      timeoutTimer?.cancel();
      _timedOutRequests.remove(request.id);
      if (_activeRequestId == request.id) {
        _activeRequestId = null;
      }
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    if (_activeRequestId != requestId) {
      return;
    }
    await _requireRuntime().cancel();
  }

  @override
  Future<void> dispose() async {
    final runtime = _runtime;
    _runtime = null;
    _loadedModelPath = null;
    _activeRequestId = null;
    if (runtime != null) {
      await runtime.dispose();
    }
  }

  EssentialLlamaRuntime _requireRuntime() {
    final runtime = _runtime;
    if (runtime == null) {
      throw const EssentialException(
        EssentialErrorCode.invalidConfiguration,
        'Call initialize() before using the llama runtime.',
      );
    }
    return runtime;
  }

  String _resolvePrompt(EssentialTaskRequest request) {
    final payload = request.payload;
    if (payload is EssentialTextTaskPayload) {
      return payload.prompt;
    }
    if (payload is EssentialLocationTaskPayload) {
      final nearbyPois = payload.nearbyPois.isEmpty
          ? ''
          : ' Nearby POIs: ${payload.nearbyPois.join(', ')}.';
      final accuracy = payload.accuracyMeters == null
          ? ''
          : ' Accuracy: ${payload.accuracyMeters}m.';
      return '${payload.prompt}\n'
          'Location: ${payload.latitude}, ${payload.longitude}.$accuracy$nearbyPois';
    }
    throw const EssentialException(
      EssentialErrorCode.payloadSchemaInvalid,
      'llama.cpp runtime requires text or location payload.',
    );
  }

  Future<void> _ensureLoadedModel(EssentialInstalledModel model) async {
    if (_loadedModelPath == model.modelPath) {
      return;
    }
    await _requireRuntime().loadModel(
      model.modelPath,
      options: _configuration.modelLoadOptions,
    );
    _loadedModelPath = model.modelPath;
  }

  List<EssentialInstalledModel> _listModels() {
    return _configuration.installedModels
        .where((model) => File(model.modelPath).existsSync())
        .toList(growable: false);
  }

  EssentialInstalledModel _resolveModel(EssentialModelRequirement requirement) {
    final explicitPath = requirement.explicitModelPath;
    if (explicitPath != null) {
      final file = File(explicitPath);
      if (!file.existsSync()) {
        throw EssentialException(
          EssentialErrorCode.modelNotInstalled,
          'Model path not found: $explicitPath',
        );
      }
      return EssentialInstalledModel(
        modelId:
            requirement.modelId ?? file.uri.pathSegments.last.split('.').first,
        modelPath: explicitPath,
        family: requirement.family,
        capabilities: requirement.capability == null
            ? const <String>[]
            : <String>[requirement.capability!],
        contextWindow: requirement.minContextWindow,
      );
    }

    final installed = _listModels();
    if (installed.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'No installed model matched the request.',
      );
    }

    bool matchesMetadata(EssentialInstalledModel model) {
      if (requirement.family != null && model.family != requirement.family) {
        return false;
      }
      if (requirement.capability != null &&
          !model.capabilities.contains(requirement.capability)) {
        return false;
      }
      return true;
    }

    bool isCompatible(EssentialInstalledModel model) {
      final minimumContext = requirement.minContextWindow;
      if (minimumContext != null &&
          model.contextWindow != null &&
          model.contextWindow! < minimumContext) {
        return false;
      }
      return true;
    }

    final metadataMatches = installed
        .where(matchesMetadata)
        .toList(growable: false);
    if (metadataMatches.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'No installed model matched the request.',
      );
    }

    final compatibleMatches = metadataMatches
        .where(isCompatible)
        .toList(growable: false);

    if (requirement.modelId != null) {
      final exactInstalled = metadataMatches
          .where((model) => model.modelId == requirement.modelId)
          .toList(growable: false);
      if (exactInstalled.isNotEmpty) {
        final exactCompatible = exactInstalled.firstWhere(
          isCompatible,
          orElse: () =>
              const EssentialInstalledModel(modelId: '', modelPath: ''),
        );
        if (exactCompatible.modelId.isNotEmpty) {
          return exactCompatible;
        }
        if (!requirement.allowFallback) {
          throw const EssentialException(
            EssentialErrorCode.modelIncompatible,
            'The requested model does not satisfy the runtime requirements.',
          );
        }
      } else if (!requirement.allowFallback) {
        throw EssentialException(
          EssentialErrorCode.modelNotInstalled,
          'Requested model is unavailable: ${requirement.modelId}',
        );
      }
    }

    if (compatibleMatches.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelIncompatible,
        'No installed model satisfies the compatibility requirements.',
      );
    }

    final defaultModelId = _configuration.defaultModelId;
    if (defaultModelId != null) {
      final preferred = compatibleMatches.where(
        (model) => model.modelId == defaultModelId,
      );
      if (preferred.isNotEmpty) {
        return preferred.first;
      }
    }

    return compatibleMatches.first;
  }

  EssentialException _mapError(Object error, String? requestId) {
    if (requestId != null && _timedOutRequests.contains(requestId)) {
      return const EssentialException(
        EssentialErrorCode.requestTimedOut,
        'The inference request timed out.',
      );
    }
    if (error is EssentialException) {
      return error;
    }
    final message = error.toString();
    final normalized = message.toLowerCase();
    if (normalized.contains('cancel')) {
      return EssentialException(
        EssentialErrorCode.sessionCancelled,
        'The inference request was cancelled.',
        cause: error,
      );
    }
    if (normalized.contains('model is not loaded')) {
      return EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        'The inference runtime is not ready.',
        cause: error,
      );
    }
    if (normalized.contains('adapter')) {
      return EssentialException(
        EssentialErrorCode.adapterIncompatible,
        message,
        cause: error,
      );
    }
    if (normalized.contains('model path') ||
        normalized.contains('no such file')) {
      return EssentialException(
        EssentialErrorCode.modelNotInstalled,
        message,
        cause: error,
      );
    }
    return EssentialException(
      EssentialErrorCode.runtimeUnavailable,
      message,
      cause: error,
    );
  }
}
