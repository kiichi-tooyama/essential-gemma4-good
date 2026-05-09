import 'dart:async';
import 'dart:io';

import 'essential_capability_registry.dart';
import 'essential_genai_runtime.dart';
import 'essential_llama_runtime.dart' show EssentialAdapterAttachmentOptions;
import 'essential_onnx_task_runtime.dart';
import 'essential_runtime.dart';
import 'essential_task_router.dart';
import 'essential_task_types.dart';
import 'essential_types.dart';

class EssentialClient {
  EssentialClient(this.configuration)
    : _routerFacade = EssentialTaskRouterFacade(
        capabilityRegistry: EssentialCapabilityRegistry.defaultRegistry(),
        router: const EssentialTaskRouter(),
        runtimes: _buildRuntimes(configuration),
      );

  final EssentialConfiguration configuration;
  final EssentialTaskRouterFacade _routerFacade;
  EssentialGenAiRuntime? _runtime;
  String? _activeRequestId;
  final Set<String> _timedOutRequests = <String>{};
  int _requestCounter = 0;

  bool get isInitialized => _runtime != null;

  static Future<EssentialClient> initialize(
    EssentialConfiguration configuration,
  ) async {
    final client = EssentialClient(configuration);
    await client.initializeRuntime();
    return client;
  }

  Future<void> initializeRuntime() async {
    _runtime ??= EssentialGenAiRuntime();
    await _routerFacade.initialize();
  }

  List<EssentialInstalledModel> listModels() {
    return configuration.installedModels
        .where((model) => model.isInstalled)
        .toList(growable: false);
  }

  EssentialInstalledModel ensureModelInstalled(
    EssentialModelRequirement requirement,
  ) {
    return _resolveModel(requirement);
  }

  Future<void> attachAdapter({
    required String sessionId,
    required String adapterPath,
    EssentialAdapterAttachmentOptions options =
        const EssentialAdapterAttachmentOptions(),
  }) async {
    throw const EssentialException(
      EssentialErrorCode.adapterIncompatible,
      'Adapters are not supported by the LiteRT-LM SDK generation path.',
    );
  }

  Future<void> detachAdapter(String sessionId) async {
    throw const EssentialException(
      EssentialErrorCode.adapterIncompatible,
      'Adapters are not supported by the LiteRT-LM SDK generation path.',
    );
  }

  Future<bool> cancel(String requestId) async {
    if (_activeRequestId != requestId) {
      return false;
    }
    final runtime = _requireRuntime();
    await runtime.cancel();
    return true;
  }

  Stream<EssentialGenerateChunk> generateStream(
    EssentialGenerateRequest request,
  ) {
    final requestId = request.id ?? _nextRequestId();
    final controller = StreamController<EssentialGenerateChunk>();
    unawaited(
      _runStream(
        _applyRuntimePreferredModel(request).copyWith(id: requestId),
        controller,
      ),
    );
    controller.onCancel = () async {
      await cancel(requestId);
    };
    return controller.stream;
  }

  Future<EssentialGenerateResult> generate(
    EssentialGenerateRequest request,
  ) async {
    final requestId = request.id ?? _nextRequestId();
    final effectiveRequest = _applyRuntimePreferredModel(request);
    final resolvedModel = _resolveModel(effectiveRequest.modelRequirement);
    var finalText = '';
    await for (final chunk in generateStream(
      effectiveRequest.copyWith(id: requestId),
    )) {
      finalText = chunk.accumulatedText;
    }
    return EssentialGenerateResult(
      requestId: requestId,
      text: finalText,
      modelUsed: resolvedModel.modelId,
      finishReason: 'completed',
    );
  }

  List<EssentialCapabilityDescriptor> listCapabilities({
    EssentialTaskType? taskType,
  }) {
    return _routerFacade.listCapabilities(taskType: taskType);
  }

  EssentialTaskRoutingDecision routeTask(EssentialTaskRequest request) {
    return _routerFacade.route(request);
  }

  Future<EssentialTaskResponse> runTask(EssentialTaskRequest request) async {
    return _routerFacade.runTask(request);
  }

  Stream<EssentialTaskEvent> streamTask(EssentialTaskRequest request) {
    return _routerFacade.streamTask(request);
  }

