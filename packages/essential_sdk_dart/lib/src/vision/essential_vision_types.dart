// Image/Vision Task Types and Request/Response Models
// Part of Essential Multimodal SDK

import 'dart:typed_data';

/// Image task types supported by Essential Vision AI
enum ImageTaskType {
  imageClassification,
  objectDetection,
  imageSegmentation,
  ocr,
  imageCaption,
  faceDetection,
  multimodalChat,
}

/// Image source type
enum ImageSourceType { camera, gallery, memory, url }

/// Image metadata for vision tasks
class ImageMetadata {
  final int width;
  final int height;
  final String? format; // 'jpeg', 'png', 'webp'
  final int? orientation; // EXIF orientation
  final DateTime? timestamp;

  ImageMetadata({
    required this.width,
    required this.height,
    this.format,
    this.orientation,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'format': format,
    'orientation': orientation,
    'timestamp': timestamp?.toIso8601String(),
  };
}

/// Base class for image task requests
abstract class ImageTaskRequest {
  final String requestId;
  final ImageTaskType taskType;
  final Uint8List imageData;
  final ImageMetadata metadata;
  final String? prompt; // For multimodal chat or caption guidance
  final Map<String, dynamic>? options;
  final String? modelPath;

  ImageTaskRequest({
    required this.requestId,
    required this.taskType,
    required this.imageData,
    required this.metadata,
    this.prompt,
    this.options,
    this.modelPath,
  });

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'task_type': taskType.name,
    'image_data_length': imageData.length,
    'metadata': metadata.toJson(),
    'prompt': prompt,
    'options': options,
    'model_path': modelPath,
  };
}

/// Classification result item
class ClassificationResult {
  final String label;
  final String? labelId;
  final double confidence;

  ClassificationResult({
    required this.label,
    this.labelId,
    required this.confidence,
  });

  factory ClassificationResult.fromJson(Map<String, dynamic> json) =>
      ClassificationResult(
        label: json['label'] as String,
        labelId: json['label_id'] as String?,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

/// Detection box (normalized 0-1 coordinates)
class DetectionBox {
  final double x; // left
  final double y; // top
  final double width;
  final double height;
  final double? rotation;

  DetectionBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation,
  });

  factory DetectionBox.fromJson(Map<String, dynamic> json) => DetectionBox(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    rotation: json['rotation'] != null
        ? (json['rotation'] as num).toDouble()
        : null,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
  };
}

/// Object detection result
class DetectionResult {
  final String label;
  final String? labelId;
  final double confidence;
  final DetectionBox box;

  DetectionResult({
    required this.label,
    this.labelId,
    required this.confidence,
    required this.box,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) =>
      DetectionResult(
        label: json['label'] as String,
        labelId: json['label_id'] as String?,
        confidence: (json['confidence'] as num).toDouble(),
        box: DetectionBox.fromJson(json['box'] as Map<String, dynamic>),
      );
}

/// Segmentation mask
class SegmentationMask {
  final int width;
  final int height;
  final Uint8List maskData; // RLE encoded or raw bytes
  final String label;
  final int? color; // ARGB color for overlay

  SegmentationMask({
    required this.width,
    required this.height,
    required this.maskData,
    required this.label,
    this.color,
  });
}

/// OCR text region
class TextRegion {
  final String text;
  final double confidence;
  final DetectionBox box;
  final List<TextRegion>? tokens; // Word-level breakdown

  TextRegion({
    required this.text,
    required this.confidence,
    required this.box,
    this.tokens,
  });

  factory TextRegion.fromJson(Map<String, dynamic> json) => TextRegion(
    text: json['text'] as String,
    confidence: (json['confidence'] as num).toDouble(),
    box: DetectionBox.fromJson(json['box'] as Map<String, dynamic>),
    tokens: json['tokens'] != null
        ? (json['tokens'] as List)
              .map((e) => TextRegion.fromJson(e as Map<String, dynamic>))
              .toList()
        : null,
  );
}

/// Face landmark point
class FaceLandmark {
  final double x;
  final double y;
  final double? z;

  FaceLandmark({required this.x, required this.y, this.z});
}

/// Face detection result
class FaceResult {
  final DetectionBox box;
  final double confidence;
  final List<FaceLandmark>? landmarks;

  FaceResult({required this.box, required this.confidence, this.landmarks});
}

/// Complete vision task response
class VisionResult {
  final String requestId;
  final ImageTaskType taskType;
  final ImageMetadata imageMetadata;
  final List<ClassificationResult>? classifications;
  final List<DetectionResult>? detections;
  final List<SegmentationMask>? segments;
  final List<TextRegion>? textBlocks;
  final List<FaceResult>? faceRegions;
  final String? captionText;
  final int latencyMs;
  final List<String>? modelBundleUsed;
  final String? error;

