import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/app_config.dart';
import '../../app/anonymous_telemetry_controller.dart';
import '../../app/runtime_health_controller.dart';
import 'download_manager.dart';
import 'huggingface_auth_service.dart';
import 'model_management_models.dart';
import 'registry_api_client.dart';
import 'storage_manager.dart';

class ModelManagementController extends ChangeNotifier {
  ModelManagementController({
    required RegistryApiClient registryApiClient,
    required StorageManager storageManager,
    required DownloadManager downloadManager,
    HuggingFaceAuthService? huggingFaceAuthService,
    AnonymousTelemetryController? telemetryController,
  }) : _registryApiClient = registryApiClient,
       _storageManager = storageManager,
       _downloadManager = downloadManager,
       _huggingFaceAuthService =
           huggingFaceAuthService ?? HuggingFaceAuthService(),
       _telemetryController = telemetryController;

  factory ModelManagementController.createDefault({
    AnonymousTelemetryController? telemetryController,
  }) {
    return ModelManagementController(
      registryApiClient: RegistryApiClient(),
      storageManager: StorageManager(),
      downloadManager: DownloadManager(),
      huggingFaceAuthService: HuggingFaceAuthService(),
      telemetryController: telemetryController,
    );
  }

  factory ModelManagementController.preview() {
    final controller = ModelManagementController(
      registryApiClient: RegistryApiClient(),
      storageManager: StorageManager(rootDirectory: Directory.systemTemp),
      downloadManager: DownloadManager(),
      huggingFaceAuthService: HuggingFaceAuthService(),
    );
    controller
      .._catalog = const <ModelCatalogEntry>[
        ModelCatalogEntry(
          modelId: 'essential-mini',
          displayName: 'Essential Mini',
          variantId: 'q4_k_m',
          version: '1.0.0',
          runtime: 'llama.cpp',
          minOsVersion: 'iOS 17 / Android 12',
          recommendedRamMb: 4096,
          diskSizeMb: 512,
          downloadSizeMb: 384,
          supportsAdapters: true,
          license: 'Apache-2.0',
          sha256: 'preview',
          signature: 'preview-signature',
          artifactId: 'essential-mini-q4',
          summary: '軽量な日本語向けチャットモデル',
        ),
        ModelCatalogEntry(
          modelId: 'essential-embed',
          displayName: 'Essential Embed',
          variantId: 'fp16',
          version: '1.2.0',
          runtime: 'onnx',
          minOsVersion: 'iOS 17 / Android 12',
          recommendedRamMb: 2048,
          diskSizeMb: 128,
          downloadSizeMb: 96,
          supportsAdapters: false,
          license: 'MIT',
          sha256: 'preview',
          signature: 'preview-signature',
          artifactId: 'essential-embed-fp16',
          summary: '検索・分類向け埋め込みモデル',
        ),
      ]
      .._installations = <String, InstalledModelRecord>{
        'essential-mini': InstalledModelRecord(
          modelId: 'essential-mini',
          displayName: 'Essential Mini',
          version: '1.0.0',
          activePath: '/preview/essential-mini.gguf',
          sizeBytes: 384 * 1024 * 1024,
          sha256: 'preview',
          isPinned: true,
          installedAt: DateTime(2026, 4, 26, 10),
          lastUsedAt: DateTime(2026, 4, 26, 11),
        ),
      }
      .._storageSnapshot = const StorageSnapshot(
        usedBytes: 384 * 1024 * 1024,
        quotaBytes: 512 * 1024 * 1024,
        installedCount: 1,
        sharedComponentCount: 1,
      )
      .._initialized = true;
    return controller;
  }

  final RegistryApiClient _registryApiClient;
  final StorageManager _storageManager;
  final DownloadManager _downloadManager;
  final HuggingFaceAuthService _huggingFaceAuthService;
  final AnonymousTelemetryController? _telemetryController;

  final Map<String, double> _downloadProgress = <String, double>{};
  final Map<String, double> _bundleDownloadProgress = <String, double>{};
  final Map<String, Map<String, double>> _bundleComponentProgress =
      <String, Map<String, double>>{};
  final Map<String, String> _modelErrors = <String, String>{};
  final Map<String, String> _bundleErrors = <String, String>{};
  final Set<String> _downloadingModelIds = <String>{};
  final Set<String> _downloadingBundleIds = <String>{};
  final Map<String, double> _adapterDownloadProgress = <String, double>{};
  final Map<String, String> _adapterErrors = <String, String>{};
  final Set<String> _downloadingAdapterIds = <String>{};

  var _initialized = false;
  var _isLoading = false;
  var _isOfflineMode = false;
  String? _catalogError;
  List<ModelCatalogEntry> _catalog = <ModelCatalogEntry>[];
  List<BundleCatalogEntry> _bundles = <BundleCatalogEntry>[];
  List<AdapterCatalogEntry> _adapters = <AdapterCatalogEntry>[];
  Map<String, InstalledModelRecord> _installations =
      <String, InstalledModelRecord>{};
  Map<String, InstalledBundleComponentRecord> _bundleComponents =
      <String, InstalledBundleComponentRecord>{};
  Map<String, InstalledBundleRecord> _bundleInstallations =
      <String, InstalledBundleRecord>{};
  Map<String, InstalledAdapterRecord> _adapterInstallations =
      <String, InstalledAdapterRecord>{};
  StorageSnapshot _storageSnapshot = StorageSnapshot.empty;

