import 'package:flutter/services.dart';

class AudioToolsService {
  const AudioToolsService({
    MethodChannel channel = const MethodChannel('essential/audio_tools'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<String> normalizeToSpeechWav(
    String path, {
    Duration? maxDuration,
  }) async {
    final normalized = await _channel
        .invokeMethod<String>('normalizeToSpeechWav', <String, Object?>{
          'path': path,
          if (maxDuration != null) 'maxDurationMs': maxDuration.inMilliseconds,
        });
    return normalized ?? path;
  }

  Future<String> preprocessForMeeting(
    String path, {
    bool voiceEnhancement = true,
    bool noiseReduction = true,
  }) async {
    final processed = await _channel
        .invokeMethod<String>('preprocessForMeeting', <String, Object?>{
          'path': path,
          'voiceEnhancement': voiceEnhancement,
          'noiseReduction': noiseReduction,
        });
    return processed ?? path;
  }

  Future<List<String>> splitSpeechWav(
    String path, {
    Duration chunkDuration = const Duration(minutes: 5),
  }) async {
    final response = await _channel.invokeMethod<List<Object?>>(
      'splitSpeechWav',
      <String, Object?>{
        'path': path,
        'chunkDurationMs': chunkDuration.inMilliseconds,
      },
    );
    return (response ?? const <Object?>[])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, Object?>> analyzeAudio(String path) async {
    final response = await _channel.invokeMethod<Map<Object?, Object?>>(
      'analyzeAudio',
      <String, Object?>{'path': path},
    );
    return Map<String, Object?>.from(response ?? const <Object?, Object?>{});
  }

  Future<List<Map<String, Object?>>> detectSilenceRegions(String path) async {
    final response = await _channel.invokeMethod<List<Object?>>(
      'detectSilenceRegions',
      <String, Object?>{'path': path},
    );
    return (response ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}
