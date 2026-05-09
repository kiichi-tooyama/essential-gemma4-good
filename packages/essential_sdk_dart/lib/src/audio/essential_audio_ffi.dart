import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../essential_types.dart';
import 'essential_audio_types.dart';

DynamicLibrary _openAudioLib() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libessential_audio.so');
  } else if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('essential_audio.dll');
  }
  throw UnsupportedError('Unsupported platform');
}

final class EssentialNativeAudioBuffer extends Struct {
  external Pointer<Float> samples;

  @Int32()
  external int numSamples;

  @Int32()
  external int sampleRate;

  @Int32()
  external int format;

  @Int32()
  external int channels;
}

final class EssentialNativeSttSegment extends Struct {
  external Pointer<Utf8> text;

  @Float()
  external double confidence;

  @Double()
  external double startTime;

  @Double()
  external double endTime;

  @Bool()
  external bool isFinal;
}

final class EssentialNativeTtsConfig extends Struct {
  external Pointer<Utf8> voiceId;

  @Float()
  external double speed;

  @Float()
  external double pitch;

  @Int32()
  external int sampleRate;
}

typedef _CreateContextNative = Pointer<Void> Function();
typedef _CreateContextDart = Pointer<Void> Function();
typedef _DestroyContextNative = Void Function(Pointer<Void>);
typedef _DestroyContextDart = void Function(Pointer<Void>);
typedef _CreateSttSessionNative =
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef _CreateSttSessionDart =
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, bool);
typedef _CreateTtsSessionNative =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<EssentialNativeTtsConfig>,
    );
typedef _CreateTtsSessionDart =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<EssentialNativeTtsConfig>,
    );
typedef _DestroySessionNative = Void Function(Pointer<Void>);
typedef _DestroySessionDart = void Function(Pointer<Void>);
typedef _ProcessChunkNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<EssentialNativeAudioBuffer>,
      Pointer<Pointer<EssentialNativeSttSegment>>,
      Pointer<Int32>,
    );
typedef _ProcessChunkDart =
    int Function(
      Pointer<Void>,
      Pointer<EssentialNativeAudioBuffer>,
      Pointer<Pointer<EssentialNativeSttSegment>>,
      Pointer<Int32>,
    );
typedef _ProcessFileNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<EssentialNativeSttSegment>>,
      Pointer<Int32>,
    );
typedef _ProcessFileDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<EssentialNativeSttSegment>>,
      Pointer<Int32>,
    );
typedef _SynthesizeNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Pointer<EssentialNativeAudioBuffer>>,
    );
typedef _SynthesizeDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Pointer<EssentialNativeAudioBuffer>>,
    );
typedef _FreeBufferNative = Void Function(Pointer<EssentialNativeAudioBuffer>);
typedef _FreeBufferDart = void Function(Pointer<EssentialNativeAudioBuffer>);
typedef _FreeSegmentsNative =
    Void Function(Pointer<EssentialNativeSttSegment>, Int32);
typedef _FreeSegmentsDart =
    void Function(Pointer<EssentialNativeSttSegment>, int);
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);
typedef _GetLastErrorNative = Pointer<Utf8> Function();
typedef _GetLastErrorDart = Pointer<Utf8> Function();

class EssentialAudioFfi {
  EssentialAudioFfi({DynamicLibrary? library})
    : _lib = library ?? _openAudioLib();

  final DynamicLibrary _lib;

