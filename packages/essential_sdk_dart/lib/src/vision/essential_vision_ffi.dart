import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../essential_types.dart';
import 'essential_vision_types.dart';

DynamicLibrary _openVisionLib() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libessential_vision.so');
  } else if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('essential_vision.dll');
  }
  throw UnsupportedError('Unsupported platform');
}

final class EssentialNativeImage extends Struct {
  external Pointer<Uint8> data;

  @Size()
  external int dataSize;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Int32()
  external int format;

  @Int32()
  external int orientation;
}

final class EssentialNativeVisionConfig extends Struct {
  @Int32()
  external int taskType;

  external Pointer<Utf8> modelPath;
  external Pointer<Utf8> labelMapPath;

  @Int32()
  external int targetWidth;

  @Int32()
  external int targetHeight;

  @Float()
  external double confidenceThreshold;

  @Int32()
  external int topK;

  @Bool()
  external bool useGpu;
}

final class EssentialNativeClassification extends Struct {
  external Pointer<Utf8> label;
  external Pointer<Utf8> labelId;

  @Float()
  external double confidence;
}

final class EssentialNativeDetectionBox extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double width;

  @Float()
  external double height;

  @Float()
  external double rotation;
}

final class EssentialNativeDetection extends Struct {
  external Pointer<Utf8> label;
  external Pointer<Utf8> labelId;

  @Float()
  external double confidence;

  external EssentialNativeDetectionBox box;
}

final class EssentialNativeTextRegion extends Struct {
  external Pointer<Utf8> text;

  @Float()
  external double confidence;

  external EssentialNativeDetectionBox box;
}

final class EssentialNativeVisionResult extends Struct {
  external Pointer<EssentialNativeClassification> classifications;

  @Size()
  external int numClassifications;

  external Pointer<EssentialNativeDetection> detections;

  @Size()
  external int numDetections;

  external Pointer<EssentialNativeTextRegion> textRegions;

  @Size()
  external int numTextRegions;

  external Pointer<Utf8> captionText;

  @Int32()
  external int latencyMs;

  external Pointer<Pointer<Utf8>> modelBundleUsed;

  @Size()
  external int numModels;

  external Pointer<Utf8> errorMessage;
}

typedef _CreateContextNative = Pointer<Void> Function();
typedef _CreateContextDart = Pointer<Void> Function();
typedef _DestroyContextNative = Void Function(Pointer<Void>);
typedef _DestroyContextDart = void Function(Pointer<Void>);
typedef _CreateSessionNative =
    Pointer<Void> Function(Pointer<Void>, Pointer<EssentialNativeVisionConfig>);
typedef _CreateSessionDart =
    Pointer<Void> Function(Pointer<Void>, Pointer<EssentialNativeVisionConfig>);
typedef _DestroySessionNative = Void Function(Pointer<Void>);
typedef _DestroySessionDart = void Function(Pointer<Void>);
typedef _RunInferenceNative =
    Pointer<EssentialNativeVisionResult> Function(
      Pointer<Void>,
      Pointer<EssentialNativeImage>,
    );
typedef _RunInferenceDart =
    Pointer<EssentialNativeVisionResult> Function(
      Pointer<Void>,
      Pointer<EssentialNativeImage>,
    );
typedef _FreeResultNative = Void Function(Pointer<EssentialNativeVisionResult>);
typedef _FreeResultDart = void Function(Pointer<EssentialNativeVisionResult>);

class EssentialVisionFfi {
  EssentialVisionFfi({DynamicLibrary? library})
    : _lib = library ?? _openVisionLib();

  final DynamicLibrary _lib;

  late final _CreateContextDart _createContext = _lib
      .lookupFunction<_CreateContextNative, _CreateContextDart>(
        'essential_vision_create_context',
      );
  late final _DestroyContextDart _destroyContext = _lib
      .lookupFunction<_DestroyContextNative, _DestroyContextDart>(
        'essential_vision_destroy_context',
      );
  late final _CreateSessionDart _createSession = _lib
      .lookupFunction<_CreateSessionNative, _CreateSessionDart>(
        'essential_vision_create_session',
      );
  late final _DestroySessionDart _destroySession = _lib
      .lookupFunction<_DestroySessionNative, _DestroySessionDart>(
        'essential_vision_destroy_session',
      );
  late final _RunInferenceDart _runInference = _lib
      .lookupFunction<_RunInferenceNative, _RunInferenceDart>(
        'essential_vision_run_inference',
      );
  late final _FreeResultDart _freeResult = _lib
      .lookupFunction<_FreeResultNative, _FreeResultDart>(
        'essential_vision_free_result',
      );

  Pointer<Void> createContext() => _createContext();

  void destroyContext(Pointer<Void> context) {
    if (context != nullptr) {
      _destroyContext(context);
    }
  }

