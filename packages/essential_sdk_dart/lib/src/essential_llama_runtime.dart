import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

final class EssentialLlamaModelOptions {
  const EssentialLlamaModelOptions({
    this.contextSize = 1024,
    this.threads,
    this.batchThreads,
    this.gpuLayers = 0,
    this.useMmap = true,
    this.useMlock = false,
  });

  final int contextSize;
  final int? threads;
  final int? batchThreads;
  final int gpuLayers;
  final bool useMmap;
  final bool useMlock;

  Map<String, Object?> toMessage() {
    final resolvedThreads = threads ?? Platform.numberOfProcessors.clamp(1, 8);
    final resolvedBatchThreads =
        batchThreads ?? Platform.numberOfProcessors.clamp(1, 8);
    return <String, Object?>{
      'contextSize': contextSize,
      'threads': resolvedThreads,
      'batchThreads': resolvedBatchThreads,
      'gpuLayers': gpuLayers,
      'useMmap': useMmap,
      'useMlock': useMlock,
    };
  }
}

final class EssentialLlamaGenerationOptions {
  const EssentialLlamaGenerationOptions({
    this.maxTokens = 64,
    this.topK = 40,
    this.topP = 0.95,
    this.temperature = 0.8,
    this.seed = 42,
  });

  final int maxTokens;
  final int topK;
  final double topP;
  final double temperature;
  final int seed;

  Map<String, Object?> toMessage() {
    return <String, Object?>{
      'maxTokens': maxTokens,
      'topK': topK,
      'topP': topP,
      'temperature': temperature,
      'seed': seed,
    };
  }
}

final class EssentialGeneration {
  const EssentialGeneration({required this.stream, required this.completed});

  final Stream<String> stream;
  final Future<String> completed;
}

final class EssentialAdapterAttachmentOptions {
  const EssentialAdapterAttachmentOptions({this.scale = 1.0});

  final double scale;

  Map<String, Object?> toMessage() {
    return <String, Object?>{'scale': scale};
  }
}

final class EssentialLlamaRuntime {
  EssentialLlamaRuntime._(this._commandPort, this._responses);