  bool get isInitialized => _initialized;

  bool get isLoading => _isLoading;

  bool get isOfflineMode => _isOfflineMode;

  String? get catalogError => _catalogError;

  List<ModelCatalogEntry> get catalog =>
      List<ModelCatalogEntry>.unmodifiable(_catalog);

  List<BundleCatalogEntry> get bundles =>
      List<BundleCatalogEntry>.unmodifiable(_bundles);

  List<AdapterCatalogEntry> get adapters =>
      List<AdapterCatalogEntry>.unmodifiable(_adapters);

  List<InstalledModelRecord> get installedModels {
    final models = _installations.values.toList()
      ..sort((left, right) {
        if (left.isPinned != right.isPinned) {
          return left.isPinned ? -1 : 1;
        }
        return right.installedAt.compareTo(left.installedAt);
      });
    return models;
  }

  List<InstalledAdapterRecord> installedAdaptersForModel(String modelId) {
    final adapters =
        _adapterInstallations.values
            .where((record) => record.baseModelId == modelId)
            .toList()
          ..sort(
            (left, right) => right.installedAt.compareTo(left.installedAt),
          );
    return List<InstalledAdapterRecord>.unmodifiable(adapters);
  }

  List<AdapterCatalogEntry> catalogAdaptersForModel(String modelId) {
    final entries =
        _adapters.where((entry) => entry.modelId == modelId).toList()..sort(
          (left, right) => left.displayName.compareTo(right.displayName),
        );
    return List<AdapterCatalogEntry>.unmodifiable(entries);
  }

  StorageSnapshot get storageSnapshot => _storageSnapshot;

  List<InstalledBundleRecord> get installedBundles {
    final bundles = _bundleInstallations.values.toList()
      ..sort((left, right) => right.installedAt.compareTo(left.installedAt));
    return List<InstalledBundleRecord>.unmodifiable(bundles);
  }

  bool isModelVisibleInSetup(String modelId) => _isSetupModelId(modelId);

