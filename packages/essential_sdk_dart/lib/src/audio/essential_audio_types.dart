import 'dart:typed_data';

enum EssentialAudioFormat { pcm16k, pcm22k, pcm44k, opus, aac }

enum EssentialAudioTaskType { stt, tts, voiceCommand, classification }

class EssentialAudioBufferData {
  const EssentialAudioBufferData({
    required this.samples,
    required this.sampleRate,
    this.channels = 1,
    this.format = EssentialAudioFormat.pcm16k,
  });

  final Float32List samples;
  final int sampleRate;
  final int channels;
  final EssentialAudioFormat format;
}

class EssentialSttSegmentData {
  const EssentialSttSegmentData({
    required this.text,
    required this.confidence,
    required this.startTime,
    required this.endTime,
    required this.isFinal,
  });

  final String text;
  final double confidence;
  final double startTime;
  final double endTime;
  final bool isFinal;
}

class EssentialTtsConfigData {
  const EssentialTtsConfigData({
    this.voiceId = 'default',
    this.speed = 1,
    this.pitch = 0,
    this.sampleRate = 22050,
  });

  final String voiceId;
  final double speed;
  final double pitch;
  final int sampleRate;
}

class EssentialSttResult {
  const EssentialSttResult({required this.text, required this.segments});

  final String text;
  final List<EssentialSttSegmentData> segments;
}

abstract class AudioTaskRequest {
  const AudioTaskRequest({
    required this.requestId,
    required this.taskType,
    this.modelPath,
  });

  final String requestId;
  final EssentialAudioTaskType taskType;
  final String? modelPath;
}

class SttTaskRequest extends AudioTaskRequest {
  const SttTaskRequest({
    required super.requestId,
    this.samples,
    this.audioFilePath,
    this.sampleRate = 16000,
    this.channels = 1,
    this.format = EssentialAudioFormat.pcm16k,
    this.language = 'auto',
    this.translate = false,
    super.modelPath,
  }) : super(taskType: EssentialAudioTaskType.stt);

  final Float32List? samples;
  final String? audioFilePath;
  final int sampleRate;
  final int channels;
  final EssentialAudioFormat format;
  final String language;
  final bool translate;
}

class TtsTaskRequest extends AudioTaskRequest {
  const TtsTaskRequest({
    required super.requestId,
    required this.text,
    this.config = const EssentialTtsConfigData(),
    super.modelPath,
  }) : super(taskType: EssentialAudioTaskType.tts);

  final String text;
  final EssentialTtsConfigData config;
}