  Future<void> dispose() async {
    final runtime = _runtime;
    _runtime = null;
    _activeRequestId = null;
    if (runtime != null) {
      await runtime.releaseIdle();
    }
    await _routerFacade.dispose();
  }

  Future<void> _runStream(
    EssentialGenerateRequest request,
    StreamController<EssentialGenerateChunk> controller,
  ) async {
    Timer? timeoutTimer;
    try {
      if (_activeRequestId != null) {
        throw const EssentialException(
          EssentialErrorCode.deviceCapacityInsufficient,
          'Only one inference request can run at a time.',
        );
      }
      final runtime = _requireRuntime();
      final resolvedModel = _resolveModel(request.modelRequirement);
      _activeRequestId = request.id;
      if (request.timeoutMs != null && request.timeoutMs! > 0) {
        timeoutTimer = Timer(Duration(milliseconds: request.timeoutMs!), () {
          _timedOutRequests.add(request.id!);
          unawaited(cancel(request.id!));
        });
      }
      var accumulated = '';
      final assembledPrompt = _assemblePrompt(request);
      final result = await runtime.generate(
        requestId: request.id,
        modelPath: resolvedModel.modelPath,
        prompt: assembledPrompt,
        imagePaths: _attachmentPaths(request, EssentialInputKind.image),
        audioPaths: _attachmentPaths(request, EssentialInputKind.audio),
        maxTokens: request.maxTokens.clamp(64, 1536).toInt(),
        contextTokens: (resolvedModel.contextWindow ?? 4000)
            .clamp(512, 4000)
            .toInt(),
        topK: request.topK,
        topP: request.topP,
        temperature: request.temperature,
        accelerator: 'auto',
        systemInstruction: request.systemInstruction,
        onToken: (token) {
          accumulated += token;
          controller.add(
            EssentialGenerateChunk(
              requestId: request.id!,
              delta: token,
              accumulatedText: accumulated,
              modelUsed: resolvedModel.modelId,
            ),
          );
        },
      );
      if (result.text != accumulated) {
        controller.add(
          EssentialGenerateChunk(
            requestId: request.id!,
            delta: '',
            accumulatedText: result.text,
            modelUsed: resolvedModel.modelId,
          ),
        );
      }
      await controller.close();
    } catch (error) {
      controller.addError(_mapError(error, request.id));
      await controller.close();
    } finally {
      timeoutTimer?.cancel();
      _timedOutRequests.remove(request.id);
      if (_activeRequestId == request.id) {
        _activeRequestId = null;
      }
    }
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
      if (!explicitPath.toLowerCase().endsWith('.litertlm')) {
        throw const EssentialException(
          EssentialErrorCode.modelIncompatible,
          'Essential SDK generation only supports LiteRT-LM .litertlm models.',
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

    final installed = listModels();
    if (installed.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'No installed model matched the request.',
      );
    }

    bool matchesMetadata(EssentialInstalledModel model) {
      if (!model.modelPath.toLowerCase().endsWith('.litertlm')) {
        return false;
      }
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

    final defaultModelId = configuration.defaultModelId;
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

  EssentialGenerateRequest _applyRuntimePreferredModel(
    EssentialGenerateRequest request,
  ) {
    final preferredModelId = request.runtimeOptions.preferredModelId?.trim();
    if (preferredModelId == null || preferredModelId.isEmpty) {
      return request;
    }
    if (request.modelRequirement.modelId == preferredModelId) {
      return request;
    }
    return request.copyWith(
      modelRequirement: request.modelRequirement.copyWith(
        modelId: preferredModelId,
        allowFallback: true,
      ),
    );
  }

  String _assemblePrompt(EssentialGenerateRequest request) {
    final buffer = StringBuffer();
    if (request.referenceDocuments.isNotEmpty) {
      buffer.writeln('# Reference Documents');
      for (final document in request.referenceDocuments) {
        buffer.writeln('## ${document.title}');
        if (document.uri != null) {
          buffer.writeln('URL: ${document.uri}');
        }
        if (document.filePath != null) {
          buffer.writeln('File: ${document.filePath}');
        }
        if (document.text.trim().isNotEmpty) {
          buffer.writeln(document.text.trim());
        }
        buffer.writeln();
      }
    }
    if (request.runtimeOptions.preferredModelId?.trim().isNotEmpty ?? false) {
      buffer.writeln('# Runtime Preferences');
      buffer.writeln(
        'Preferred model: ${request.runtimeOptions.preferredModelId!.trim()}',
      );
      buffer.writeln(
        'Web search: ${request.runtimeOptions.webSearchEnabled ? 'enabled' : 'disabled'}',
      );
      buffer.writeln(
        'Location context: ${request.runtimeOptions.locationEnabled ? 'enabled' : 'disabled'}',
      );
      buffer.writeln(
        'Shared memory: ${request.runtimeOptions.sharedMemoryEnabled ? 'enabled' : 'disabled'}',
      );
      buffer.writeln(
        'Shared memory read: ${request.runtimeOptions.sharedMemoryReadEnabled ? 'enabled' : 'disabled'}',
      );
      buffer.writeln(
        'Shared memory write: ${request.runtimeOptions.sharedMemoryWriteEnabled ? 'enabled' : 'disabled'}',
      );
      buffer.writeln(
        'Spoken output: ${request.runtimeOptions.spokenOutputEnabled ? 'enabled' : 'disabled'}',
      );
      buffer.writeln();
    }
    final textAttachments = request.attachments.where(
      (attachment) =>
          attachment.kind == EssentialInputKind.text ||
          attachment.kind == EssentialInputKind.url ||
          attachment.kind == EssentialInputKind.document ||
          attachment.kind == EssentialInputKind.reference,
    );
    if (textAttachments.isNotEmpty) {
      buffer.writeln('# Input Attachments');
      for (final attachment in textAttachments) {
        final name = attachment.name ?? attachment.kind.name;
        buffer.writeln('## $name');
        if (attachment.uri != null) {
          buffer.writeln('URI: ${attachment.uri}');
        }
        if (attachment.filePath != null) {
          buffer.writeln('File: ${attachment.filePath}');
        }
        if (attachment.text?.trim().isNotEmpty ?? false) {
          buffer.writeln(attachment.text!.trim());
        }
        buffer.writeln();
      }
    }
    if (request.attachments.any(
      (attachment) =>
          attachment.kind == EssentialInputKind.image ||
          attachment.kind == EssentialInputKind.audio,
    )) {
      buffer.writeln('# Media Attachments');
      for (final attachment in request.attachments) {
        if (attachment.kind != EssentialInputKind.image &&
            attachment.kind != EssentialInputKind.audio) {
          continue;
        }
        buffer.writeln(
          '- ${attachment.kind.name}: ${attachment.name ?? attachment.filePath ?? attachment.uri ?? 'inline'}',
        );
      }
      buffer.writeln();
    }
    buffer.writeln('# User Prompt');
    buffer.writeln(request.prompt);
    return buffer.toString().trim();
  }

  List<String> _attachmentPaths(
    EssentialGenerateRequest request,
    EssentialInputKind kind,
  ) {
    return request.attachments
        .where((attachment) => attachment.kind == kind)
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
  }

  EssentialGenAiRuntime _requireRuntime() {
    final runtime = _runtime;
    if (runtime == null) {
      throw const EssentialException(
        EssentialErrorCode.invalidConfiguration,
        'Call initializeRuntime() before using EssentialClient.',
      );
    }
    return runtime;
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

  static Map<EssentialRuntimeFamily, EssentialRuntime> _buildRuntimes(
    EssentialConfiguration configuration,
  ) {
    return <EssentialRuntimeFamily, EssentialRuntime>{
      EssentialRuntimeFamily.onnx: EssentialOnnxTaskRuntime(),
      EssentialRuntimeFamily.tflite: EssentialUnavailableRuntime(
        EssentialRuntimeFamily.tflite,
      ),
      EssentialRuntimeFamily.llamaCpp: EssentialUnavailableRuntime(
        EssentialRuntimeFamily.llamaCpp,
      ),
      EssentialRuntimeFamily.mediaPipe: EssentialUnavailableRuntime(
        EssentialRuntimeFamily.mediaPipe,
      ),
      EssentialRuntimeFamily.android: EssentialUnavailableRuntime(
        EssentialRuntimeFamily.android,
      ),
    };
  }

  String _nextRequestId() {
    _requestCounter += 1;
    return 'essential-request-$_requestCounter';
  }
}
