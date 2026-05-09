import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../features/model_management/model_management_models.dart';
import 'anonymous_telemetry_controller.dart';
import 'app_preferences_controller.dart';

enum DeviceThermalState { unknown, nominal, fair, serious, critical }

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.platform,
    required this.thermalState,
    this.totalRamMb,
    this.availableRamMb,
    this.lowRamDevice = false,
    this.isLowPowerMode = false,
    this.batteryLevel,
    this.isCharging = false,
    this.temperatureC,
  });

  const DeviceSnapshot.unknown()
    : platform = 'unknown',
      thermalState = DeviceThermalState.unknown,
      totalRamMb = null,
      availableRamMb = null,
      lowRamDevice = false,
      isLowPowerMode = false,
      batteryLevel = null,
      isCharging = false,
      temperatureC = null;

  final String platform;
  final int? totalRamMb;
  final int? availableRamMb;
  final bool lowRamDevice;
  final bool isLowPowerMode;
  final double? batteryLevel;
  final bool isCharging;
  final double? temperatureC;
  final DeviceThermalState thermalState;

  bool get isMemoryConstrained =>
      lowRamDevice || (totalRamMb != null && totalRamMb! <= 4096);

  bool get isBatteryConstrained =>
      isLowPowerMode ||
      (!isCharging && batteryLevel != null && batteryLevel! <= 0.2);

  factory DeviceSnapshot.fromMap(Map<Object?, Object?> map) {
    return DeviceSnapshot(
      platform: map['platform'] as String? ?? 'unknown',
      totalRamMb: map['totalRamMb'] as int?,
      availableRamMb: map['availableRamMb'] as int?,
      lowRamDevice: map['lowRamDevice'] as bool? ?? false,
      isLowPowerMode: map['isLowPowerMode'] as bool? ?? false,
      batteryLevel: (map['batteryLevel'] as num?)?.toDouble(),
      isCharging: map['isCharging'] as bool? ?? false,
      temperatureC: (map['temperatureC'] as num?)?.toDouble(),
      thermalState: _thermalStateFromRaw(map['thermalState'] as String?),
    );
  }

  static DeviceThermalState _thermalStateFromRaw(String? raw) {
    return switch (raw) {
      'nominal' => DeviceThermalState.nominal,
      'fair' => DeviceThermalState.fair,
      'serious' => DeviceThermalState.serious,
      'critical' => DeviceThermalState.critical,
      _ => DeviceThermalState.unknown,
    };
  }
}

class DeviceStateService {
  static const MethodChannel _channel = MethodChannel('essential/device_state');

  Future<DeviceSnapshot> getSnapshot() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getSnapshot',
      );
      if (result == null) {
        return const DeviceSnapshot.unknown();
      }
      return DeviceSnapshot.fromMap(result);
    } on MissingPluginException {
      return const DeviceSnapshot.unknown();
    } on PlatformException {
      return const DeviceSnapshot.unknown();
    }
  }
}

class ModelRecommendation {
  const ModelRecommendation({
    required this.label,
    required this.reason,
    required this.recommended,
    required this.shouldWarn,
  });

  final String label;
  final String reason;
  final bool recommended;
  final bool shouldWarn;
}

class PreflightDecision {
  const PreflightDecision({
    required this.blocked,
    required this.message,
    required this.maxTokens,
    this.suggestedFallbackModelId,
    this.suggestedFallbackModelName,
    this.shouldSuggestFallback = false,
  });

  final bool blocked;
  final String message;
  final int maxTokens;
  final String? suggestedFallbackModelId;
  final String? suggestedFallbackModelName;
  final bool shouldSuggestFallback;
}

class RuntimeHealthController extends ChangeNotifier {
  RuntimeHealthController({
    required AppPreferencesController preferencesController,
    required AnonymousTelemetryController telemetryController,
    DeviceStateService? deviceStateService,
  }) : _preferencesController = preferencesController,
       _telemetryController = telemetryController,
       _deviceStateService = deviceStateService ?? DeviceStateService();

  final AppPreferencesController _preferencesController;
  final AnonymousTelemetryController _telemetryController;
  final DeviceStateService _deviceStateService;

  DeviceSnapshot _snapshot = const DeviceSnapshot.unknown();
  final List<DateTime> _recentInferenceStarts = <DateTime>[];
  bool _initialized = false;

  DeviceSnapshot get snapshot => _snapshot;