  static Future<EssentialLlamaRuntime> create() async {
    final receivePort = ReceivePort();
    final commandPortCompleter = Completer<SendPort>();
    EssentialLlamaRuntime? runtime;
    Object? pendingIsolateFailure;
    await Isolate.spawn(
      _isolateMain,
      receivePort.sendPort,
      onError: receivePort.sendPort,
      onExit: receivePort.sendPort,
    );
    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!commandPortCompleter.isCompleted) {
          commandPortCompleter.complete(message);
        }
        return;
      }
      if (message is List<Object?> && message.isNotEmpty) {
        final error = StateError('Llama isolate failed: ${message.first}');
        final currentRuntime = runtime;
        if (currentRuntime == null) {
          pendingIsolateFailure = error;
        } else {
          currentRuntime._failPending(error);
        }
        return;
      }
      if (message == null) {
        runtime?._failPending(StateError('Llama isolate exited.'));
        return;
      }
      runtime?._handleResponse(message);
    });
    final commandPort = await commandPortCompleter.future;
    final createdRuntime = EssentialLlamaRuntime._(commandPort, receivePort);
    runtime = createdRuntime;
    final startupFailure = pendingIsolateFailure;
    if (startupFailure != null) {
      createdRuntime._failPending(startupFailure);
    }
    return createdRuntime;
  }

  final SendPort _commandPort;
  final ReceivePort _responses;
  int _nextRequestId = 1;
  final Map<int, Completer<void>> _pendingLoads = <int, Completer<void>>{};
  final Map<int, _PendingGeneration> _pendingGenerations =
      <int, _PendingGeneration>{};
  Completer<void>? _disposeCompleter;

  Future<void> loadModel(
    String modelPath, {
    EssentialLlamaModelOptions options = const EssentialLlamaModelOptions(),
  }) {
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingLoads[requestId] = completer;
    _commandPort.send(<String, Object?>{
      'type': 'load',
      'requestId': requestId,
      'modelPath': modelPath,
      ...options.toMessage(),
    });
    return completer.future;
  }

  Future<void> attachAdapter(
    String sessionId,
    String adapterPath, {
    EssentialAdapterAttachmentOptions options =
        const EssentialAdapterAttachmentOptions(),
  }) {
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingLoads[requestId] = completer;
    _commandPort.send(<String, Object?>{
      'type': 'attach_adapter',
      'requestId': requestId,
      'sessionId': sessionId,
      'adapterPath': adapterPath,
      ...options.toMessage(),
    });
    return completer.future;
  }

  Future<void> detachAdapter(String sessionId) {
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingLoads[requestId] = completer;
    _commandPort.send(<String, Object?>{
      'type': 'detach_adapter',
      'requestId': requestId,
      'sessionId': sessionId,
    });
    return completer.future;
  }

  EssentialGeneration generate(
    String prompt, {
    String? sessionId,
    EssentialLlamaGenerationOptions options =
        const EssentialLlamaGenerationOptions(),
  }) {
    final requestId = _nextRequestId++;
    final controller = StreamController<String>();
    final completer = Completer<String>();
    _pendingGenerations[requestId] = _PendingGeneration(controller, completer);
    _commandPort.send(<String, Object?>{
      'type': 'generate',
      'requestId': requestId,
      'prompt': prompt,
      'sessionId': sessionId,
      ...options.toMessage(),
    });
    return EssentialGeneration(
      stream: controller.stream,
      completed: completer.future,
    );
  }

  Future<void> cancel() async {
    _commandPort.send(const <String, Object?>{'type': 'cancel'});
  }

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
    if (type == 'load_ok') {
      final requestId = message['requestId']! as int;
      final completer = _pendingLoads.remove(requestId);
      completer?.complete();
      return;
    }
    if (type == 'load_error') {
      final requestId = message['requestId']! as int;
      final completer = _pendingLoads.remove(requestId);
      completer?.completeError(StateError(message['message']! as String));
      return;
    }
    if (type == 'attach_ok' || type == 'detach_ok') {
      final requestId = message['requestId']! as int;
      final completer = _pendingLoads.remove(requestId);
      completer?.complete();
      return;
    }
    if (type == 'attach_error' || type == 'detach_error') {
      final requestId = message['requestId']! as int;
      final completer = _pendingLoads.remove(requestId);
      completer?.completeError(StateError(message['message']! as String));
      return;
    }
    if (type == 'token') {
      final requestId = message['requestId']! as int;
      final pending = _pendingGenerations[requestId];
      pending?.controller.add(message['value']! as String);
      return;
    }
    if (type == 'done') {
      final requestId = message['requestId']! as int;
      final pending = _pendingGenerations.remove(requestId);
      if (pending == null) {
        return;
      }
      pending.controller.close();
      pending.completer.complete(message['value']! as String);
      return;
    }
    if (type == 'generate_error') {
      final requestId = message['requestId']! as int;
      final pending = _pendingGenerations.remove(requestId);
      if (pending == null) {
        return;
      }
      final error = StateError(message['message']! as String);
      pending.controller.addError(error);
      pending.controller.close();
      pending.completer.completeError(error);
      return;
    }
    if (type == 'disposed') {
      _disposeCompleter?.complete();
      _disposeCompleter = null;
      _responses.close();
    }
  }

  void _failPending(Object error) {
    for (final completer in _pendingLoads.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingLoads.clear();
    for (final pending in _pendingGenerations.values) {
      pending.controller.addError(error);
      pending.controller.close();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _pendingGenerations.clear();
    if (_disposeCompleter != null && !_disposeCompleter!.isCompleted) {
      _disposeCompleter!.completeError(error);
    }
  }
}

final class _PendingGeneration {
  const _PendingGeneration(this.controller, this.completer);

  final StreamController<String> controller;
  final Completer<String> completer;
}

final class _NativeModelOptions extends Struct {
  @Int32()
  external int contextSize;

  @Int32()
  external int threads;

  @Int32()
  external int batchThreads;

  @Int32()
  external int gpuLayers;

  @Int32()
  external int useMmap;

  @Int32()
  external int useMlock;
}

final class _NativeAttachmentOptions extends Struct {
  @Float()
  external double scale;
}

final class _NativeGenerationOptions extends Struct {
  @Int32()
  external int maxTokens;

  @Int32()
  external int topK;

  @Float()
  external double topP;

  @Float()
  external double temperature;

  @Uint32()
  external int seed;
}

typedef _NativeCreateEngineC =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<_NativeModelOptions>);
typedef _NativeCreateEngineDart =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<_NativeModelOptions>);

typedef _NativeDestroyEngineC = Void Function(Pointer<Void>);
typedef _NativeDestroyEngineDart = void Function(Pointer<Void>);

typedef _NativeCancelC = Int32 Function(Pointer<Void>);
typedef _NativeCancelDart = int Function(Pointer<Void>);

