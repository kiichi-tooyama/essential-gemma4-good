import 'dart:typed_data';

import 'package:essential_sdk_dart/essential_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('multimodal integration contracts', () {
    test('image classification request can be routed', () {
      final request = ImageClassificationRequest(
        requestId: 'image-classification-1',
        imageData: Uint8List(4 * 4 * 3),
        metadata: ImageMetadata(width: 4, height: 4, format: 'rgb'),
      );

      final task = EssentialTaskRequest(
        id: request.requestId,
        taskType: EssentialTaskType.imageClassification,
        payload: EssentialImageTaskPayload(
          imageData: request.imageData,
          metadata: request.metadata,
        ),
      );

      expect(task.taskType, EssentialTaskType.imageClassification);
      expect((task.payload as EssentialImageTaskPayload).metadata.width, 4);
    });

    test('object detection request preserves image metadata', () {
      final request = ObjectDetectionRequest(
        requestId: 'object-detection-1',
        imageData: Uint8List(8 * 8 * 3),
        metadata: ImageMetadata(width: 8, height: 8, format: 'rgb'),
        confidenceThreshold: 0.35,
      );

      expect(request.taskType, ImageTaskType.objectDetection);
      expect(request.metadata.height, 8);
      expect(request.confidenceThreshold, 0.35);
    });

    test('STT payload supports file and streaming forms', () {
      final fileRequest = SttTaskRequest(
        requestId: 'stt-file-1',
        audioFilePath: '/tmp/sample.wav',
        modelPath: '/system/android-speechrecognizer',
      );
      final streamPayload = EssentialAudioTaskPayload(
        samples: Float32List(16000),
        sampleRate: 16000,
      );

      expect(fileRequest.audioFilePath, endsWith('sample.wav'));
      expect(streamPayload.samples, hasLength(16000));
    });

    test('TTS payload carries text for synthesis', () {
      const request = TtsTaskRequest(
        requestId: 'tts-1',
        text: 'hello from essential',
        modelPath: '/models/tts.onnx',
      );
      final payload = EssentialTtsTaskPayload(text: request.text);

      expect(request.taskType, EssentialAudioTaskType.tts);
      expect(payload.text, contains('essential'));
    });

    test('multimodal chat combines image and text', () {
      final request = MultimodalChatRequest(
        requestId: 'mm-chat-1',
        imageData: Uint8List(12),
        metadata: ImageMetadata(width: 2, height: 2, format: 'rgb'),
        textPrompt: 'What is in this image?',
      );

      expect(request.taskType, ImageTaskType.multimodalChat);
      expect(request.textPrompt, startsWith('What'));
      expect(request.imageData, isNotEmpty);
    });

    test('generate request preserves media and reference documents', () {
      const request = EssentialGenerateRequest(
        prompt: 'この商品のFAQチャット用に答えて',
        systemInstruction: '参照資料を優先して回答する',
        attachments: <EssentialInputAttachment>[
          EssentialInputAttachment.imageFile(
            '/tmp/product.jpg',
            name: 'product-photo',
            mimeType: 'image/jpeg',
          ),
          EssentialInputAttachment.url(
            'https://example.com/product',
            name: 'product-page',
          ),
        ],
        referenceDocuments: <EssentialReferenceDocument>[
          EssentialReferenceDocument(
            title: '商品仕様',
            text: '容量は500ml。保証期間は1年。',
            uri: 'https://example.com/spec',
          ),
        ],
      );

      expect(request.systemInstruction, contains('参照資料'));
      expect(request.attachments.first.kind, EssentialInputKind.image);
      expect(request.attachments.last.kind, EssentialInputKind.url);
      expect(request.referenceDocuments.single.title, '商品仕様');
    });

    test('generate request exposes runtime customization options', () {
      const request = EssentialGenerateRequest(
        prompt: 'Summarize this voice note and speak the answer.',
        attachments: <EssentialInputAttachment>[
          EssentialInputAttachment.audioFile(
            '/tmp/voice.wav',
            name: 'voice-note',
          ),
          EssentialInputAttachment.imageFile('/tmp/photo.jpg', name: 'photo'),
        ],
        runtimeOptions: EssentialRuntimeOptions(
          preferredModelId: 'gemma-4-e2b-litertlm-it',
          webSearchEnabled: true,
          locationEnabled: false,
          sharedMemoryReadEnabled: true,
          sharedMemoryWriteEnabled: false,
          spokenOutputEnabled: true,
        ),
      );

      expect(request.attachments.map((item) => item.kind), [
        EssentialInputKind.audio,
        EssentialInputKind.image,
      ]);
      expect(
        request.runtimeOptions.preferredModelId,
        'gemma-4-e2b-litertlm-it',
      );
      expect(request.runtimeOptions.webSearchEnabled, isTrue);
      expect(request.runtimeOptions.locationEnabled, isFalse);
      expect(request.runtimeOptions.sharedMemoryReadEnabled, isTrue);
      expect(request.runtimeOptions.sharedMemoryWriteEnabled, isFalse);
      expect(request.runtimeOptions.spokenOutputEnabled, isTrue);
    });

    test('multimodal task payload supports external normalized inputs', () {
      const payload = EssentialMultimodalTaskPayload(
        prompt: '資料と音声を踏まえて回答して',
        textInputs: <String>['外部で整形済みのOCRテキスト'],
        imagePaths: <String>['/tmp/screen.png'],
        audioPaths: <String>['/tmp/voice.wav'],
        urls: <String>['https://example.com/help'],
        referenceDocuments: <String, String>{'FAQ': '返品は30日以内。'},
      );

      expect(payload.imagePaths.single, endsWith('.png'));
      expect(payload.audioPaths.single, endsWith('.wav'));
      expect(payload.referenceDocuments['FAQ'], contains('30日'));
    });

    test(
      'vision facade forwards raw image payload and explicit model path',
      () async {
        final runtime = _RecordingRuntime();
        final facade = EssentialTaskRouterFacade(
          capabilityRegistry: EssentialCapabilityRegistry.defaultRegistry(),
          router: const EssentialTaskRouter(),
          runtimes: <EssentialRuntimeFamily, EssentialRuntime>{
            EssentialRuntimeFamily.onnx: runtime,
          },
        );

        await facade.initialize();
        final response = await facade.routeVisionTask(
          ImageClassificationRequest(
            requestId: 'vision-sdk-1',
            imageData: Uint8List(2 * 2 * 4),
            metadata: ImageMetadata(width: 2, height: 2, format: 'rgba'),
            modelPath: '/models/vision.onnx',
          ),
        );

        final payload =
            runtime.lastRequest!.payload as EssentialImageTaskPayload;
        expect(response.modelUsed, '/models/vision.onnx');
        expect(
          runtime.lastRequest!.modelRequirement.explicitModelPath,
          '/models/vision.onnx',
        );
        expect(payload.metadata.format, 'rgba');
        expect(payload.imageData, hasLength(16));
      },
    );
  });
}

final class _RecordingRuntime implements EssentialRuntime {
  EssentialTaskRequest? lastRequest;

  @override
  EssentialRuntimeFamily get family => EssentialRuntimeFamily.onnx;

  @override
  bool get isAvailable => true;

  @override
  Future<void> initialize() async {}

  @override
  String ensureRequestId(EssentialTaskRequest request) =>
      request.id ?? 'vision-sdk-1';

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async {
    lastRequest = request;
    return EssentialTaskResponse(
      requestId: request.id!,
      taskType: request.taskType,
      status: EssentialTaskStatus.completed,
      result: EssentialTaskResult(),
      runtimeFamily: family,
      capabilityId: decision.capability.capabilityId,
      modelUsed: request.modelRequirement.explicitModelPath ?? '',
    );
  }

  @override
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) async* {
    lastRequest = request;
    yield EssentialTaskEvent(
      requestId: request.id!,
      taskType: request.taskType,
      type: EssentialTaskEventType.completed,
      runtimeFamily: family,
      capabilityId: decision.capability.capabilityId,
    );
  }

  @override
  Future<void> cancel(String requestId) async {}

  @override
  Future<void> dispose() async {}
}