  AnonymousTelemetryController get telemetryController => _telemetryController;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _telemetryController.load(
      enabled: _preferencesController.telemetryEnabled,
    );
    await refreshDeviceSnapshot();
    _initialized = true;
  }

  Future<void> syncTelemetryConsent() {
    return _telemetryController.updateConsent(
      _preferencesController.telemetryEnabled,
    );
  }

  Future<void> refreshDeviceSnapshot() async {
    _snapshot = await _deviceStateService.getSnapshot();
    await _telemetryController.recordCompatibility(_snapshot);
    notifyListeners();
  }

  int get recentInferenceCount {
    _pruneHistory();
    return _recentInferenceStarts.length;
  }

  void markInferenceStart() {
    _recentInferenceStarts.add(DateTime.now());
    _pruneHistory();
    notifyListeners();
  }

  Future<void> markInferenceFinished({
    required Duration latency,
    required bool recoveredRuntime,
    required bool lowMemoryFallbackSuggested,
  }) async {
    await _telemetryController.recordInference(
      latency: latency,
      snapshot: _snapshot,
      recoveredRuntime: recoveredRuntime,
      lowMemoryFallbackSuggested: lowMemoryFallbackSuggested,
    );
    notifyListeners();
  }

  ModelRecommendation recommendationFor(ModelCatalogEntry entry) {
    final totalRamMb = _snapshot.totalRamMb;
    if (totalRamMb == null) {
      if (entry.recommendedRamMb <= 4096) {
        return ModelRecommendation(
          label: _text('軽量推奨', 'Lightweight recommended'),
          reason: _text(
            '端末情報が未取得でも導入しやすい構成です。',
            'This setup is easy to install even before device details are available.',
          ),
          recommended: true,
          shouldWarn: false,
        );
      }
      return ModelRecommendation(
        label: _text('要確認', 'Check first'),
        reason: _text(
          '端末 RAM 情報を取得できないため、慎重な導入が必要です。',
          'RAM information is unavailable, so install this carefully.',
        ),
        recommended: false,
        shouldWarn: true,
      );
    }

    final stronglyRecommended =
        entry.recommendedRamMb <= totalRamMb - 1024 &&
        (!_snapshot.isLowPowerMode || entry.recommendedRamMb <= 4096);
    if (stronglyRecommended) {
      return ModelRecommendation(
        label: _text('この端末に推奨', 'Recommended for this device'),
        reason: _text(
          'RAM 余裕があり、安定運用しやすいモデルです。',
          'This model has enough RAM headroom for stable use.',
        ),
        recommended: true,
        shouldWarn: false,
      );
    }

    if (entry.recommendedRamMb <= totalRamMb &&
        !_snapshot.isMemoryConstrained) {
      return ModelRecommendation(
        label: _text('利用可能', 'Available'),
        reason: _text(
          '動作見込みはありますが、長時間推論では負荷が上がる場合があります。',
          'This should run, but long sessions may increase device load.',
        ),
        recommended: false,
        shouldWarn: false,
      );
    }

    return ModelRecommendation(
      label: _text('低RAM注意', 'Low RAM warning'),
      reason: _text(
        'この端末では軽量モデルのほうが安定します。',
        'A lighter model will be more stable on this device.',
      ),
      recommended: false,
      shouldWarn: true,
    );
  }

  String _text(String japanese, String english) {
    return _preferencesController.useEnglish ? english : japanese;
  }

  PreflightDecision buildPreflightDecision({
    required String currentModelId,
    required int baseMaxTokens,
    required List<ModelCatalogEntry> catalog,
    required List<InstalledModelRecord> installedModels,
    int? currentModelSizeBytes,
  }) {
    final fallback = pickFallbackInstalledModel(
      currentModelId: currentModelId,
      catalog: catalog,
      installedModels: installedModels,
    );

    if (_snapshot.thermalState == DeviceThermalState.critical) {
      return PreflightDecision(
        blocked: true,
        message: '端末温度が高いため推論を一時停止しました。少し冷ましてから再開してください。',
        maxTokens: 64,
        suggestedFallbackModelId: fallback?.modelId,
        suggestedFallbackModelName: fallback?.displayName,
        shouldSuggestFallback: fallback != null,
      );
    }

    if (recentInferenceCount >= 4 &&
        _snapshot.thermalState.index >= DeviceThermalState.serious.index) {
      return PreflightDecision(
        blocked: true,
        message: '連続推論回数が多く、発熱を検知しました。少し待ってから再試行してください。',
        maxTokens: 64,
        suggestedFallbackModelId: fallback?.modelId,
        suggestedFallbackModelName: fallback?.displayName,
        shouldSuggestFallback: fallback != null,
      );
    }

    final availableRamMb = _snapshot.availableRamMb;
    final currentModelSizeMb = currentModelSizeBytes == null
        ? null
        : (currentModelSizeBytes / (1024 * 1024)).ceil();
    final estimatedRequiredRamMb = currentModelSizeMb == null
        ? null
        : currentModelSizeMb + (currentModelSizeMb >= 300 ? 1024 : 256);
    if (currentModelSizeMb != null &&
        currentModelSizeMb >= 300 &&
        _snapshot.isMemoryConstrained) {
      return PreflightDecision(
        blocked: true,
        message: 'この端末では大きなモデルの初回応答が遅くなるため開始しません。軽量モデルへ切り替えてください。',
        maxTokens: 32,
        suggestedFallbackModelId: fallback?.modelId,
        suggestedFallbackModelName: fallback?.displayName,
        shouldSuggestFallback: fallback != null,
      );
    }
    if (availableRamMb != null &&
        availableRamMb < 768 &&
        (estimatedRequiredRamMb == null ||
            availableRamMb < 384 ||
            estimatedRequiredRamMb > availableRamMb)) {
      return PreflightDecision(
        blocked: true,
        message: '空きメモリが少ないため、大きなモデルは開始しません。軽量モデルへの切り替えを提案します。',
        maxTokens: 64,
        suggestedFallbackModelId: fallback?.modelId,
        suggestedFallbackModelName: fallback?.displayName,
        shouldSuggestFallback: fallback != null,
      );
    }

    var maxTokens = baseMaxTokens;
    if (_snapshot.isLowPowerMode) {
      maxTokens = maxTokens.clamp(1, 128);
    }
    if (_snapshot.isMemoryConstrained) {
      maxTokens = maxTokens.clamp(1, 160);
    }
    if (_snapshot.thermalState == DeviceThermalState.fair) {
      maxTokens = maxTokens.clamp(1, 160);
    }
    if (_snapshot.thermalState == DeviceThermalState.serious) {
      maxTokens = maxTokens.clamp(1, 96);
    }
    if (recentInferenceCount >= 3) {
      maxTokens = maxTokens.clamp(1, 128);
    }

    if (_snapshot.isBatteryConstrained &&
        fallback != null &&
        fallback.modelId != currentModelId) {
      return PreflightDecision(
        blocked: false,
        message: '省電力状態を検知しました。軽量モデルへ切り替えると安定しやすくなります。',
        maxTokens: maxTokens,
        suggestedFallbackModelId: fallback.modelId,
        suggestedFallbackModelName: fallback.displayName,
        shouldSuggestFallback: true,
      );
    }

    return PreflightDecision(
      blocked: false,
      message: '端末状態を確認し、推論を開始します。',
      maxTokens: maxTokens,
      suggestedFallbackModelId: fallback?.modelId,
      suggestedFallbackModelName: fallback?.displayName,
      shouldSuggestFallback: false,
    );
  }

  InstalledModelRecord? pickFallbackInstalledModel({
    required String currentModelId,
    required List<ModelCatalogEntry> catalog,
    required List<InstalledModelRecord> installedModels,
  }) {
    if (installedModels.isEmpty) {
      return null;
    }
    final catalogById = <String, ModelCatalogEntry>{
      for (final entry in catalog) entry.modelId: entry,
    };
    final candidates =
        installedModels
            .where((record) => record.modelId != currentModelId)
            .toList()
          ..sort((left, right) {
            final leftCatalog = catalogById[left.modelId];
            final rightCatalog = catalogById[right.modelId];
            final leftRam = leftCatalog?.recommendedRamMb ?? 1 << 30;
            final rightRam = rightCatalog?.recommendedRamMb ?? 1 << 30;
            if (leftRam != rightRam) {
              return leftRam.compareTo(rightRam);
            }
            return left.sizeBytes.compareTo(right.sizeBytes);
          });
    return candidates.isEmpty ? null : candidates.first;
  }

  Duration tokenPacingDelay() {
    if (_snapshot.thermalState == DeviceThermalState.serious) {
      return const Duration(milliseconds: 24);
    }
    if (_snapshot.thermalState == DeviceThermalState.fair ||
        recentInferenceCount >= 3) {
      return const Duration(milliseconds: 12);
    }
    return Duration.zero;
  }

  bool shouldPauseForThermal(DeviceSnapshot snapshot) {
    return snapshot.thermalState == DeviceThermalState.critical;
  }

  bool shouldCancelForMemory(DeviceSnapshot snapshot) {
    return snapshot.availableRamMb != null && snapshot.availableRamMb! < 384;
  }

  String deviceHealthLabel() {
    final memory = _snapshot.totalRamMb == null
        ? 'RAM 不明'
        : 'RAM ${_snapshot.totalRamMb} MB';
    final battery = _snapshot.batteryLevel == null
        ? 'Battery 不明'
        : 'Battery ${(_snapshot.batteryLevel! * 100).toStringAsFixed(0)}%';
    final thermal = switch (_snapshot.thermalState) {
      DeviceThermalState.nominal => '温度 安定',
      DeviceThermalState.fair => '温度 注意',
      DeviceThermalState.serious => '温度 高め',
      DeviceThermalState.critical => '温度 危険',
      DeviceThermalState.unknown => '温度 不明',
    };
    return '$memory / $battery / $thermal';
  }

  void _pruneHistory() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    _recentInferenceStarts.removeWhere((time) => time.isBefore(cutoff));
  }
}