typedef _NativeTokenCallbackC = Void Function(Pointer<Utf8>, Pointer<Void>);

typedef _NativeGenerateC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<_NativeGenerationOptions>,
      Pointer<NativeFunction<_NativeTokenCallbackC>>,
      Pointer<Void>,
      Pointer<Pointer<Char>>,
    );
typedef _NativeGenerateDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<_NativeGenerationOptions>,
      Pointer<NativeFunction<_NativeTokenCallbackC>>,
      Pointer<Void>,
      Pointer<Pointer<Char>>,
    );

typedef _NativeAttachAdapterC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<_NativeAttachmentOptions>,
    );
typedef _NativeAttachAdapterDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<_NativeAttachmentOptions>,
    );

typedef _NativeDetachAdapterC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _NativeDetachAdapterDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _NativeStringFreeC = Void Function(Pointer<Char>);
typedef _NativeStringFreeDart = void Function(Pointer<Char>);

typedef _NativeLastErrorC = Pointer<Utf8> Function();
typedef _NativeLastErrorDart = Pointer<Utf8> Function();

final class _EssentialLlamaBindings {
  _EssentialLlamaBindings(DynamicLibrary library)
    : createEngine = library
          .lookupFunction<_NativeCreateEngineC, _NativeCreateEngineDart>(
            'essential_llama_engine_create',
          ),
      destroyEngine = library
          .lookupFunction<_NativeDestroyEngineC, _NativeDestroyEngineDart>(
            'essential_llama_engine_destroy',
          ),
      cancel = library.lookupFunction<_NativeCancelC, _NativeCancelDart>(
        'essential_llama_engine_cancel',
      ),
      generate = library.lookupFunction<_NativeGenerateC, _NativeGenerateDart>(
        'essential_llama_engine_generate',
      ),
      attachAdapter = library
          .lookupFunction<_NativeAttachAdapterC, _NativeAttachAdapterDart>(
            'essential_llama_engine_attach_adapter',
          ),
      detachAdapter = library
          .lookupFunction<_NativeDetachAdapterC, _NativeDetachAdapterDart>(
            'essential_llama_engine_detach_adapter',
          ),
      stringFree = library
          .lookupFunction<_NativeStringFreeC, _NativeStringFreeDart>(
            'essential_llama_string_free',
          ),
      lastError = library
          .lookupFunction<_NativeLastErrorC, _NativeLastErrorDart>(
            'essential_llama_last_error_message',
          );

  final _NativeCreateEngineDart createEngine;
  final _NativeDestroyEngineDart destroyEngine;
  final _NativeCancelDart cancel;
  final _NativeGenerateDart generate;
  final _NativeAttachAdapterDart attachAdapter;
  final _NativeDetachAdapterDart detachAdapter;
  final _NativeStringFreeDart stringFree;
  final _NativeLastErrorDart lastError;
}

DynamicLibrary _loadLibrary() {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open(
      'essential_sdk_dart.framework/essential_sdk_dart',
    );
  }
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libessential_android_service.so');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libessential_sdk_dart.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('essential_sdk_dart.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

