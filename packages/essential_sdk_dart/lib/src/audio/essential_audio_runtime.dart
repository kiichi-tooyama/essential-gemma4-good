import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import '../essential_runtime.dart';
import '../essential_task_router.dart';
import '../essential_task_types.dart';
import '../essential_types.dart';
import 'essential_audio_ffi.dart';
import 'essential_audio_types.dart';

final class EssentialAudioRuntime extends EssentialBaseRuntime {
  EssentialAudioRuntime({EssentialAudioFfi? ffi}) : _ffi = ffi;

  EssentialAudioFfi? _ffi;
  Pointer<Void>? _context;
  Pointer<Void>? _sttSession;
  Pointer<Void>? _ttsSession;
  String? _sttModelPath;
  String? _ttsModelPath;
  bool _available = false;

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.onnx;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> initialize() async {
    try {
      _ffi ??= EssentialAudioFfi();
      _context = _ffi!.createContext();
      _available = _context != nullptr;
    } catch (_) {
      _available = false;
    }
  }

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async {
    final requestId = request.id!;
    switch (request.taskType) {
      case EssentialTaskType.stt:
        final payload = request.payload;
        if (payload is! EssentialAudioTaskPayload) {
          throw const EssentialException(
            EssentialErrorCode.payloadSchemaInvalid,
            'STT requires EssentialAudioTaskPayload.',
          );
        }
        final result = payload.audioFilePath == null
            ? _ffi!.processChunk(
                await _ensureSttSession(request),
                EssentialAudioBufferData(
                  samples: payload.samples ?? Float32List(0),
                  sampleRate: payload.sampleRate,
                  channels: payload.channels,
                  format: payload.format,
                ),
              )
            : _ffi!.processFile(
                await _ensureSttSession(request),
                payload.audioFilePath!,
              );
        return EssentialTaskResponse(
          requestId: requestId,
          taskType: request.taskType,
          status: EssentialTaskStatus.completed,
          result: EssentialTaskResult(
            text: result.text,
            metadata: <String, Object?>{
              'segments': result.segments
                  .map(
                    (segment) => <String, Object?>{
                      'text': segment.text,
                      'confidence': segment.confidence,
                      'start_time': segment.startTime,
                      'end_time': segment.endTime,
                      'is_final': segment.isFinal,
                    },
                  )
                  .toList(),
            },
          ),
          runtimeFamily: family,
          capabilityId: decision.capability.capabilityId,
          modelUsed: _sttModelPath ?? 'android-speechrecognizer',
        );
      case EssentialTaskType.tts:
        final payload = request.payload;
        if (payload is! EssentialTtsTaskPayload) {
          throw const EssentialException(
            EssentialErrorCode.payloadSchemaInvalid,
            'TTS requires EssentialTtsTaskPayload.',
          );
        }
        final audio = _ffi!.synthesize(
          await _ensureTtsSession(request),
          payload.text,
        );
        return EssentialTaskResponse(
          requestId: requestId,
          taskType: request.taskType,
          status: EssentialTaskStatus.completed,
          result: EssentialTaskResult(
            tensorData: audio.samples,
            tensorShape: <int>[audio.samples.length],
            metadata: <String, Object?>{
              'sample_rate': audio.sampleRate,
              'channels': audio.channels,
              'format': audio.format.name,
            },
          ),
          runtimeFamily: family,
          capabilityId: decision.capability.capabilityId,
          modelUsed: _ttsModelPath ?? 'tts',
        );
      default:
        throw EssentialException(
          EssentialErrorCode.unsupportedTaskType,
          'Audio runtime does not support ${request.taskType.wireName}.',
        );
    }
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
      final stt = _sttSession;
      final tts = _ttsSession;
      final context = _context;
      if (stt != null) {
        ffi.destroySession(stt);
      }
      if (tts != null) {
        ffi.destroySession(tts);
      }
      if (context != null) {
        ffi.destroyContext(context);
      }
    }
    _context = null;
    _sttSession = null;
    _ttsSession = null;
    _available = false;
  }

  Future<Pointer<Void>> _ensureSttSession(EssentialTaskRequest request) async {
    final ffi = _ffi;
    final context = _context;
    if (ffi == null || context == null || context == nullptr) {
      throw const EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        'Audio runtime is not initialized.',
      );
    }
    final modelPath =
        request.modelRequirement.explicitModelPath ??
        request.metadata['stt_model_path'] as String?;
    if (modelPath == null || modelPath.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'STT requires an explicit model path.',
      );
    }
    if (_sttSession != null && _sttModelPath == modelPath) {
      return _sttSession!;
    }
    if (_sttSession != null) {
      ffi.destroySession(_sttSession!);
    }
    _sttSession = ffi.createSttSession(
      context: context,
      modelPath: modelPath,
      language: request.metadata['language'] as String? ?? 'auto',
      translate: request.metadata['translate'] as bool? ?? false,
    );
    _sttModelPath = modelPath;
    return _sttSession!;
  }

  Future<Pointer<Void>> _ensureTtsSession(EssentialTaskRequest request) async {
    final ffi = _ffi;
    final context = _context;
    if (ffi == null || context == null || context == nullptr) {
      throw const EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        'Audio runtime is not initialized.',
      );
    }
    final modelPath =
        request.modelRequirement.explicitModelPath ??
        request.metadata['tts_model_path'] as String?;
    if (modelPath == null || modelPath.isEmpty) {
      throw const EssentialException(
        EssentialErrorCode.modelNotInstalled,
        'TTS requires an explicit model path.',
      );
    }
    if (_ttsSession != null && _ttsModelPath == modelPath) {
      return _ttsSession!;
    }
    if (_ttsSession != null) {
      ffi.destroySession(_ttsSession!);
    }
    _ttsSession = ffi.createTtsSession(
      context: context,
      modelPath: modelPath,
      config: EssentialTtsConfigData(
        voiceId: request.metadata['voice_id'] as String? ?? 'default',
        speed: (request.metadata['speed'] as num?)?.toDouble() ?? 1,
        pitch: (request.metadata['pitch'] as num?)?.toDouble() ?? 0,
        sampleRate: request.metadata['sample_rate'] as int? ?? 22050,
      ),
    );
    _ttsModelPath = modelPath;
    return _ttsSession!;
  }
}

final class EssentialAudioTaskPayload implements EssentialTaskPayload {
  EssentialAudioTaskPayload({
    this.samples,
    this.audioFilePath,
    this.sampleRate = 16000,
    this.channels = 1,
    this.format = EssentialAudioFormat.pcm16k,
  });

  final Float32List? samples;
  final String? audioFilePath;
  final int sampleRate;
  final int channels;
  final EssentialAudioFormat format;
}

final class EssentialTtsTaskPayload implements EssentialTaskPayload {
  const EssentialTtsTaskPayload({required this.text});

  final String text;
}
