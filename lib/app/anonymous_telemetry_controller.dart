import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'runtime_health_controller.dart';

class TelemetrySummary {
  const TelemetrySummary({
    required this.enabled,
    required this.downloadSuccessCount,
    required this.downloadFailureCount,
    required this.inferenceCount,
    required this.averageInferenceLatencyMs,
    required this.runtimeRecoveryCount,
    required this.lowMemoryFallbackCount,
    required this.compatibilityBuckets,
  });

  static const empty = TelemetrySummary(
    enabled: false,
    downloadSuccessCount: 0,
    downloadFailureCount: 0,
    inferenceCount: 0,
    averageInferenceLatencyMs: 0,
    runtimeRecoveryCount: 0,
    lowMemoryFallbackCount: 0,
    compatibilityBuckets: <String, int>{},
  );

  final bool enabled;
  final int downloadSuccessCount;
  final int downloadFailureCount;
  final int inferenceCount;
  final double averageInferenceLatencyMs;
  final int runtimeRecoveryCount;
  final int lowMemoryFallbackCount;
  final Map<String, int> compatibilityBuckets;

  TelemetrySummary copyWith({
    bool? enabled,
    int? downloadSuccessCount,
    int? downloadFailureCount,
    int? inferenceCount,
    double? averageInferenceLatencyMs,
    int? runtimeRecoveryCount,
    int? lowMemoryFallbackCount,
    Map<String, int>? compatibilityBuckets,
  }) {
    return TelemetrySummary(
      enabled: enabled ?? this.enabled,
      downloadSuccessCount: downloadSuccessCount ?? this.downloadSuccessCount,
      downloadFailureCount: downloadFailureCount ?? this.downloadFailureCount,
      inferenceCount: inferenceCount ?? this.inferenceCount,
      averageInferenceLatencyMs:
          averageInferenceLatencyMs ?? this.averageInferenceLatencyMs,
      runtimeRecoveryCount: runtimeRecoveryCount ?? this.runtimeRecoveryCount,
      lowMemoryFallbackCount:
          lowMemoryFallbackCount ?? this.lowMemoryFallbackCount,
      compatibilityBuckets: compatibilityBuckets ?? this.compatibilityBuckets,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'download_success_count': downloadSuccessCount,
      'download_failure_count': downloadFailureCount,
      'inference_count': inferenceCount,
      'average_inference_latency_ms': averageInferenceLatencyMs,
      'runtime_recovery_count': runtimeRecoveryCount,
      'low_memory_fallback_count': lowMemoryFallbackCount,
      'compatibility_buckets': compatibilityBuckets,
    };
  }

  factory TelemetrySummary.fromJson(Map<String, dynamic> json) {
    return TelemetrySummary(
      enabled: json['enabled'] as bool? ?? false,
      downloadSuccessCount: json['download_success_count'] as int? ?? 0,
      downloadFailureCount: json['download_failure_count'] as int? ?? 0,
      inferenceCount: json['inference_count'] as int? ?? 0,
      averageInferenceLatencyMs:
          (json['average_inference_latency_ms'] as num?)?.toDouble() ?? 0,
      runtimeRecoveryCount: json['runtime_recovery_count'] as int? ?? 0,
      lowMemoryFallbackCount: json['low_memory_fallback_count'] as int? ?? 0,
      compatibilityBuckets: Map<String, int>.from(
        json['compatibility_buckets'] as Map<String, dynamic>? ??
            <String, dynamic>{},
      ),
    );
  }
}

class AnonymousTelemetryController extends ChangeNotifier {
  File? _file;
  TelemetrySummary _summary = TelemetrySummary.empty;
  bool _loaded = false;

  TelemetrySummary get summary => _summary;

  bool get isLoaded => _loaded;

  Future<void> load({required bool enabled}) async {
    if (_loaded) {
      if (_summary.enabled != enabled) {
        _summary = _summary.copyWith(enabled: enabled);
        await _persist();
        notifyListeners();
      }
      return;
    }

    final directory = await getApplicationSupportDirectory();
    _file = File(path.join(directory.path, 'essential_telemetry.json'));

    if (await _file!.exists()) {
      final payload =
          jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      _summary = TelemetrySummary.fromJson(payload).copyWith(enabled: enabled);
    } else {
      _summary = TelemetrySummary.empty.copyWith(enabled: enabled);
      await _persist();
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> updateConsent(bool enabled) async {
    await load(enabled: enabled);
    if (_summary.enabled == enabled) {
      return;
    }
    _summary = _summary.copyWith(enabled: enabled);
    await _persist();
    notifyListeners();
  }

  Future<void> recordDownloadResult({
    required bool success,
    required DeviceSnapshot snapshot,
  }) async {
    if (!_summary.enabled) {
      return;
    }
    final nextBuckets = Map<String, int>.from(_summary.compatibilityBuckets);
    final key = _compatibilityKey(snapshot);
    nextBuckets[key] = (nextBuckets[key] ?? 0) + 1;
    _summary = _summary.copyWith(
      downloadSuccessCount: _summary.downloadSuccessCount + (success ? 1 : 0),
      downloadFailureCount: _summary.downloadFailureCount + (success ? 0 : 1),
      compatibilityBuckets: nextBuckets,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> recordInference({
    required Duration latency,
    required DeviceSnapshot snapshot,
    required bool recoveredRuntime,
    required bool lowMemoryFallbackSuggested,
  }) async {
    if (!_summary.enabled) {
      return;
    }
    final nextCount = _summary.inferenceCount + 1;
    final totalLatency =
        _summary.averageInferenceLatencyMs * _summary.inferenceCount +
        latency.inMilliseconds;
    final nextBuckets = Map<String, int>.from(_summary.compatibilityBuckets);
    final key = _compatibilityKey(snapshot);
    nextBuckets[key] = (nextBuckets[key] ?? 0) + 1;
    _summary = _summary.copyWith(
      inferenceCount: nextCount,
      averageInferenceLatencyMs: totalLatency / nextCount,
      runtimeRecoveryCount:
          _summary.runtimeRecoveryCount + (recoveredRuntime ? 1 : 0),
      lowMemoryFallbackCount:
          _summary.lowMemoryFallbackCount +
          (lowMemoryFallbackSuggested ? 1 : 0),
      compatibilityBuckets: nextBuckets,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> recordCompatibility(DeviceSnapshot snapshot) async {
    if (!_summary.enabled) {
      return;
    }
    final nextBuckets = Map<String, int>.from(_summary.compatibilityBuckets);
    final key = _compatibilityKey(snapshot);
    nextBuckets[key] = (nextBuckets[key] ?? 0) + 1;
    _summary = _summary.copyWith(compatibilityBuckets: nextBuckets);
    await _persist();
    notifyListeners();
  }

  String _compatibilityKey(DeviceSnapshot snapshot) {
    final ramBucket = switch (snapshot.totalRamMb) {
      null => 'unknown-ram',
      < 4096 => 'lt4gb',
      < 6144 => '4to6gb',
      < 8192 => '6to8gb',
      _ => '8gb-plus',
    };
    return '${snapshot.platform}-$ramBucket-${snapshot.thermalState.name}';
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_summary.toJson()));
  }
}