Future<void> _isolateMain(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final bindings = _EssentialLlamaBindings(_loadLibrary());
  Pointer<Void> engine = nullptr;

  await for (final dynamic message in receivePort) {
    if (message is! Map<Object?, Object?>) {
      continue;
    }
    final type = message['type'];
    if (type == 'load') {
      final requestId = message['requestId']! as int;
      if (engine != nullptr) {
        bindings.destroyEngine(engine);
        engine = nullptr;
      }
      final modelPathPointer = (message['modelPath']! as String).toNativeUtf8();
      final optionsPointer = calloc<_NativeModelOptions>();
      optionsPointer.ref.contextSize = message['contextSize']! as int;
      optionsPointer.ref.threads = message['threads']! as int;
      optionsPointer.ref.batchThreads = message['batchThreads']! as int;
      optionsPointer.ref.gpuLayers = message['gpuLayers']! as int;
      optionsPointer.ref.useMmap = (message['useMmap']! as bool) ? 1 : 0;
      optionsPointer.ref.useMlock = (message['useMlock']! as bool) ? 1 : 0;
      final createdEngine = bindings.createEngine(
        modelPathPointer,
        optionsPointer,
      );
      calloc.free(modelPathPointer);
      calloc.free(optionsPointer);
      if (createdEngine.address == 0) {
        sendPort.send(<String, Object?>{
          'type': 'load_error',
          'requestId': requestId,
          'message': bindings.lastError().toDartString(),
        });
        continue;
      }
      engine = createdEngine;
      sendPort.send(<String, Object?>{
        'type': 'load_ok',
        'requestId': requestId,
      });
      continue;
    }
    if (type == 'attach_adapter') {
      final requestId = message['requestId']! as int;
      if (engine == nullptr) {
        sendPort.send(<String, Object?>{
          'type': 'attach_error',
          'requestId': requestId,
          'message': 'Model is not loaded.',
        });
        continue;
      }
      final sessionIdPointer = (message['sessionId']! as String).toNativeUtf8();
      final adapterPathPointer = (message['adapterPath']! as String)
          .toNativeUtf8();
      final optionsPointer = calloc<_NativeAttachmentOptions>();
      optionsPointer.ref.scale = (message['scale']! as num).toDouble();
      final status = bindings.attachAdapter(
        engine,
        sessionIdPointer,
        adapterPathPointer,
        optionsPointer,
      );
      calloc.free(sessionIdPointer);
      calloc.free(adapterPathPointer);
      calloc.free(optionsPointer);
      if (status != 0) {
        sendPort.send(<String, Object?>{
          'type': 'attach_error',
          'requestId': requestId,
          'message': bindings.lastError().toDartString(),
        });
        continue;
      }
      sendPort.send(<String, Object?>{
        'type': 'attach_ok',
        'requestId': requestId,
      });
      continue;
    }
    if (type == 'detach_adapter') {
      final requestId = message['requestId']! as int;
      if (engine == nullptr) {
        sendPort.send(<String, Object?>{
          'type': 'detach_error',
          'requestId': requestId,
          'message': 'Model is not loaded.',
        });
        continue;
      }
      final sessionIdPointer = (message['sessionId']! as String).toNativeUtf8();
      final status = bindings.detachAdapter(engine, sessionIdPointer);
      calloc.free(sessionIdPointer);
      if (status != 0) {
        sendPort.send(<String, Object?>{
          'type': 'detach_error',
          'requestId': requestId,
          'message': bindings.lastError().toDartString(),
        });
        continue;
      }
      sendPort.send(<String, Object?>{
        'type': 'detach_ok',
        'requestId': requestId,
      });
      continue;
    }
    if (type == 'generate') {
      final requestId = message['requestId']! as int;
      if (engine == nullptr) {
        sendPort.send(<String, Object?>{
          'type': 'generate_error',
          'requestId': requestId,
          'message': 'Model is not loaded.',
        });
        continue;
      }
      final promptPointer = (message['prompt']! as String).toNativeUtf8();
      final sessionIdPointer = ((message['sessionId'] as String?) ?? '')
          .toNativeUtf8();
      final optionsPointer = calloc<_NativeGenerationOptions>();
      final outputPointer = calloc<Pointer<Char>>();
      optionsPointer.ref.maxTokens = message['maxTokens']! as int;
      optionsPointer.ref.topK = message['topK']! as int;
      optionsPointer.ref.topP = (message['topP']! as num).toDouble();
      optionsPointer.ref.temperature = (message['temperature']! as num)
          .toDouble();
      optionsPointer.ref.seed = message['seed']! as int;
      final callback = NativeCallable<_NativeTokenCallbackC>.isolateLocal((
        Pointer<Utf8> token,
        Pointer<Void> _,
      ) {
        sendPort.send(<String, Object?>{
          'type': 'token',
          'requestId': requestId,
          'value': token.toDartString(),
        });
      });
      final status = bindings.generate(
        engine,
        sessionIdPointer,
        promptPointer,
        optionsPointer,
        callback.nativeFunction,
        nullptr,
        outputPointer,
      );
      callback.close();
      calloc.free(sessionIdPointer);
      calloc.free(promptPointer);
      calloc.free(optionsPointer);
      if (status != 0) {
        calloc.free(outputPointer);
        sendPort.send(<String, Object?>{
          'type': 'generate_error',
          'requestId': requestId,
          'message': bindings.lastError().toDartString(),
        });
        continue;
      }
      final generatedText = outputPointer.value.cast<Utf8>().toDartString();
      bindings.stringFree(outputPointer.value);
      calloc.free(outputPointer);
      sendPort.send(<String, Object?>{
        'type': 'done',
        'requestId': requestId,
        'value': generatedText,
      });
      continue;
    }
    if (type == 'cancel') {
      if (engine != nullptr) {
        bindings.cancel(engine);
      }
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
