import 'essential_task_types.dart';

final class EssentialCapabilityDescriptor {
  const EssentialCapabilityDescriptor({
    required this.capabilityId,
    required this.supportedTaskTypes,
    required this.runtimeFamily,
    this.inputModalities = const <String>[],
    this.outputModalities = const <String>[],
    this.modelBundleRequirements = const <String>[],
    this.preprocessingProfile,
    this.postprocessingProfile,
    this.realtimeSupported = false,
    this.streamingSupported = false,
    this.adapterSupported = false,
    this.minOsVersion,
    this.minRamMb,
    this.acceleratorRequirements = const <String>[],
    this.permissionRequirements = const <String>[],
    this.qualityTier = 'balanced',
  });

  final String capabilityId;
  final List<EssentialTaskType> supportedTaskTypes;
  final EssentialRuntimeFamily runtimeFamily;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final List<String> modelBundleRequirements;
  final String? preprocessingProfile;
  final String? postprocessingProfile;
  final bool realtimeSupported;
  final bool streamingSupported;
  final bool adapterSupported;
  final String? minOsVersion;
  final int? minRamMb;
  final List<String> acceleratorRequirements;
  final List<String> permissionRequirements;
  final String qualityTier;

  bool supports(EssentialTaskType taskType) {
    return supportedTaskTypes.contains(taskType);
  }
}

final class EssentialCapabilityRegistry {
  EssentialCapabilityRegistry({
    Iterable<EssentialCapabilityDescriptor> descriptors =
        const <EssentialCapabilityDescriptor>[],
  }) : _descriptors = List<EssentialCapabilityDescriptor>.from(descriptors);

  final List<EssentialCapabilityDescriptor> _descriptors;

  List<EssentialCapabilityDescriptor> all() {
    return List<EssentialCapabilityDescriptor>.unmodifiable(_descriptors);
  }

  void register(EssentialCapabilityDescriptor descriptor) {
    _descriptors.add(descriptor);
  }

  void registerAll(Iterable<EssentialCapabilityDescriptor> descriptors) {
    _descriptors.addAll(descriptors);
  }

  List<EssentialCapabilityDescriptor> findByTaskType(
    EssentialTaskType taskType,
  ) {
    return _descriptors
        .where((descriptor) => descriptor.supports(taskType))
        .toList(growable: false);
  }

  List<EssentialCapabilityDescriptor> findByRuntime(
    EssentialRuntimeFamily family,
  ) {
    return _descriptors
        .where((descriptor) => descriptor.runtimeFamily == family)
        .toList(growable: false);
  }

  factory EssentialCapabilityRegistry.defaultRegistry() {
    return EssentialCapabilityRegistry(
      descriptors: const <EssentialCapabilityDescriptor>[
        EssentialCapabilityDescriptor(
          capabilityId: 'llm.text.chat',
          supportedTaskTypes: <EssentialTaskType>[
            EssentialTaskType.textGeneration,
            EssentialTaskType.locationContext,
            EssentialTaskType.mapReasoning,
          ],
          runtimeFamily: EssentialRuntimeFamily.llamaCpp,
          inputModalities: <String>['text', 'location'],
          outputModalities: <String>['text'],
          modelBundleRequirements: <String>['base', 'optional_adapter'],
          preprocessingProfile: 'prompt_assembly',
          postprocessingProfile: 'text_stream',
          streamingSupported: true,
          adapterSupported: true,
          qualityTier: 'high',
        ),
        EssentialCapabilityDescriptor(
          capabilityId: 'vision.classification.onnx',
          supportedTaskTypes: <EssentialTaskType>[
            EssentialTaskType.imageClassification,
          ],
          runtimeFamily: EssentialRuntimeFamily.onnx,
          inputModalities: <String>['image'],
          outputModalities: <String>['labels'],
          modelBundleRequirements: <String>['vision_encoder'],
          preprocessingProfile: 'image_tensor',
          postprocessingProfile: 'topk_labels',
        ),
        EssentialCapabilityDescriptor(
          capabilityId: 'vision.object_detection.onnx',
          supportedTaskTypes: <EssentialTaskType>[
            EssentialTaskType.objectDetection,
          ],
          runtimeFamily: EssentialRuntimeFamily.onnx,
          inputModalities: <String>['image'],
          outputModalities: <String>['boxes', 'labels'],
          modelBundleRequirements: <String>['detector'],
          preprocessingProfile: 'image_tensor',
          postprocessingProfile: 'detection_decode',
        ),
        EssentialCapabilityDescriptor(
          capabilityId: 'audio.stt.android_speech_recognizer',
          supportedTaskTypes: <EssentialTaskType>[EssentialTaskType.stt],
          runtimeFamily: EssentialRuntimeFamily.android,
          inputModalities: <String>['audio'],
          outputModalities: <String>['text'],
          modelBundleRequirements: <String>[],
          preprocessingProfile: 'android_speech_intent',
          postprocessingProfile: 'recognition_results',
          streamingSupported: true,
        ),
        EssentialCapabilityDescriptor(
          capabilityId: 'audio.stt.whisper_file',
          supportedTaskTypes: <EssentialTaskType>[EssentialTaskType.stt],
          runtimeFamily: EssentialRuntimeFamily.onnx,
          inputModalities: <String>['audio_file'],
          outputModalities: <String>['text'],
          modelBundleRequirements: <String>['whisper_base'],
          preprocessingProfile: 'speech_wav_16khz',
          postprocessingProfile: 'transcript_segments',
        ),
        EssentialCapabilityDescriptor(
          capabilityId: 'audio.tts.melotts',
          supportedTaskTypes: <EssentialTaskType>[EssentialTaskType.tts],
          runtimeFamily: EssentialRuntimeFamily.android,
          inputModalities: <String>['text'],
          outputModalities: <String>['audio'],
          modelBundleRequirements: <String>['melotts_en_jp'],
          preprocessingProfile: 'melotts_text',
          postprocessingProfile: 'waveform_decode',
        ),
      ],
    );
  }
}