  VisionResult({
    required this.requestId,
    required this.taskType,
    required this.imageMetadata,
    this.classifications,
    this.detections,
    this.segments,
    this.textBlocks,
    this.faceRegions,
    this.captionText,
    required this.latencyMs,
    this.modelBundleUsed,
    this.error,
  });

  bool get isSuccess => error == null;

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'task_type': taskType.name,
    'image_metadata': imageMetadata.toJson(),
    'classifications': classifications
        ?.map(
          (item) => {
            'label': item.label,
            'label_id': item.labelId,
            'confidence': item.confidence,
          },
        )
        .toList(),
    'detections': detections
        ?.map(
          (item) => {
            'label': item.label,
            'label_id': item.labelId,
            'confidence': item.confidence,
            'box': item.box.toJson(),
          },
        )
        .toList(),
    'text_blocks': textBlocks
        ?.map(
          (item) => {
            'text': item.text,
            'confidence': item.confidence,
            'box': item.box.toJson(),
          },
        )
        .toList(),
    'caption_text': captionText,
    'latency_ms': latencyMs,
    'model_bundle_used': modelBundleUsed,
    'error': error,
  };

  factory VisionResult.fromJson(Map<String, dynamic> json) => VisionResult(
    requestId: json['request_id'] as String,
    taskType: ImageTaskType.values.byName(json['task_type'] as String),
    imageMetadata: ImageMetadata(
      width: json['image_metadata']['width'] as int,
      height: json['image_metadata']['height'] as int,
      format: json['image_metadata']['format'] as String?,
      orientation: json['image_metadata']['orientation'] as int?,
    ),
    classifications: json['classifications'] != null
        ? (json['classifications'] as List)
              .map(
                (e) => ClassificationResult.fromJson(e as Map<String, dynamic>),
              )
              .toList()
        : null,
    detections: json['detections'] != null
        ? (json['detections'] as List)
              .map((e) => DetectionResult.fromJson(e as Map<String, dynamic>))
              .toList()
        : null,
    textBlocks: json['text_blocks'] != null
        ? (json['text_blocks'] as List)
              .map((e) => TextRegion.fromJson(e as Map<String, dynamic>))
              .toList()
        : null,
    captionText: json['caption_text'] as String?,
    latencyMs: json['latency_ms'] as int,
    modelBundleUsed: json['model_bundle_used'] != null
        ? (json['model_bundle_used'] as List).cast<String>()
        : null,
    error: json['error'] as String?,
  );
}

/// Image classification request
class ImageClassificationRequest extends ImageTaskRequest {
  final int topK;
  final double? confidenceThreshold;

  ImageClassificationRequest({
    required super.requestId,
    required super.imageData,
    required super.metadata,
    this.topK = 5,
    this.confidenceThreshold,
    super.options,
    super.modelPath,
  }) : super(taskType: ImageTaskType.imageClassification);

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'top_k': topK,
    'confidence_threshold': confidenceThreshold,
  };
}

/// Object detection request
class ObjectDetectionRequest extends ImageTaskRequest {
  final double? confidenceThreshold;
  final double? nmsThreshold;
  final List<String>? targetClasses;

  ObjectDetectionRequest({
    required super.requestId,
    required super.imageData,
    required super.metadata,
    this.confidenceThreshold,
    this.nmsThreshold,
    this.targetClasses,
    super.options,
    super.modelPath,
  }) : super(taskType: ImageTaskType.objectDetection);
}

/// OCR request
class OcrRequest extends ImageTaskRequest {
  final String? languageHint;
  final bool detectOrientation;

  OcrRequest({
    required super.requestId,
    required super.imageData,
    required super.metadata,
    this.languageHint,
    this.detectOrientation = true,
    super.options,
    super.modelPath,
  }) : super(taskType: ImageTaskType.ocr);
}

/// Image caption request
class ImageCaptionRequest extends ImageTaskRequest {
  final String? style; // 'detailed', 'concise', 'creative'
  final int? maxLength;

  ImageCaptionRequest({
    required super.requestId,
    required super.imageData,
    required super.metadata,
    super.prompt,
    this.style,
    this.maxLength,
    super.options,
    super.modelPath,
  }) : super(taskType: ImageTaskType.imageCaption);
}

/// Multimodal chat request (image + text)
class MultimodalChatRequest extends ImageTaskRequest {
  final String textPrompt;
  final bool streamResponse;

  MultimodalChatRequest({
    required super.requestId,
    required super.imageData,
    required super.metadata,
    required this.textPrompt,
    this.streamResponse = true,
    super.options,
    super.modelPath,
  }) : super(taskType: ImageTaskType.multimodalChat, prompt: textPrompt);
}