  Pointer<Void> createSession({
    required Pointer<Void> context,
    required String modelPath,
    required ImageTaskType taskType,
    int targetWidth = 224,
    int targetHeight = 224,
    double confidenceThreshold = 0.25,
    int topK = 5,
    bool useGpu = false,
    String? labelMapPath,
  }) {
    final config = calloc<EssentialNativeVisionConfig>();
    final model = modelPath.toNativeUtf8();
    final labels = (labelMapPath ?? '').toNativeUtf8();
    try {
      config.ref
        ..taskType = _taskTypeToNative(taskType)
        ..modelPath = model
        ..labelMapPath = labels
        ..targetWidth = targetWidth
        ..targetHeight = targetHeight
        ..confidenceThreshold = confidenceThreshold
        ..topK = topK
        ..useGpu = useGpu;
      final session = _createSession(context, config);
      if (session == nullptr) {
        throw const EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          'Failed to create native vision session.',
        );
      }
      return session;
    } finally {
      calloc.free(config);
      calloc.free(model);
      calloc.free(labels);
    }
  }

  void destroySession(Pointer<Void> session) {
    if (session != nullptr) {
      _destroySession(session);
    }
  }

  VisionResult runInference({
    required Pointer<Void> session,
    required Uint8List imageBytes,
    required ImageMetadata metadata,
    required ImageTaskType taskType,
    int format = 0,
  }) {
    final image = calloc<EssentialNativeImage>();
    final data = calloc<Uint8>(imageBytes.length);
    try {
      data.asTypedList(imageBytes.length).setAll(0, imageBytes);
      image.ref
        ..data = data
        ..dataSize = imageBytes.length
        ..width = metadata.width
        ..height = metadata.height
        ..format = format
        ..orientation = metadata.orientation ?? 1;
      final nativeResult = _runInference(session, image);
      if (nativeResult == nullptr) {
        throw const EssentialException(
          EssentialErrorCode.runtimeUnavailable,
          'Native vision inference returned null.',
        );
      }
      try {
        return _readResult(nativeResult, metadata, taskType);
      } finally {
        _freeResult(nativeResult);
      }
    } finally {
      calloc.free(data);
      calloc.free(image);
    }
  }

  VisionResult _readResult(
    Pointer<EssentialNativeVisionResult> pointer,
    ImageMetadata metadata,
    ImageTaskType taskType,
  ) {
    final result = pointer.ref;
    final error = result.errorMessage == nullptr
        ? null
        : result.errorMessage.toDartString();
    return VisionResult(
      requestId: '',
      taskType: taskType,
      imageMetadata: metadata,
      classifications: _readClassifications(result),
      detections: _readDetections(result),
      textBlocks: _readTextRegions(result),
      captionText: result.captionText == nullptr
          ? null
          : result.captionText.toDartString(),
      latencyMs: result.latencyMs,
      modelBundleUsed: _readModelBundle(result),
      error: error,
    );
  }

  List<ClassificationResult>? _readClassifications(
    EssentialNativeVisionResult result,
  ) {
    if (result.classifications == nullptr || result.numClassifications == 0) {
      return null;
    }
    return List<ClassificationResult>.generate(result.numClassifications, (i) {
      final item = (result.classifications + i).ref;
      return ClassificationResult(
        label: item.label == nullptr ? '' : item.label.toDartString(),
        labelId: item.labelId == nullptr ? null : item.labelId.toDartString(),
        confidence: item.confidence,
      );
    });
  }

  List<DetectionResult>? _readDetections(EssentialNativeVisionResult result) {
    if (result.detections == nullptr || result.numDetections == 0) {
      return null;
    }
    return List<DetectionResult>.generate(result.numDetections, (i) {
      final item = (result.detections + i).ref;
      return DetectionResult(
        label: item.label == nullptr ? '' : item.label.toDartString(),
        labelId: item.labelId == nullptr ? null : item.labelId.toDartString(),
        confidence: item.confidence,
        box: DetectionBox(
          x: item.box.x,
          y: item.box.y,
          width: item.box.width,
          height: item.box.height,
          rotation: item.box.rotation,
        ),
      );
    });
  }

  List<TextRegion>? _readTextRegions(EssentialNativeVisionResult result) {
    if (result.textRegions == nullptr || result.numTextRegions == 0) {
      return null;
    }
    return List<TextRegion>.generate(result.numTextRegions, (i) {
      final item = (result.textRegions + i).ref;
      return TextRegion(
        text: item.text == nullptr ? '' : item.text.toDartString(),
        confidence: item.confidence,
        box: DetectionBox(
          x: item.box.x,
          y: item.box.y,
          width: item.box.width,
          height: item.box.height,
          rotation: item.box.rotation,
        ),
      );
    });
  }

  List<String>? _readModelBundle(EssentialNativeVisionResult result) {
    if (result.modelBundleUsed == nullptr || result.numModels == 0) {
      return null;
    }
    return List<String>.generate(result.numModels, (i) {
      final value = (result.modelBundleUsed + i).value;
      return value == nullptr ? '' : value.toDartString();
    });
  }

  int _taskTypeToNative(ImageTaskType type) {
    return switch (type) {
      ImageTaskType.imageClassification => 0,
      ImageTaskType.objectDetection => 1,
      ImageTaskType.imageSegmentation => 2,
      ImageTaskType.ocr => 3,
      ImageTaskType.imageCaption => 4,
      ImageTaskType.faceDetection => 5,
      ImageTaskType.multimodalChat => 6,
    };
  }
}
