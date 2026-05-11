import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'essential_runtime.dart';
import 'essential_task_router.dart';
import 'essential_task_types.dart';
import 'essential_types.dart';

final class EssentialOnnxRuntime extends EssentialBaseRuntime {
  EssentialOnnxRuntime._(this._commandPort, this._responses, this._available);

  static Future<EssentialOnnxRuntime> create() async {
    final receivePort = ReceivePort();
    final commandPortCompleter = Completer<SendPort>();
    await Isolate.spawn(_onnxIsolateMain, receivePort.sendPort);
    late final EssentialOnnxRuntime runtime;
    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!commandPortCompleter.isCompleted) {
          commandPortCompleter.complete(message);
        }
        return;
      }
      runtime._handleResponse(message);
    });
    final commandPort = await commandPortCompleter.future;
    final availabilityCompleter = Completer<bool>();
    runtime = EssentialOnnxRuntime._(
      commandPort,
      receivePort,
      availabilityCompleter,
    );
    runtime._commandPort.send(const <String, Object?>{'type': 'probe'});
    final available = await availabilityCompleter.future;
    runtime._availableValue = available;
    return runtime;
  }

  final SendPort _commandPort;
  final ReceivePort _responses;
  final Completer<bool> _available;
  bool _availableValue = false;
  int _nextRequestId = 1;
  final Map<int, Completer<void>> _pendingLoads = <int, Completer<void>>{};
  final Map<int, _OnnxPendingExecution> _pendingExecutions =
      <int, _OnnxPendingExecution>{};
  Completer<void>? _disposeCompleter;
  String? _loadedModelPath;

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.onnx;

  @override
  bool get isAvailable => _availableValue;

  Future<void> loadModel(String modelPath) {
    if (_loadedModelPath == modelPath) {
      return Future<void>.value();
    }
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingLoads[requestId] = completer;
    _commandPort.send(<String, Object?>{
      'type': 'load',
      'requestId': requestId,
      'modelPath': modelPath,
    });
    return completer.future.then((_) {
      _loadedModelPath = modelPath;
    });
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async {
    final payload = request.payload;
    if (payload is! EssentialTensorTaskPayload) {
      throw const EssentialException(
        EssentialErrorCode.payloadSchemaInvalid,
        'ONNX runtime requires EssentialTensorTaskPayload.',
      );
    }
    final modelPath = request.modelRequirement.explicitModelPath;
    if (modelPath == null || modelPath.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'ONNX task requires an explicit model path.',
      );
    }
    await loadModel(modelPath);
    final nativeRequestId = _nextRequestId++;
    final completer = Completer<EssentialTaskResponse>();
    _pendingExecutions[nativeRequestId] = _OnnxPendingExecution(
      request: request,
      decision: decision,
      completer: completer,
    );
    _commandPort.send(<String, Object?>{
      'type': 'run',
      'requestId': nativeRequestId,
      'taskType': request.taskType.wireName,
      'shape': payload.shape,
      'data': payload.data,
      'labels': payload.labels,
      'topK': payload.topK,
      'metadata': payload.metadata,
    });
    return completer.future;
  }

  @override
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async* {
    final response = await execute(request, decision);
    yield EssentialTaskEvent(
      requestId: response.requestId,
      taskType: response.taskType,
      type: EssentialTaskEventType.started,
      runtimeFamily: response.runtimeFamily,
      capabilityId: response.capabilityId,
    );
    yield EssentialTaskEvent(
      requestId: response.requestId,
      taskType: response.taskType,
      type: EssentialTaskEventType.completed,
      runtimeFamily: response.runtimeFamily,
      capabilityId: response.capabilityId,
      response: response,
    );
  }

  @override
  Future<void> cancel(String requestId) async {
    _commandPort.send(<String, Object?>{
      'type': 'cancel',
      'requestId': requestId,
    });
  }

  @override
  Future<void> dispose() {
    final completer = Completer<void>();
    _disposeCompleter = completer;
    _commandPort.send(const <String, Object?>{'type': 'dispose'});
    return completer.future;
  }

  void _handleResponse(dynamic message) {
    if (message is! Map<Object?, Object?>) {
      return;
    }
    final type = message['type'];
    if (type == 'probe_result') {
      if (!_available.isCompleted) {
        _available.complete(message['available']! as bool);
      }
      return;
    }
    if (type == 'load_ok') {
      final requestId = message['requestId']! as int;
      _pendingLoads.remove(requestId)?.complete();
      return;
    }
    if (type == 'load_error') {
      final requestId = message['requestId']! as int;
      _pendingLoads
          .remove(requestId)
          ?.completeError(
            EssentialException(
              EssentialErrorCode.runtimeUnavailable,
              message['message']! as String,
            ),
          );
      return;
    }
    if (type == 'run_ok') {
      final requestId = message['requestId']! as int;
      final pending = _pendingExecutions.remove(requestId);
      if (pending == null) {
        return;
      }
      final output = (message['output']! as Uint8List).buffer.asFloat32List();
      final shape = (message['shape']! as List<Object?>).cast<int>();
      final labels =
          ((message['labels'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>();
      final classifications = _buildClassifications(
        output,
        labels,
        pending.request.payload as EssentialTensorTaskPayload,
      );
      pending.completer.complete(
        EssentialTaskResponse(
          requestId: pending.request.id!,
          taskType: pending.request.taskType,
          status: EssentialTaskStatus.completed,
          result: EssentialTaskResult(
            tensorData: output,
            tensorShape: shape,
            classifications: classifications,
            metadata: <String, Object?>{
              'labels': labels,
              'selected_runtime': pending.decision.runtimeFamily.wireName,
            },
          ),
          runtimeFamily: pending.decision.runtimeFamily,
          capabilityId: pending.decision.capability.capabilityId,
          modelUsed:
              pending.request.modelRequirement.modelId ??
              pending.request.modelRequirement.explicitModelPath ??
              'onnx-model',
        ),
      );
      return;
    }
    if (type == 'run_error') {
      final requestId = message['requestId']! as int;
      final pending = _pendingExecutions.remove(requestId);
      pending?.completer.completeError(
        EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          message['message']! as String,
        ),
      );
      return;
    }
    if (type == 'disposed') {
      _disposeCompleter?.complete();
      _disposeCompleter = null;
      _responses.close();
    }
  }

  List<EssentialClassification> _buildClassifications(
    Float32List output,
    List<String> labels,
    EssentialTensorTaskPayload payload,
  ) {
    final scores = <_IndexedScore>[];
    for (var index = 0; index < output.length; index += 1) {
      scores.add(_IndexedScore(index: index, score: output[index]));
    }
    scores.sort((left, right) => right.score.compareTo(left.score));
    final limit = payload.topK.clamp(1, scores.length);
    return scores
        .take(limit)
        .map((entry) {
          final label = entry.index < labels.length
              ? labels[entry.index]
              : 'label_${entry.index}';
          return EssentialClassification(
            label: label,
            index: entry.index,
            score: entry.score,
          );
        })
        .toList(growable: false);
  }
}

final class _IndexedScore {
  const _IndexedScore({required this.index, required this.score});

  final int index;
  final double score;
}

final class _OnnxPendingExecution {
  const _OnnxPendingExecution({
    required this.request,
    required this.decision,
    required this.completer,
  });

  final EssentialTaskRequest request;
  final EssentialTaskRoutingDecision decision;
  final Completer<EssentialTaskResponse> completer;
}

final class _NativeOnnxBindings {
  _NativeOnnxBindings(DynamicLibrary library)
    : isAvailable = library
          .lookupFunction<_NativeOnnxIsAvailableC, _NativeOnnxIsAvailableDart>(
            'essential_onnx_runtime_is_available',
          ),
      createEngine = library
          .lookupFunction<
            _NativeOnnxCreateEngineC,
            _NativeOnnxCreateEngineDart
          >('essential_onnx_engine_create'),
      destroyEngine = library
          .lookupFunction<
            _NativeOnnxDestroyEngineC,
            _NativeOnnxDestroyEngineDart
          >('essential_onnx_engine_destroy'),
      run = library.lookupFunction<_NativeOnnxRunC, _NativeOnnxRunDart>(
        'essential_onnx_engine_run',
      ),
      stringFree = library
          .lookupFunction<_NativeOnnxStringFreeC, _NativeOnnxStringFreeDart>(
            'essential_onnx_string_free',
          ),
      lastError = library
          .lookupFunction<_NativeOnnxLastErrorC, _NativeOnnxLastErrorDart>(
            'essential_onnx_last_error_message',
          );

  final _NativeOnnxIsAvailableDart isAvailable;
  final _NativeOnnxCreateEngineDart createEngine;
  final _NativeOnnxDestroyEngineDart destroyEngine;
  final _NativeOnnxRunDart run;
  final _NativeOnnxStringFreeDart stringFree;
  final _NativeOnnxLastErrorDart lastError;
}

DynamicLibrary _loadOnnxLibrary() {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open(
      'essential_sdk_dart.framework/essential_sdk_dart',
    );
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libessential_sdk_dart.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('essential_sdk_dart.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

Future<void> _onnxIsolateMain(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  final bindings = _NativeOnnxBindings(_loadOnnxLibrary());
  Pointer<Void> engine = nullptr;

  await for (final dynamic message in receivePort) {
    if (message is! Map<Object?, Object?>) {
      continue;
    }
    final type = message['type'];
    if (type == 'probe') {
      sendPort.send(<String, Object?>{
        'type': 'probe_result',
        'available': bindings.isAvailable() != 0,
      });
      continue;
    }
    if (type == 'load') {
      final requestId = message['requestId']! as int;
      if (engine != nullptr) {
        bindings.destroyEngine(engine);
        engine = nullptr;
      }
      final modelPathPointer = (message['modelPath']! as String).toNativeUtf8();
      final created = bindings.createEngine(modelPathPointer);
      calloc.free(modelPathPointer);
      if (created.address == 0) {
        sendPort.send(<String, Object?>{
          'type': 'load_error',
          'requestId': requestId,
          'message': bindings.lastError().toDartString(),
        });
        continue;
      }
      engine = created;
      sendPort.send(<String, Object?>{
        'type': 'load_ok',
        'requestId': requestId,
      });
      continue;
    }
    if (type == 'run') {
      final requestId = message['requestId']! as int;
      if (engine == nullptr) {
        sendPort.send(<String, Object?>{
          'type': 'run_error',
          'requestId': requestId,
          'message': 'ONNX model is not loaded.',
        });
        continue;
      }
      final shape = (message['shape']! as List<Object?>).cast<int>();
      final input = message['data']! as Uint8List;
      final inputShapePointer = calloc<Int64>(shape.length);
      for (var index = 0; index < shape.length; index += 1) {
        inputShapePointer[index] = shape[index];
      }
      final inputDataPointer = calloc<Float>(
        input.lengthInBytes ~/ sizeOf<Float>(),
      );
      inputDataPointer.asTypedList(input.lengthInBytes ~/ sizeOf<Float>())
        ..setAll(0, input.buffer.asFloat32List());

      final outputDataPointer = calloc<Pointer<Float>>();
      final outputLengthPointer = calloc<Uint64>();
      final outputShapePointer = calloc<Pointer<Int64>>();
      final outputShapeLengthPointer = calloc<Uint64>();
      final labelsPointer = calloc<Pointer<Char>>();

      final status = bindings.run(
        engine,
        inputDataPointer,
        input.lengthInBytes ~/ sizeOf<Float>(),
        inputShapePointer,
        shape.length,
        outputDataPointer,
        outputLengthPointer,
        outputShapePointer,
        outputShapeLengthPointer,
        labelsPointer,
      );

      calloc.free(inputDataPointer);
      calloc.free(inputShapePointer);

      if (status != 0) {
        calloc.free(outputDataPointer);
        calloc.free(outputLengthPointer);
        calloc.free(outputShapePointer);
        calloc.free(outputShapeLengthPointer);
        calloc.free(labelsPointer);
        sendPort.send(<String, Object?>{
          'type': 'run_error',
          'requestId': requestId,
          'message': bindings.lastError().toDartString(),
        });
        continue;
      }

      final outputValues = outputDataPointer.value.asTypedList(
        outputLengthPointer.value.toInt(),
      );
      final outputBytes = Uint8List.view(
        Float32List.fromList(outputValues).buffer,
      );
      final shapeValues = outputShapePointer.value
          .asTypedList(outputShapeLengthPointer.value.toInt())
          .map((dimension) => dimension.toInt())
          .toList(growable: false);
      final labelCsv = labelsPointer.value == nullptr
          ? ''
          : labelsPointer.value.cast<Utf8>().toDartString();

      calloc.free(outputDataPointer.value);
      calloc.free(outputShapePointer.value);
      calloc.free(outputDataPointer);
      calloc.free(outputLengthPointer);
      calloc.free(outputShapePointer);
      calloc.free(outputShapeLengthPointer);
      if (labelsPointer.value != nullptr) {
        bindings.stringFree(labelsPointer.value);
      }
      calloc.free(labelsPointer);

      sendPort.send(<String, Object?>{
        'type': 'run_ok',
        'requestId': requestId,
        'output': outputBytes,
        'shape': shapeValues,
        'labels': labelCsv.isEmpty ? const <String>[] : labelCsv.split(','),
      });
      continue;
    }
    if (type == 'dispose') {
      if (engine != nullptr) {
        bindings.destroyEngine(engine);
        engine = nullptr;
      }
      sendPort.send(const <String, Object?>{'type': 'disposed'});
      receivePort.close();
      return;
    }
  }
}

typedef _NativeOnnxIsAvailableC = Int32 Function();
typedef _NativeOnnxIsAvailableDart = int Function();

typedef _NativeOnnxCreateEngineC = Pointer<Void> Function(Pointer<Utf8>);
typedef _NativeOnnxCreateEngineDart = Pointer<Void> Function(Pointer<Utf8>);

typedef _NativeOnnxDestroyEngineC = Void Function(Pointer<Void>);
typedef _NativeOnnxDestroyEngineDart = void Function(Pointer<Void>);

typedef _NativeOnnxRunC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Float>,
      Uint64,
      Pointer<Int64>,
      Uint64,
      Pointer<Pointer<Float>>,
      Pointer<Uint64>,
      Pointer<Pointer<Int64>>,
      Pointer<Uint64>,
      Pointer<Pointer<Char>>,
    );
typedef _NativeOnnxRunDart =
    int Function(
      Pointer<Void>,
      Pointer<Float>,
      int,
      Pointer<Int64>,
      int,
      Pointer<Pointer<Float>>,
      Pointer<Uint64>,
      Pointer<Pointer<Int64>>,
      Pointer<Uint64>,
      Pointer<Pointer<Char>>,
    );

typedef _NativeOnnxStringFreeC = Void Function(Pointer<Char>);
typedef _NativeOnnxStringFreeDart = void Function(Pointer<Char>);

typedef _NativeOnnxLastErrorC = Pointer<Utf8> Function();
typedef _NativeOnnxLastErrorDart = Pointer<Utf8> Function();