  late final _CreateContextDart _createContext = _lib
      .lookupFunction<_CreateContextNative, _CreateContextDart>(
        'essential_audio_create_context',
      );
  late final _DestroyContextDart _destroyContext = _lib
      .lookupFunction<_DestroyContextNative, _DestroyContextDart>(
        'essential_audio_destroy_context',
      );
  late final _CreateSttSessionDart _createSttSession = _lib
      .lookupFunction<_CreateSttSessionNative, _CreateSttSessionDart>(
        'essential_audio_create_stt_session',
      );
  late final _CreateTtsSessionDart _createTtsSession = _lib
      .lookupFunction<_CreateTtsSessionNative, _CreateTtsSessionDart>(
        'essential_audio_create_tts_session',
      );
  late final _DestroySessionDart _destroySession = _lib
      .lookupFunction<_DestroySessionNative, _DestroySessionDart>(
        'essential_audio_destroy_session',
      );
  late final _ProcessChunkDart _processChunk = _lib
      .lookupFunction<_ProcessChunkNative, _ProcessChunkDart>(
        'essential_audio_stt_process_chunk',
      );
  late final _ProcessFileDart _processFile = _lib
      .lookupFunction<_ProcessFileNative, _ProcessFileDart>(
        'essential_audio_stt_process_file',
      );
  late final _SynthesizeDart _synthesize = _lib
      .lookupFunction<_SynthesizeNative, _SynthesizeDart>(
        'essential_audio_tts_synthesize',
      );
  late final _FreeBufferDart _freeBuffer = _lib
      .lookupFunction<_FreeBufferNative, _FreeBufferDart>(
        'essential_audio_free_buffer',
      );
  late final _FreeSegmentsDart _freeSegments = _lib
      .lookupFunction<_FreeSegmentsNative, _FreeSegmentsDart>(
        'essential_audio_free_segments',
      );
  late final _FreeStringDart _freeString = _lib
      .lookupFunction<_FreeStringNative, _FreeStringDart>(
        'essential_audio_free_string',
      );
  late final _GetLastErrorDart _getLastError = _lib
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
        'essential_audio_get_last_error',
      );

  Pointer<Void> createContext() => _createContext();

  void destroyContext(Pointer<Void> context) {
    if (context != nullptr) {
      _destroyContext(context);
    }
  }

  Pointer<Void> createSttSession({
    required Pointer<Void> context,
    required String modelPath,
    String language = 'auto',
    bool translate = false,
  }) {
    final model = modelPath.toNativeUtf8();
    final lang = language.toNativeUtf8();
    try {
      final session = _createSttSession(context, model, lang, translate);
      if (session == nullptr) {
        throw EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          _lastErrorOr('Failed to create STT session.'),
        );
      }
      return session;
    } finally {
      calloc.free(model);
      calloc.free(lang);
    }
  }

  Pointer<Void> createTtsSession({
    required Pointer<Void> context,
    required String modelPath,
    EssentialTtsConfigData config = const EssentialTtsConfigData(),
  }) {
    final model = modelPath.toNativeUtf8();
    final voice = config.voiceId.toNativeUtf8();
    final nativeConfig = calloc<EssentialNativeTtsConfig>();
    try {
      nativeConfig.ref
        ..voiceId = voice
        ..speed = config.speed
        ..pitch = config.pitch
        ..sampleRate = config.sampleRate;
      final session = _createTtsSession(context, model, nativeConfig);
      if (session == nullptr) {
        throw EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          _lastErrorOr('Failed to create TTS session.'),
        );
      }
      return session;
    } finally {
      calloc.free(model);
      calloc.free(voice);
      calloc.free(nativeConfig);
    }
  }

  void destroySession(Pointer<Void> session) {
    if (session != nullptr) {
      _destroySession(session);
    }
  }

  EssentialSttResult processChunk(
    Pointer<Void> session,
    EssentialAudioBufferData audio,
  ) {
    final buffer = calloc<EssentialNativeAudioBuffer>();
    final samples = calloc<Float>(audio.samples.length);
    final segmentsOut = calloc<Pointer<EssentialNativeSttSegment>>();
    final countOut = calloc<Int32>();
    try {
      samples.asTypedList(audio.samples.length).setAll(0, audio.samples);
      buffer.ref
        ..samples = samples
        ..numSamples = audio.samples.length
        ..sampleRate = audio.sampleRate
        ..format = _formatToNative(audio.format)
        ..channels = audio.channels;
      final rc = _processChunk(session, buffer, segmentsOut, countOut);
      if (rc != 0) {
        throw EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          _lastErrorOr('STT inference failed.'),
        );
      }
      return _readSegments(segmentsOut.value, countOut.value);
    } finally {
      if (segmentsOut.value != nullptr) {
        _freeSegments(segmentsOut.value, countOut.value);
      }
      calloc.free(buffer);
      calloc.free(samples);
      calloc.free(segmentsOut);
      calloc.free(countOut);
    }
  }

  EssentialSttResult processFile(Pointer<Void> session, String audioFilePath) {
    final path = audioFilePath.toNativeUtf8();
    final textOut = calloc<Pointer<Utf8>>();
    final segmentsOut = calloc<Pointer<EssentialNativeSttSegment>>();
    final countOut = calloc<Int32>();
    try {
      final rc = _processFile(session, path, textOut, segmentsOut, countOut);
      if (rc != 0) {
        throw EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          _lastErrorOr('STT file inference failed.'),
        );
      }
      final segments = _readSegmentList(segmentsOut.value, countOut.value);
      final text = textOut.value == nullptr
          ? segments.map((segment) => segment.text).join(' ')
          : textOut.value.toDartString();
      return EssentialSttResult(text: text, segments: segments);
    } finally {
      if (textOut.value != nullptr) {
        _freeString(textOut.value);
      }
      if (segmentsOut.value != nullptr) {
        _freeSegments(segmentsOut.value, countOut.value);
      }
      calloc.free(path);
      calloc.free(textOut);
      calloc.free(segmentsOut);
      calloc.free(countOut);
    }
  }

  EssentialAudioBufferData synthesize(Pointer<Void> session, String text) {
    final nativeText = text.toNativeUtf8();
    final audioOut = calloc<Pointer<EssentialNativeAudioBuffer>>();
    try {
      final rc = _synthesize(session, nativeText, audioOut);
      if (rc != 0 || audioOut.value == nullptr) {
        throw EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          _lastErrorOr('TTS synthesis failed.'),
        );
      }
      final native = audioOut.value.ref;
      return EssentialAudioBufferData(
        samples: Float32List.fromList(
          native.samples.asTypedList(native.numSamples),
        ),
        sampleRate: native.sampleRate,
        channels: native.channels,
        format: _formatFromNative(native.format),
      );
    } finally {
      if (audioOut.value != nullptr) {
        _freeBuffer(audioOut.value);
      }
      calloc.free(nativeText);
      calloc.free(audioOut);
    }
  }

  EssentialSttResult _readSegments(
    Pointer<EssentialNativeSttSegment> segments,
    int count,
  ) {
    return EssentialSttResult(
      text: _readSegmentList(
        segments,
        count,
      ).map((segment) => segment.text).join(' '),
      segments: _readSegmentList(segments, count),
    );
  }

  List<EssentialSttSegmentData> _readSegmentList(
    Pointer<EssentialNativeSttSegment> segments,
    int count,
  ) {
    if (segments == nullptr || count <= 0) {
      return const <EssentialSttSegmentData>[];
    }
    return List<EssentialSttSegmentData>.generate(count, (i) {
      final item = (segments + i).ref;
      return EssentialSttSegmentData(
        text: item.text == nullptr ? '' : item.text.toDartString(),
        confidence: item.confidence,
        startTime: item.startTime,
        endTime: item.endTime,
        isFinal: item.isFinal,
      );
    });
  }

  String _lastErrorOr(String fallback) {
    final pointer = _getLastError();
    if (pointer == nullptr) {
      return fallback;
    }
    final value = pointer.toDartString();
    return value.isEmpty ? fallback : value;
  }

  int _formatToNative(EssentialAudioFormat format) {
    return switch (format) {
      EssentialAudioFormat.pcm16k => 0,
      EssentialAudioFormat.pcm22k => 1,
      EssentialAudioFormat.pcm44k => 2,
      EssentialAudioFormat.opus => 3,
      EssentialAudioFormat.aac => 4,
    };
  }

  EssentialAudioFormat _formatFromNative(int format) {
    return switch (format) {
      0 => EssentialAudioFormat.pcm16k,
      1 => EssentialAudioFormat.pcm22k,
      2 => EssentialAudioFormat.pcm44k,
      3 => EssentialAudioFormat.opus,
      4 => EssentialAudioFormat.aac,
      _ => EssentialAudioFormat.pcm16k,
    };
  }
}
