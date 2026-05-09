import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'model_management_models.dart';

class StorageManager {
  StorageManager({
    Directory? rootDirectory,
    this.quotaBytes = 64 * 1024 * 1024 * 1024,
  }) : _rootDirectoryOverride = rootDirectory;

  final Directory? _rootDirectoryOverride;
  final int quotaBytes;

  late final Directory _rootDirectory;
  late final Directory _activeDirectory;
  late final Directory _activeBundleComponentsDirectory;
  late final Directory _activeBundlesDirectory;
  late final Directory _activeAdaptersDirectory;
  late final Directory _stagingDirectory;
  late final Directory _failedDirectory;
  late final File _metadataFile;
  var _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final rootDirectory =
        _rootDirectoryOverride ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'essential_models',
          ),
        );

    _rootDirectory = rootDirectory;
    _activeDirectory = Directory(path.join(rootDirectory.path, 'active'));
    _activeBundleComponentsDirectory = Directory(
      path.join(rootDirectory.path, 'active_components'),
    );
    _activeBundlesDirectory = Directory(
      path.join(rootDirectory.path, 'active_bundles'),
    );
    _activeAdaptersDirectory = Directory(
      path.join(rootDirectory.path, 'active_adapters'),
    );
    _stagingDirectory = Directory(path.join(rootDirectory.path, 'staging'));
    _failedDirectory = Directory(path.join(rootDirectory.path, 'failed'));
    _metadataFile = File(path.join(rootDirectory.path, 'metadata.json'));

    await _rootDirectory.create(recursive: true);
    await _activeDirectory.create(recursive: true);
    await _activeBundleComponentsDirectory.create(recursive: true);
    await _activeBundlesDirectory.create(recursive: true);
    await _activeAdaptersDirectory.create(recursive: true);
    await _stagingDirectory.create(recursive: true);
    await _failedDirectory.create(recursive: true);

    if (!await _metadataFile.exists()) {
      await _metadataFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'installations': <dynamic>[],
          'bundle_components': <dynamic>[],
          'bundles': <dynamic>[],
          'adapters': <dynamic>[],
        }),
      );
    }
    await _importLocalDeviceSeeds();

    _initialized = true;
  }

  Future<Map<String, InstalledModelRecord>> loadInstallations() async {
    await initialize();
    final metadata =
        jsonDecode(await _metadataFile.readAsString()) as Map<String, dynamic>;
    final rows = metadata['installations'] as List<dynamic>? ?? <dynamic>[];
    return Map<String, InstalledModelRecord>.fromEntries(
      rows.map((dynamic row) {
        final record = InstalledModelRecord.fromJson(
          row as Map<String, dynamic>,
        );
        return MapEntry(record.modelId, record);
      }),
    );
  }

  Future<Map<String, InstalledAdapterRecord>> loadAdapterInstallations() async {
    await initialize();
    final metadata =
        jsonDecode(await _metadataFile.readAsString()) as Map<String, dynamic>;
    final rows = metadata['adapters'] as List<dynamic>? ?? <dynamic>[];
    return Map<String, InstalledAdapterRecord>.fromEntries(
      rows.map((dynamic row) {
        final record = InstalledAdapterRecord.fromJson(
          row as Map<String, dynamic>,
        );
        return MapEntry(record.adapterId, record);
      }),
    );
  }

  Future<Map<String, InstalledBundleComponentRecord>>
  loadBundleComponentInstallations() async {
    await initialize();
    final metadata =
        jsonDecode(await _metadataFile.readAsString()) as Map<String, dynamic>;
    final rows = metadata['bundle_components'] as List<dynamic>? ?? <dynamic>[];
    return Map<String, InstalledBundleComponentRecord>.fromEntries(
      rows.map((dynamic row) {
        final record = InstalledBundleComponentRecord.fromJson(
          row as Map<String, dynamic>,
        );
        return MapEntry(record.modelId, record);
      }),
    );
  }

  Future<Map<String, InstalledBundleRecord>> loadBundleInstallations() async {
    await initialize();
    final metadata =
        jsonDecode(await _metadataFile.readAsString()) as Map<String, dynamic>;
    final rows = metadata['bundles'] as List<dynamic>? ?? <dynamic>[];
    return Map<String, InstalledBundleRecord>.fromEntries(
      rows.map((dynamic row) {
        final record = InstalledBundleRecord.fromJson(
          row as Map<String, dynamic>,
        );
        return MapEntry(record.bundleId, record);
      }),
    );
  }

  Future<void> persistInstallations(
    Iterable<InstalledModelRecord> installations,
    Iterable<InstalledBundleComponentRecord> bundleComponents,
    Iterable<InstalledBundleRecord> bundles,
    Iterable<InstalledAdapterRecord> adapters,
  ) async {
    await initialize();
    final payload = <String, dynamic>{
      'installations': installations.map((record) => record.toJson()).toList(),
      'bundle_components': bundleComponents
          .map((record) => record.toJson())
          .toList(),
      'bundles': bundles.map((record) => record.toJson()).toList(),
      'adapters': adapters.map((record) => record.toJson()).toList(),
    };
    await _metadataFile.writeAsString(jsonEncode(payload));
  }

  Future<File> prepareStagingFile(ModelManifest manifest) async {
    await initialize();
    final directory = Directory(
      path.join(_stagingDirectory.path, manifest.modelId, manifest.version),
    );
    await directory.create(recursive: true);
    return File(path.join(directory.path, manifest.artifactFileName));
  }

  Future<File> prepareAdapterStagingFile(AdapterManifest manifest) async {
    await initialize();
    final directory = Directory(
      path.join(
        _stagingDirectory.path,
        'adapters',
        manifest.adapterId,
        manifest.version,
      ),
    );
    await directory.create(recursive: true);
    return File(path.join(directory.path, manifest.artifactFileName));
  }

  Future<File> prepareBundleNodeStagingFile(BundleNode node) async {
    await initialize();
    final directory = Directory(
      path.join(_stagingDirectory.path, 'bundle_nodes', node.modelId),
    );
    await directory.create(recursive: true);
    return File(path.join(directory.path, node.artifactFileName));
  }

  Future<List<String>> ensureCapacityFor(
    int requiredBytes,
    Map<String, InstalledModelRecord> currentInstallations, {
    Set<String> protectedModelIds = const <String>{},
  }) async {
    await initialize();
    await purgeFailedFiles();

    final usedBytes = await _directorySize(_rootDirectory);
    if (usedBytes + requiredBytes <= quotaBytes) {
      return <String>[];
    }

    final removable =
        currentInstallations.values
            .where(
              (record) =>
                  !record.isPinned &&
                  !protectedModelIds.contains(record.modelId),
            )
            .toList()
          ..sort((left, right) => left.lastUsedAt.compareTo(right.lastUsedAt));

    final deletedIds = <String>[];
    var reclaimedBytes = 0;

    for (final record in removable) {
      await deleteInstalledModel(record.modelId);
      deletedIds.add(record.modelId);
      reclaimedBytes += record.sizeBytes;
      if (usedBytes + requiredBytes - reclaimedBytes <= quotaBytes) {
        break;
      }
    }

    final hasCapacity =
        usedBytes + requiredBytes - reclaimedBytes <= quotaBytes;
    if (!hasCapacity) {
      throw StateError('Not enough storage capacity for this download.');
    }

    return deletedIds;
  }

  Future<void> purgeFailedFiles() async {
    await initialize();
    if (await _failedDirectory.exists()) {
      await _failedDirectory.delete(recursive: true);
    }
    await _failedDirectory.create(recursive: true);
  }

  Future<InstalledModelRecord> activateModel({
    required ModelCatalogEntry entry,
    required ModelManifest manifest,
    required File stagedFile,
    InstalledModelRecord? previousRecord,
    required bool isPinned,
  }) async {
    await initialize();

    final targetDirectory = Directory(
      path.join(_activeDirectory.path, entry.modelId, manifest.version),
    );
    await targetDirectory.create(recursive: true);

    final targetFile = File(
      path.join(targetDirectory.path, manifest.artifactFileName),
    );
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final activatedFile = await stagedFile.rename(targetFile.path);

    if (previousRecord != null &&
        previousRecord.activePath != activatedFile.path) {
      final previousFile = File(previousRecord.activePath);
      if (await previousFile.exists()) {
        await previousFile.delete();
      }
      await _deleteEmptyParents(previousFile.parent, _activeDirectory);
    }

    return InstalledModelRecord(
      modelId: entry.modelId,
      displayName: entry.displayName,
      version: manifest.version,
      activePath: activatedFile.path,
      sizeBytes: await activatedFile.length(),
      sha256: manifest.sha256,
      isPinned: isPinned,
      installedAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
  }

  Future<InstalledAdapterRecord> activateAdapter({
    required AdapterCatalogEntry entry,
    required AdapterManifest manifest,
    required File stagedFile,
    InstalledAdapterRecord? previousRecord,
  }) async {
    await initialize();

    final targetDirectory = Directory(
      path.join(
        _activeAdaptersDirectory.path,
        entry.namespaceId,
        entry.adapterId,
        manifest.version,
      ),
    );
    await targetDirectory.create(recursive: true);

    final targetFile = File(
      path.join(targetDirectory.path, manifest.artifactFileName),
    );
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final activatedFile = await stagedFile.rename(targetFile.path);

    if (previousRecord != null &&
        previousRecord.activePath != activatedFile.path) {
      final previousFile = File(previousRecord.activePath);
      if (await previousFile.exists()) {
        await previousFile.delete();
      }
      await _deleteEmptyParents(previousFile.parent, _activeAdaptersDirectory);
    }

    return InstalledAdapterRecord(
      adapterId: entry.adapterId,
      ownerAppId: entry.ownerAppId,
      namespaceId: entry.namespaceId,
      baseModelId: entry.modelId,
      displayName: entry.displayName,
      version: manifest.version,
      activePath: activatedFile.path,
      sizeBytes: await activatedFile.length(),
      sha256: manifest.sha256,
      compatibleVariantIds: entry.compatibleVariantIds,
      compatibleQuantizations: manifest.quantizationCompatibility,
      taskProfile: manifest.taskProfile,
      installedAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
  }

  Future<InstalledBundleComponentRecord> activateBundleComponent({
    required String bundleId,
    required BundleNode node,
    required File stagedFile,
    InstalledBundleComponentRecord? previousRecord,
  }) async {
    await initialize();

    final targetDirectory = Directory(
      path.join(_activeBundleComponentsDirectory.path, node.modelId),
    );
    await targetDirectory.create(recursive: true);
    final targetFile = File(
      path.join(targetDirectory.path, node.artifactFileName),
    );
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    final activatedFile = await stagedFile.rename(targetFile.path);
    final bundleIds = <String>{
      ...(previousRecord?.bundleIds ?? const <String>[]),
      bundleId,
    }.toList()..sort();

    return InstalledBundleComponentRecord(
      modelId: node.modelId,
      nodeId: node.nodeId,
      type: node.type,
      bundleIds: bundleIds,
      runtime: node.runtime,
      format: node.format,
      modality: node.modality,
      activePath: activatedFile.path,
      sizeBytes: await activatedFile.length(),
      sha256: node.sha256,
      installedAt: previousRecord?.installedAt ?? DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
  }

  Future<InstalledBundleRecord> activateBundle({
    required BundleCatalogEntry entry,
    required BundleManifest manifest,
    required List<String> componentModelIds,
    InstalledBundleRecord? previousRecord,
  }) async {
    await initialize();
    final record = InstalledBundleRecord(
      bundleId: entry.bundleId,
      displayName: entry.displayName,
      version: manifest.version,
      taskProfiles: manifest.taskProfiles,
      componentModelIds: componentModelIds,
      installedAt: previousRecord?.installedAt ?? DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
    final targetFile = File(
      path.join(_activeBundlesDirectory.path, '${entry.bundleId}.json'),
    );
    await targetFile.writeAsString(jsonEncode(record.toJson()));
    return record;
  }

  Future<void> quarantineStagingFile(File stagedFile) async {
    await initialize();
    if (!await stagedFile.exists()) {
      return;
    }

    final quarantineFile = File(
      path.join(
        _failedDirectory.path,
        '${DateTime.now().millisecondsSinceEpoch}-${path.basename(stagedFile.path)}',
      ),
    );
    await quarantineFile.parent.create(recursive: true);
    await stagedFile.rename(quarantineFile.path);
  }

  Future<void> deleteInstalledModel(String modelId) async {
    await initialize();
    final modelDirectory = Directory(path.join(_activeDirectory.path, modelId));
    if (await modelDirectory.exists()) {
      await modelDirectory.delete(recursive: true);
    }
  }

  Future<void> deleteInstalledAdapter(
    String namespaceId,
    String adapterId,
  ) async {
    await initialize();
    final adapterDirectory = Directory(
      path.join(_activeAdaptersDirectory.path, namespaceId, adapterId),
    );
    if (await adapterDirectory.exists()) {
      await adapterDirectory.delete(recursive: true);
    }
  }

  Future<void> deleteBundleRecord(String bundleId) async {
    await initialize();
    final file = File(
      path.join(_activeBundlesDirectory.path, '$bundleId.json'),
    );
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteBundleComponent(String modelId) async {
    await initialize();
    final componentDirectory = Directory(
      path.join(_activeBundleComponentsDirectory.path, modelId),
    );
    if (await componentDirectory.exists()) {
      await componentDirectory.delete(recursive: true);
    }
  }

  Future<StorageSnapshot> buildSnapshot(
    Map<String, InstalledModelRecord> installations,
    Map<String, InstalledBundleComponentRecord> bundleComponents,
  ) async {
    await initialize();
    return StorageSnapshot(
      usedBytes: await _directorySize(_rootDirectory),
      quotaBytes: quotaBytes,
      installedCount: installations.length,
      sharedComponentCount: bundleComponents.values
          .where((record) => record.bundleIds.length > 1)
          .length,
    );
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var totalBytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }

  Future<void> _deleteEmptyParents(
    Directory currentDirectory,
    Directory stopAt,
  ) async {
    var directory = currentDirectory;
    while (path.normalize(directory.path) != path.normalize(stopAt.path)) {
      if (!await directory.exists()) {
        directory = directory.parent;
        continue;
      }

      final entries = await directory.list().toList();
      if (entries.isNotEmpty) {
        return;
      }

      await directory.delete();
      directory = directory.parent;
    }
  }

  Future<void> _importLocalDeviceSeeds() async {
    final metadata =
        jsonDecode(await _metadataFile.readAsString()) as Map<String, dynamic>;
    final installationsById = <String, Map<String, dynamic>>{
      for (final row
          in metadata['installations'] as List<dynamic>? ?? const <dynamic>[])
        (row as Map<String, dynamic>)['model_id'] as String:
            Map<String, dynamic>.from(row),
    };
    final componentsById = <String, Map<String, dynamic>>{
      for (final row
          in metadata['bundle_components'] as List<dynamic>? ??
              const <dynamic>[])
        (row as Map<String, dynamic>)['model_id'] as String:
            Map<String, dynamic>.from(row),
    };
    final bundlesById = <String, Map<String, dynamic>>{
      for (final row
          in metadata['bundles'] as List<dynamic>? ?? const <dynamic>[])
        (row as Map<String, dynamic>)['bundle_id'] as String:
            Map<String, dynamic>.from(row),
    };
    final adapters =
        metadata['adapters'] as List<dynamic>? ?? const <dynamic>[];

    var changed = false;
    final generalSeedRoot = Directory('/data/local/tmp/essential_model_seed');
    final generalSeedMetadata = File(
      path.join(generalSeedRoot.path, 'metadata.json'),
    );
    if (await generalSeedMetadata.exists()) {
      final seed =
          jsonDecode(await generalSeedMetadata.readAsString())
              as Map<String, dynamic>;
      for (final row
          in seed['installations'] as List<dynamic>? ?? const <dynamic>[]) {
        final normalized = _normalizeSeedRecordPath(
          Map<String, dynamic>.from(row as Map<String, dynamic>),
          generalSeedRoot,
        );
        final modelId = normalized['model_id'] as String;
        if (!installationsById.containsKey(modelId) &&
            await File(normalized['active_path'] as String).exists()) {
          installationsById[modelId] = normalized;
          changed = true;
        }
      }
      for (final row
          in seed['bundle_components'] as List<dynamic>? ?? const <dynamic>[]) {
        final normalized = _normalizeSeedRecordPath(
          Map<String, dynamic>.from(row as Map<String, dynamic>),
          generalSeedRoot,
        );
        final modelId = normalized['model_id'] as String;
        if (!componentsById.containsKey(modelId) &&
            await File(normalized['active_path'] as String).exists()) {
          componentsById[modelId] = normalized;
          changed = true;
        }
      }
      for (final row
          in seed['bundles'] as List<dynamic>? ?? const <dynamic>[]) {
        final normalized = Map<String, dynamic>.from(
          row as Map<String, dynamic>,
        );
        final bundleId = normalized['bundle_id'] as String;
        if (!bundlesById.containsKey(bundleId)) {
          bundlesById[bundleId] = normalized;
          changed = true;
        }
      }
    }

    changed =
        await _registerLiteRtLmSeedModel(
          installationsById: installationsById,
          componentsById: componentsById,
          bundlesById: bundlesById,
          modelId: 'gemma-4-e2b-litertlm-it',
          displayName: 'Gemma-4-E2B-it LiteRT-LM',
          fileName: 'gemma-4-E2B-it.litertlm',
          sha256:
              'ab7838cdfc8f77e54d8ca45eadceb20452d9f01e4bfade03e5dce27911b27e42',
          bundleId: 'essential-chat-gemma-4-e2b-litertlm-it-bundle',
          bundleName: 'Essential Chat Gemma-4-E2B LiteRT-LM Bundle',
          recommendedTaskProfiles: const <String>['TEXT_GENERATION', 'CHAT'],
        ) ||
        changed;
    changed =
        await _registerLiteRtLmSeedModel(
          installationsById: installationsById,
          componentsById: componentsById,
          bundlesById: bundlesById,
          modelId: 'gemma-4-e4b-litertlm-it',
          displayName: 'Gemma-4-E4B-it LiteRT-LM',
          fileName: 'gemma-4-E4B-it.litertlm',
          sha256:
              'f335f2bfd1b758dc6476db16c0f41854bd6237e2658d604cbe566bcefd00a7bc',
          bundleId: 'essential-chat-gemma-4-e4b-litertlm-it-bundle',
          bundleName: 'Essential Chat Gemma-4-E4B LiteRT-LM Bundle',
          recommendedTaskProfiles: const <String>['TEXT_GENERATION', 'CHAT'],
        ) ||
        changed;

    if (!changed) {
      return;
    }

    await _metadataFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'installations': installationsById.values.toList(),
        'bundle_components': componentsById.values.toList(),
        'bundles': bundlesById.values.toList(),
        'adapters': adapters,
      }),
    );
  }

  Map<String, dynamic> _normalizeSeedRecordPath(
    Map<String, dynamic> record,
    Directory seedRoot,
  ) {
    final activePath = record['active_path'] as String? ?? '';
    final activeComponentsIndex = activePath.indexOf('/active_components/');
    final activeIndex = activePath.indexOf('/active/');
    if (activeComponentsIndex >= 0) {
      record['active_path'] = path.join(
        seedRoot.path,
        activePath.substring(activeComponentsIndex + 1),
      );
    } else if (activeIndex >= 0) {
      record['active_path'] = path.join(
        seedRoot.path,
        activePath.substring(activeIndex + 1),
      );
    }
    return record;
  }

  Future<bool> _registerLiteRtLmSeedModel({
    required Map<String, Map<String, dynamic>> installationsById,
    required Map<String, Map<String, dynamic>> componentsById,
    required Map<String, Map<String, dynamic>> bundlesById,
    required String modelId,
    required String displayName,
    required String fileName,
    required String sha256,
    required String bundleId,
    required String bundleName,
    required List<String> recommendedTaskProfiles,
  }) async {
    final modelFile = File(
      path.join('/data/local/tmp/essential_genai_seed', fileName),
    );
    if (!await modelFile.exists()) {
      return false;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final sizeBytes = await modelFile.length();
    var changed = false;
    if (!installationsById.containsKey(modelId)) {
      installationsById[modelId] = <String, dynamic>{
        'model_id': modelId,
        'display_name': displayName,
        'version': '1.0.0',
        'active_path': modelFile.path,
        'size_bytes': sizeBytes,
        'sha256': sha256,
        'is_pinned': true,
        'installed_at': now,
        'last_used_at': now,
      };
      changed = true;
    }
    if (!componentsById.containsKey(modelId)) {
      componentsById[modelId] = <String, dynamic>{
        'model_id': modelId,
        'node_id': '$modelId-base',
        'type': 'base',
        'bundle_ids': <String>[bundleId],
        'runtime': 'google-ai-edge-litertlm',
        'format': 'litertlm',
        'modality': 'text',
        'active_path': modelFile.path,
        'size_bytes': sizeBytes,
        'sha256': sha256,
        'installed_at': now,
        'last_used_at': now,
      };
      changed = true;
    }
    if (!bundlesById.containsKey(bundleId)) {
      bundlesById[bundleId] = <String, dynamic>{
        'bundle_id': bundleId,
        'display_name': bundleName,
        'version': '1.0.0',
        'task_profiles': recommendedTaskProfiles,
        'component_model_ids': <String>[modelId],
        'installed_at': now,
        'last_used_at': now,
      };
      changed = true;
    }
    return changed;
  }
}