  bool isBundleVisibleInSetup(BundleCatalogEntry entry) =>
      _isSetupBundle(entry);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await refreshCatalog();
  }

  ModelAvailabilityState stateFor(ModelCatalogEntry entry) {
    final installation = _installations[entry.modelId];
    final bundleComponent = _bundleComponents[entry.modelId];
    if (_isInstalledCatalogEntry(entry, installation, bundleComponent)) {
      _downloadingModelIds.remove(entry.modelId);
      _downloadProgress.remove(entry.modelId);
      return ModelAvailabilityState.available;
    }

    if (_downloadingModelIds.contains(entry.modelId)) {
      return ModelAvailabilityState.downloading;
    }

    if (installation == null) {
      return _modelErrors.containsKey(entry.modelId)
          ? ModelAvailabilityState.failed
          : ModelAvailabilityState.notInstalled;
    }

    if (installation.version != entry.version) {
      return ModelAvailabilityState.updateAvailable;
    }

    return ModelAvailabilityState.available;
  }

  double progressFor(String modelId) {
    return _downloadProgress[modelId] ?? 0;
  }

  double bundleProgressFor(String bundleId) {
    return _bundleDownloadProgress[bundleId] ?? 0;
  }

  Map<String, double> bundleComponentProgressFor(String bundleId) {
    return Map<String, double>.unmodifiable(
      _bundleComponentProgress[bundleId] ?? const <String, double>{},
    );
  }

  double adapterProgressFor(String adapterId) {
    return _adapterDownloadProgress[adapterId] ?? 0;
  }

  String? errorFor(String modelId) {
    return _modelErrors[modelId];
  }

  String? bundleErrorFor(String bundleId) {
    return _bundleErrors[bundleId];
  }

  String? adapterErrorFor(String adapterId) {
    return _adapterErrors[adapterId];
  }

  InstalledModelRecord? installationFor(String modelId) {
    return _installations[modelId];
  }

  InstalledAdapterRecord? adapterInstallationFor(String adapterId) {
    return _adapterInstallations[adapterId];
  }

  InstalledBundleRecord? bundleInstallationFor(String bundleId) {
    return _bundleInstallations[bundleId];
  }

  InstalledBundleComponentRecord? componentInstallationFor(String modelId) {
    return _bundleComponents[modelId];
  }

  bool isModelAvailableThroughBundle(String modelId) {
    return _installations[modelId] == null &&
        _bundleComponents[modelId] != null;
  }

  bool isAdapterDownloading(String adapterId) {
    return _downloadingAdapterIds.contains(adapterId);
  }

  bool isBundleDownloading(String bundleId) {
    return _downloadingBundleIds.contains(bundleId);
  }

  bool isBundleInstalled(String bundleId) {
    return _bundleInstallations.containsKey(bundleId);
  }

  bool isComponentShared(String modelId) {
    final record = _bundleComponents[modelId];
    return record != null && record.bundleIds.length > 1;
  }

  bool isAdapterCompatible(
    AdapterCatalogEntry entry,
    InstalledModelRecord? baseModel,
  ) {
    if (baseModel == null) {
      return false;
    }
    final variantCompatible =
        entry.compatibleVariantIds.isEmpty ||
        entry.compatibleVariantIds.contains(_extractVariant(baseModel));
    final quantizationCompatible =
        entry.compatibleQuantizations.isEmpty ||
        entry.compatibleQuantizations.contains(_extractVariant(baseModel));
    return entry.modelId == baseModel.modelId &&
        variantCompatible &&
        quantizationCompatible;
  }

  Future<void> refreshCatalog() async {
    _isLoading = true;
    _catalogError = null;
    notifyListeners();

    try {
      await _storageManager.initialize();
      _installations = await _storageManager.loadInstallations();
      _bundleComponents = await _storageManager
          .loadBundleComponentInstallations();
      _bundleInstallations = await _storageManager.loadBundleInstallations();
      _adapterInstallations = await _storageManager.loadAdapterInstallations();
      _clearCompletedModelDownloads();
      _catalog = _sortCatalog(await _registryApiClient.fetchCatalog());
      _bundles = _sortBundles(await _registryApiClient.fetchBundles());
      _adapters = await _registryApiClient.fetchAdapters();
      final prunedLegacyRecords = await _pruneRecordsMissingFromCatalog();
      if (prunedLegacyRecords) {
        await _storageManager.persistInstallations(
          _installations.values,
          _bundleComponents.values,
          _bundleInstallations.values,
          _adapterInstallations.values,
        );
      }
      _storageSnapshot = await _storageManager.buildSnapshot(
        _installations,
        _bundleComponents,
      );
      _isOfflineMode = false;
    } catch (error) {
      _isOfflineMode = _looksOffline(error);
      _catalogError = _formatCatalogError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _pruneRecordsMissingFromCatalog() async {
    var changed = false;
    final catalogModelIds = _catalog.map((entry) => entry.modelId).toSet();
    final bundleIds = _bundles.map((entry) => entry.bundleId).toSet();
    final bundleComponentModelIds = _bundles
        .expand((entry) => entry.nodes)
        .map((node) => node.modelId)
        .toSet();
    final adapterIds = _adapters.map((entry) => entry.adapterId).toSet();

    for (final modelId in _installations.keys.toList()) {
      if (!catalogModelIds.contains(modelId)) {
        await _storageManager.deleteInstalledModel(modelId);
        _installations.remove(modelId);
        changed = true;
      }
    }

    for (final componentId in _bundleComponents.keys.toList()) {
      if (!bundleComponentModelIds.contains(componentId)) {
        await _storageManager.deleteBundleComponent(componentId);
        _bundleComponents.remove(componentId);
        changed = true;
      }
    }

    for (final bundleId in _bundleInstallations.keys.toList()) {
      if (!bundleIds.contains(bundleId)) {
        await _storageManager.deleteBundleRecord(bundleId);
        _bundleInstallations.remove(bundleId);
        changed = true;
      }
    }

    for (final adapterId in _adapterInstallations.keys.toList()) {
      if (!adapterIds.contains(adapterId)) {
        final record = _adapterInstallations[adapterId];
        if (record != null) {
          await _storageManager.deleteInstalledAdapter(
            record.namespaceId,
            adapterId,
          );
        }
        _adapterInstallations.remove(adapterId);
        changed = true;
      }
    }

    return changed;
  }

  Future<void> downloadModel(ModelCatalogEntry entry) async {
    final bundleComponent = _bundleComponents[entry.modelId];
    if (_isInstalledCatalogEntry(
      entry,
      _installations[entry.modelId],
      bundleComponent,
    )) {
      _downloadingModelIds.remove(entry.modelId);
      _downloadProgress.remove(entry.modelId);
      _modelErrors.remove(entry.modelId);
      notifyListeners();
      return;
    }

    if (_downloadingModelIds.contains(entry.modelId)) {
      return;
    }

    _downloadingModelIds.add(entry.modelId);
    _downloadProgress[entry.modelId] = 0;
    _modelErrors.remove(entry.modelId);
    notifyListeners();

    File? stagedFile;

    try {
      final deletedModelIds = await _storageManager.ensureCapacityFor(
        entry.downloadSizeMb * 1024 * 1024,
        _installations,
        protectedModelIds: _downloadingModelIds,
      );
      for (final modelId in deletedModelIds) {
        _installations.remove(modelId);
      }

      final manifest = await _registryApiClient.fetchManifest(entry.modelId);
      final effectiveManifest = _effectiveModelManifestForHuggingFace(manifest);
      stagedFile = await _storageManager.prepareStagingFile(effectiveManifest);
      await _downloadArtifactFromBestSource(
        modelId: entry.modelId,
        artifactFileName: effectiveManifest.artifactFileName,
        destinationFile: stagedFile,
        expectedSha256: effectiveManifest.sha256,
        expectedSizeBytes: effectiveManifest.artifactSizeBytes,
        onProgress: (progress) {
          _downloadProgress[entry.modelId] = progress.fraction;
          notifyListeners();
        },
      );

      final installed = await _storageManager.activateModel(
        entry: entry,
        manifest: effectiveManifest,
        stagedFile: stagedFile,
        previousRecord: _installations[entry.modelId],
        isPinned: _installations[entry.modelId]?.isPinned ?? false,
      );
      _installations[entry.modelId] = installed;
      await _storageManager.persistInstallations(
        _installations.values,
        _bundleComponents.values,
        _bundleInstallations.values,
        _adapterInstallations.values,
      );
      _storageSnapshot = await _storageManager.buildSnapshot(
        _installations,
        _bundleComponents,
      );
      _isOfflineMode = false;
      await _recordDownloadTelemetry(success: true);
    } catch (error) {
      _isOfflineMode = _looksOffline(error);
      _modelErrors[entry.modelId] = error.toString();
      if (stagedFile != null) {
        final hasPartialDownload = await stagedFile.exists();
        if (!_looksOffline(error) || !hasPartialDownload) {
          await _storageManager.quarantineStagingFile(stagedFile);
        }
      }
      await _recordDownloadTelemetry(success: false);
    } finally {
      _downloadingModelIds.remove(entry.modelId);
      _downloadProgress.remove(entry.modelId);
      _storageSnapshot = await _storageManager.buildSnapshot(
        _installations,
        _bundleComponents,
      );
      notifyListeners();
    }
  }

  Future<void> downloadRecommended() async {
    if (!_initialized) {
      await initialize();
    }

    final preferredBundle =
        _bundles
            .where(_isSetupBundle)
            .where(
              (bundle) => !_bundleInstallations.containsKey(bundle.bundleId),
            )
            .where(
              (bundle) =>
                  bundle.taskProfiles.contains('MULTIMODAL_CHAT') ||
                  bundle.taskProfiles.contains('TEXT_GENERATION'),
            )
            .toList()
          ..sort(
            (left, right) =>
                left.recommendedRamMb.compareTo(right.recommendedRamMb),
          );
    if (preferredBundle.isNotEmpty) {
      await downloadBundle(preferredBundle.first);
      await _downloadCompatibleAdapters();
      return;
    }

    final preferredModels =
        _catalog
            .where((entry) => _isSetupModelId(entry.modelId))
            .where((entry) => !_installations.containsKey(entry.modelId))
            .toList()
          ..sort((left, right) {
            final adapterCompare = right.supportsAdapters.toString().compareTo(
              left.supportsAdapters.toString(),
            );
            if (adapterCompare != 0) {
              return adapterCompare;
            }
            return left.recommendedRamMb.compareTo(right.recommendedRamMb);
          });
    if (preferredModels.isNotEmpty) {
      await downloadModel(preferredModels.first);
    }
    await _downloadCompatibleAdapters();
  }

  Future<void> downloadHighAccuracyChat() async {
    if (!_initialized) {
      await initialize();
    }

    final e4bBundle = _firstOrNull(
      _bundles.where(
        (bundle) => _isSetupBundle(bundle) && _isGemmaE4bBundle(bundle),
      ),
    );
    if (e4bBundle != null &&
        !_bundleInstallations.containsKey(e4bBundle.bundleId)) {
      await downloadBundle(e4bBundle);
      await _downloadCompatibleAdapters();
      return;
    }

    final e4bModel = _firstOrNull(
      _catalog.where((entry) => entry.modelId == 'gemma-4-e4b-litertlm-it'),
    );
    if (e4bModel != null && !_installations.containsKey(e4bModel.modelId)) {
      await downloadModel(e4bModel);
    }
    await _downloadCompatibleAdapters();
  }

  Future<void> downloadEverything() async {
    if (!_initialized) {
      await initialize();
    }

    for (final entry in _catalog) {
      if (_isSetupModelId(entry.modelId) &&
          !_installations.containsKey(entry.modelId)) {
        await downloadModel(entry);
      }
    }
    for (final bundle in _bundles) {
      if (_isSetupBundle(bundle) &&
          !_bundleInstallations.containsKey(bundle.bundleId)) {
        await downloadBundle(bundle);
      }
    }
    await _downloadCompatibleAdapters();
  }

  Future<void> downloadBundle(BundleCatalogEntry entry) async {
    if (_downloadingBundleIds.contains(entry.bundleId)) {
      return;
    }

    _downloadingBundleIds.add(entry.bundleId);
    _bundleDownloadProgress[entry.bundleId] = 0;
    _bundleComponentProgress[entry.bundleId] = <String, double>{};
    _bundleErrors.remove(entry.bundleId);
    notifyListeners();

    try {
      final resolution = await _registryApiClient.resolveBundle(
        entry.bundleId,
        installedComponentIds: _bundleComponents.keys.toList(),
      );
      final manifest = await _registryApiClient.fetchBundleManifest(
        entry.bundleId,
      );

      final missingNodes = manifest.nodes
          .where(
            (BundleNode node) => resolution.missingNodes.contains(node.modelId),
          )
          .toList();
      final totalNodes = manifest.nodes
          .where((BundleNode node) => node.required)
          .length;
      var completedNodes = totalNodes - missingNodes.length;
      _bundleDownloadProgress[entry.bundleId] = totalNodes == 0
          ? 1
          : completedNodes / totalNodes;
      notifyListeners();

      for (final node in missingNodes) {
        final effectiveNode = _effectiveBundleNodeForHuggingFace(node);
        final stagedFile = await _storageManager.prepareBundleNodeStagingFile(
          effectiveNode,
        );
        try {
          await _downloadArtifactFromBestSource(
            modelId: effectiveNode.modelId,
            artifactFileName: effectiveNode.artifactFileName,
            destinationFile: stagedFile,
            expectedSha256: effectiveNode.sha256,
            expectedSizeBytes: effectiveNode.artifactSizeBytes,
            onProgress: (progress) {
              _bundleComponentProgress[entry.bundleId]![effectiveNode.modelId] =
                  progress.fraction;
              final aggregate = completedNodes + progress.fraction;
              _bundleDownloadProgress[entry.bundleId] = totalNodes == 0
                  ? 1
                  : (aggregate / totalNodes).clamp(0, 1);
              notifyListeners();
            },
          );
          final installed = await _storageManager.activateBundleComponent(
            bundleId: entry.bundleId,
            node: effectiveNode,
            stagedFile: stagedFile,
            previousRecord: _bundleComponents[effectiveNode.modelId],
          );
          _bundleComponents[effectiveNode.modelId] = installed;
          completedNodes += 1;
          _bundleComponentProgress[entry.bundleId]!.remove(
            effectiveNode.modelId,
          );
        } catch (error) {
          await _storageManager.quarantineStagingFile(stagedFile);
          rethrow;
        }
      }

      final installedBundle = await _storageManager.activateBundle(
        entry: entry,
        manifest: manifest,
        componentModelIds: manifest.nodes
            .where((BundleNode node) => node.required)
            .map((BundleNode node) => node.modelId)
            .toList(),
        previousRecord: _bundleInstallations[entry.bundleId],
      );
      _bundleInstallations[entry.bundleId] = installedBundle;
      await _storageManager.persistInstallations(
        _installations.values,
        _bundleComponents.values,
        _bundleInstallations.values,
        _adapterInstallations.values,
      );
      _storageSnapshot = await _storageManager.buildSnapshot(
        _installations,
        _bundleComponents,
      );
      _bundleDownloadProgress[entry.bundleId] = 1;
      _isOfflineMode = false;
      await _recordDownloadTelemetry(success: true);
    } catch (error) {
      _isOfflineMode = _looksOffline(error);
      _bundleErrors[entry.bundleId] = error.toString();
      await _recordDownloadTelemetry(success: false);
    } finally {
      _downloadingBundleIds.remove(entry.bundleId);
      _bundleComponentProgress.remove(entry.bundleId);
      notifyListeners();
    }
  }

  Future<void> downloadAdapter(AdapterCatalogEntry entry) async {
    if (_downloadingAdapterIds.contains(entry.adapterId)) {
      return;
    }

    final baseModel = _installations[entry.modelId];
    if (!isAdapterCompatible(entry, baseModel)) {
      _adapterErrors[entry.adapterId] = 'ベースモデルまたは量子化方式と互換性がありません。';
      notifyListeners();
      return;
    }

    _downloadingAdapterIds.add(entry.adapterId);
    _adapterDownloadProgress[entry.adapterId] = 0;
    _adapterErrors.remove(entry.adapterId);
    notifyListeners();

    File? stagedFile;

    try {
      final manifest = await _registryApiClient.fetchAdapterManifest(
        entry.adapterId,
      );
      stagedFile = await _storageManager.prepareAdapterStagingFile(manifest);
      await _downloadArtifactFromBestSource(
        modelId: entry.modelId,
        artifactFileName: manifest.artifactFileName,
        destinationFile: stagedFile,
        expectedSha256: manifest.sha256,
        expectedSizeBytes: manifest.artifactSizeBytes,
        onProgress: (progress) {
          _adapterDownloadProgress[entry.adapterId] = progress.fraction;
          notifyListeners();
        },
      );

      final installed = await _storageManager.activateAdapter(
        entry: entry,
        manifest: manifest,
        stagedFile: stagedFile,
        previousRecord: _adapterInstallations[entry.adapterId],
      );
      _adapterInstallations[entry.adapterId] = installed;
      await _storageManager.persistInstallations(
        _installations.values,
        _bundleComponents.values,
        _bundleInstallations.values,
        _adapterInstallations.values,
      );
      _isOfflineMode = false;
      await _recordDownloadTelemetry(success: true);
    } catch (error) {
      _isOfflineMode = _looksOffline(error);
      _adapterErrors[entry.adapterId] = error.toString();
      if (stagedFile != null) {
        await _storageManager.quarantineStagingFile(stagedFile);
      }
      await _recordDownloadTelemetry(success: false);
    } finally {
      _downloadingAdapterIds.remove(entry.adapterId);
      _adapterDownloadProgress.remove(entry.adapterId);
      notifyListeners();
    }
  }

  Future<void> _downloadArtifactFromBestSource({
    required String modelId,
    required String artifactFileName,
    required File destinationFile,
    required String expectedSha256,
    required int expectedSizeBytes,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final sources = <Uri>[
      ..._configuredHuggingFaceArtifactUris(artifactFileName),
      ..._directModelSourceUris(modelId),
    ];
    if (sources.isEmpty) {
      throw StateError(
        'No Hugging Face download source is configured for $modelId '
        '($artifactFileName). Upload this artifact to Hugging Face and set '
        'ESSENTIAL_HF_ARTIFACT_BASE_URL, or add an upstream Hugging Face URL.',
      );
    }
    Object? lastError;

    for (final source in sources) {
      try {
        await _downloadHuggingFaceArtifact(
          artifactUri: source,
          destinationFile: destinationFile,
          expectedSha256: expectedSha256,
          expectedSizeBytes: expectedSizeBytes,
          onProgress: onProgress,
        );
        return;
      } catch (error) {
        lastError = error;
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
      }
    }

    throw StateError('All download sources failed for $modelId: $lastError');
  }

  ModelManifest _effectiveModelManifestForHuggingFace(ModelManifest manifest) {
    final source = _directHuggingFaceArtifact(manifest.modelId);
    if (source == null) {
      return manifest;
    }
    return ModelManifest(
      modelId: manifest.modelId,
      version: manifest.version,
      artifactId: manifest.artifactId,
      artifactFileName: manifest.artifactFileName,
      artifactSizeBytes: source.sizeBytes,
      sha256: source.sha256,
      downloadPath: manifest.downloadPath,
      signature: manifest.signature,
    );
  }

  BundleNode _effectiveBundleNodeForHuggingFace(BundleNode node) {
    final source = _directHuggingFaceArtifact(node.modelId);
    if (source == null) {
      return node;
    }
    return BundleNode(
      nodeId: node.nodeId,
      modelId: node.modelId,
      type: node.type,
      runtime: node.runtime,
      format: node.format,
      artifactId: node.artifactId,
      artifactFileName: node.artifactFileName,
      artifactSizeBytes: source.sizeBytes,
      sha256: source.sha256,
      downloadPath: node.downloadPath,
      modality: node.modality,
      compatibleWith: node.compatibleWith,
      required: node.required,
    );
  }

  Future<void> _downloadHuggingFaceArtifact({
    required Uri artifactUri,
    required File destinationFile,
    required String expectedSha256,
    required int expectedSizeBytes,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final publicCode = await _huggingFaceAuthService.responseCode(artifactUri);
    if (publicCode == HttpStatus.ok ||
        publicCode == HttpStatus.partialContent) {
      await _downloadManager.downloadArtifact(
        artifactUri: artifactUri,
        destinationFile: destinationFile,
        expectedSha256: expectedSha256,
        expectedSizeBytes: expectedSizeBytes,
        onProgress: onProgress,
      );
      return;
    }
    if (publicCode != HttpStatus.unauthorized &&
        publicCode != HttpStatus.forbidden) {
      throw HttpException(
        'Hugging Face download check failed ($publicCode).',
        uri: artifactUri,
      );
    }

    final token = await _huggingFaceAuthService.ensureAccessToken();
    final authedCode = await _huggingFaceAuthService.responseCode(
      artifactUri,
      accessToken: token,
    );
    if (authedCode == HttpStatus.forbidden) {
      await _huggingFaceAuthService.openModelPage(artifactUri);
      throw StateError(
        'Hugging Face blocked this model download. Accept the model license '
        'or access request in the browser, then retry.',
      );
    }
    if (authedCode != HttpStatus.ok &&
        authedCode != HttpStatus.partialContent) {
      throw HttpException(
        'Hugging Face authenticated download check failed ($authedCode).',
        uri: artifactUri,
      );
    }

    await _downloadManager.downloadArtifact(
      artifactUri: artifactUri,
      destinationFile: destinationFile,
      expectedSha256: expectedSha256,
      expectedSizeBytes: expectedSizeBytes,
      authorizationBearerToken: token,
      onProgress: onProgress,
    );
  }

  List<Uri> _directModelSourceUris(String modelId) {
    final source = _directHuggingFaceArtifact(modelId);
    return source == null ? const <Uri>[] : <Uri>[source.uri];
  }

  List<Uri> _configuredHuggingFaceArtifactUris(String artifactFileName) {
    final baseUrl = AppConfig.huggingFaceArtifactBaseUrl.trim();
    if (baseUrl.isEmpty || artifactFileName.trim().isEmpty) {
      return const <Uri>[];
    }
    final normalized = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return <Uri>[
      Uri.parse(normalized).resolve(Uri.encodeComponent(artifactFileName)),
    ];
  }

  _HuggingFaceArtifact? _directHuggingFaceArtifact(String modelId) {
    return switch (modelId) {
      'gemma-4-e2b-litertlm-it' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
        ),
        sizeBytes: 2588147712,
        sha256:
            '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
      ),
      'gemma-4-e4b-litertlm-it' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
        ),
        sizeBytes: 3659530240,
        sha256:
            '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
      ),
      'essential-mini' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
        ),
        sizeBytes: 668788096,
        sha256:
            '9fecc3b3cd76bba89d504f29b616eedf7da85b96540e490ca5824d3f7d2776a0',
      ),
      'gemma-4-e2b-it' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/s3dev-ai/gemma-4-E2B-it-gguf/resolve/main/gemma-4-E2B-it-Q2_K.gguf',
        ),
        sizeBytes: 2989081280,
        sha256:
            '844bb4f29ce207a7add67ea107042e5b533d367aa8dcdaf9e4e3bfb27a92168e',
      ),
      'gemma-4-e4b-it' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/sunil-pathak/gemma-4-E4B-it-Q4_K_M/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf',
        ),
        sizeBytes: 5335289856,
        sha256:
            '846a7f692a2aa5ccb09eab3a5f909b5485dd5ead506078614f65bd71ed824593',
      ),
      'whisper-tiny' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
        ),
        sizeBytes: 77691713,
        sha256:
            'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
      ),
      'whisper-base' => _HuggingFaceArtifact(
        uri: Uri.parse(
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
        ),
        sizeBytes: 147951465,
        sha256:
            '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
      ),
      _ => null,
    };
  }

  Future<void> deleteModel(String modelId) async {
    if (_downloadingModelIds.contains(modelId)) {
      return;
    }

    _modelErrors.remove(modelId);
    await _storageManager.deleteInstalledModel(modelId);
    _installations.remove(modelId);
    final adaptersToDelete = _adapterInstallations.values
        .where((record) => record.baseModelId == modelId)
        .toList();
    for (final adapter in adaptersToDelete) {
      await _storageManager.deleteInstalledAdapter(
        adapter.namespaceId,
        adapter.adapterId,
      );
      _adapterInstallations.remove(adapter.adapterId);
    }
    await _storageManager.persistInstallations(
      _installations.values,
      _bundleComponents.values,
      _bundleInstallations.values,
      _adapterInstallations.values,
    );
    _storageSnapshot = await _storageManager.buildSnapshot(
      _installations,
      _bundleComponents,
    );
    notifyListeners();
  }

  Future<void> deleteAdapter(String adapterId) async {
    final record = _adapterInstallations[adapterId];
    if (record == null || _downloadingAdapterIds.contains(adapterId)) {
      return;
    }
    _adapterErrors.remove(adapterId);
    await _storageManager.deleteInstalledAdapter(record.namespaceId, adapterId);
    _adapterInstallations.remove(adapterId);
    await _storageManager.persistInstallations(
      _installations.values,
      _bundleComponents.values,
      _bundleInstallations.values,
      _adapterInstallations.values,
    );
    notifyListeners();
  }

  Future<void> deleteBundle(String bundleId) async {
    final bundle = _bundleInstallations[bundleId];
    if (bundle == null || _downloadingBundleIds.contains(bundleId)) {
      return;
    }

    for (final componentId in bundle.componentModelIds) {
      final record = _bundleComponents[componentId];
      if (record == null) {
        continue;
      }
      final remainingBundles = record.bundleIds
          .where((String id) => id != bundleId)
          .toList();
      if (remainingBundles.isEmpty) {
        await _storageManager.deleteBundleComponent(componentId);
        _bundleComponents.remove(componentId);
      } else {
        _bundleComponents[componentId] = record.copyWith(
          bundleIds: remainingBundles,
          lastUsedAt: DateTime.now(),
        );
      }
    }

    await _storageManager.deleteBundleRecord(bundleId);
    _bundleInstallations.remove(bundleId);
    await _storageManager.persistInstallations(
      _installations.values,
      _bundleComponents.values,
      _bundleInstallations.values,
      _adapterInstallations.values,
    );
    _storageSnapshot = await _storageManager.buildSnapshot(
      _installations,
      _bundleComponents,
    );
    notifyListeners();
  }

  Future<void> togglePin(String modelId) async {
    final record = _installations[modelId];
    if (record == null) {
      return;
    }

    _installations[modelId] = record.copyWith(
      isPinned: !record.isPinned,
      lastUsedAt: DateTime.now(),
    );
    await _storageManager.persistInstallations(
      _installations.values,
      _bundleComponents.values,
      _bundleInstallations.values,
      _adapterInstallations.values,
    );
    notifyListeners();
  }

  Future<void> markModelUsed(String modelId) async {
    final record = _installations[modelId];
    if (record == null) {
      return;
    }

    _installations[modelId] = record.copyWith(lastUsedAt: DateTime.now());
    await _storageManager.persistInstallations(
      _installations.values,
      _bundleComponents.values,
      _bundleInstallations.values,
      _adapterInstallations.values,
    );
    notifyListeners();
  }

  Future<void> markAdapterUsed(String adapterId) async {
    final record = _adapterInstallations[adapterId];
    if (record == null) {
      return;
    }
    _adapterInstallations[adapterId] = record.copyWith(
      lastUsedAt: DateTime.now(),
    );
    await _storageManager.persistInstallations(
      _installations.values,
      _bundleComponents.values,
      _bundleInstallations.values,
      _adapterInstallations.values,
    );
    notifyListeners();
  }

  Future<void> _downloadCompatibleAdapters() async {
    for (final adapter in _adapters) {
      if (_adapterInstallations.containsKey(adapter.adapterId)) {
        continue;
      }
      final baseModel = _installations[adapter.modelId];
      if (baseModel != null && isAdapterCompatible(adapter, baseModel)) {
        await downloadAdapter(adapter);
      }
    }
  }

  String _extractVariant(InstalledModelRecord record) {
    final normalized = record.activePath.toLowerCase();
    if (normalized.contains('q4')) {
      return 'q4_k_m';
    }
    if (normalized.contains('q5')) {
      return 'q5_k_m';
    }
    return record.version;
  }

  Future<bool> verifyModelIntegrity(String modelId) async {
    final record = _installations[modelId];
    if (record == null) {
      return false;
    }
    final isValid = await _downloadManager.verifyArtifactSha256(
      file: File(record.activePath),
      expectedSha256: record.sha256,
    );
    if (!isValid) {
      _modelErrors[modelId] = 'モデルファイル破損を検出しました。再ダウンロードを提案します。';
      notifyListeners();
    }
    return isValid;
  }

  bool _looksOffline(Object error) {
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error.toString().toLowerCase().contains('failed host lookup');
  }

  String _formatCatalogError(Object error) {
    if (_looksOffline(error)) {
      return 'Registry API に接続できませんでした: ${_registryApiClient.baseUrl}\n'
          'サーバーを起動するか、--dart-define=ESSENTIAL_REGISTRY_URL=http://<host>:8100 を指定してください。\n'
          '$error';
    }
    return error.toString();
  }

  Future<void> _recordDownloadTelemetry({required bool success}) async {
    final telemetry = _telemetryController;
    if (telemetry == null || !telemetry.summary.enabled) {
      return;
    }
    await telemetry.recordDownloadResult(
      success: success,
      snapshot: const DeviceSnapshot.unknown(),
    );
  }

  static List<ModelCatalogEntry> _sortCatalog(List<ModelCatalogEntry> entries) {
    return entries.toList()..sort((left, right) {
      final priority = _modelPriority(left).compareTo(_modelPriority(right));
      if (priority != 0) {
        return priority;
      }
      return left.displayName.compareTo(right.displayName);
    });
  }

  static int _modelPriority(ModelCatalogEntry entry) {
    if (entry.modelId == 'gemma-4-e4b-litertlm-it') {
      return 0;
    }
    if (entry.modelId == 'gemma-4-e2b-litertlm-it') {
      return 1;
    }
    if (_isGemmaE4bModel(entry)) {
      return 2;
    }
    if (entry.modelId == 'gemma-4-e2b-it') {
      return 3;
    }
    if (entry.modelId == 'essential-mini') {
      return 4;
    }
    return 10;
  }

  static List<BundleCatalogEntry> _sortBundles(
    List<BundleCatalogEntry> entries,
  ) {
    return entries.toList()..sort((left, right) {
      final priority = _bundlePriority(left).compareTo(_bundlePriority(right));
      if (priority != 0) {
        return priority;
      }
      return left.displayName.compareTo(right.displayName);
    });
  }

  static int _bundlePriority(BundleCatalogEntry entry) {
    if (entry.bundleId == 'essential-chat-gemma-4-e4b-litertlm-it-bundle') {
      return 0;
    }
    if (entry.bundleId == 'essential-chat-gemma-4-e2b-litertlm-it-bundle') {
      return 1;
    }
    if (_isGemmaE4bBundle(entry)) {
      return 2;
    }
    if (entry.bundleId.contains('e2b')) {
      return 3;
    }
    if (entry.bundleId.contains('lite')) {
      return 4;
    }
    return 10;
  }

  static bool _isGemmaE4bModel(ModelCatalogEntry entry) {
    return entry.modelId == 'gemma-4-e4b-litertlm-it';
  }

  static bool _isGemmaE4bBundle(BundleCatalogEntry entry) {
    return entry.bundleId == 'essential-chat-gemma-4-e4b-it-mobile-bundle' ||
        entry.nodes.any(
          (BundleNode node) => node.modelId == 'gemma-4-e4b-litertlm-it',
        );
  }

  static bool _isSetupModelId(String modelId) {
    return const <String>{
      'gemma-4-e2b-litertlm-it',
      'gemma-4-e4b-litertlm-it',
      'whisper-tiny',
      'whisper-base',
    }.contains(modelId);
  }

  static bool _isSetupBundle(BundleCatalogEntry entry) {
    return entry.bundleId == 'essential-chat-gemma-4-e2b-it-mobile-bundle' ||
        entry.bundleId == 'essential-chat-gemma-4-e4b-it-mobile-bundle';
  }

  void _clearCompletedModelDownloads() {
    for (final modelId in _bundleComponents.keys) {
      _downloadingModelIds.remove(modelId);
      _downloadProgress.remove(modelId);
      _modelErrors.remove(modelId);
    }
    for (final modelId in _installations.keys) {
      _downloadingModelIds.remove(modelId);
      _downloadProgress.remove(modelId);
      _modelErrors.remove(modelId);
    }
  }

  static bool _isInstalledCatalogEntry(
    ModelCatalogEntry entry,
    InstalledModelRecord? installation,
    InstalledBundleComponentRecord? bundleComponent,
  ) {
    if (installation != null) {
      return installation.version == entry.version;
    }
    if (bundleComponent == null) {
      return false;
    }
    if (bundleComponent.sha256 == entry.sha256) {
      return true;
    }
    final expectedSizeBytes = entry.downloadSizeMb * 1024 * 1024;
    return expectedSizeBytes > 0 &&
        bundleComponent.sizeBytes == expectedSizeBytes;
  }

  static T? _firstOrNull<T>(Iterable<T> items) {
    final iterator = items.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class _HuggingFaceArtifact {
  const _HuggingFaceArtifact({
    required this.uri,
    required this.sizeBytes,
    required this.sha256,
  });

  final Uri uri;
  final int sizeBytes;
  final String sha256;
}
