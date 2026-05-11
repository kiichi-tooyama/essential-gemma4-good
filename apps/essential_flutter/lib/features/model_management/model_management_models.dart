enum ModelAvailabilityState {
  notInstalled,
  downloading,
  available,
  updateAvailable,
  failed,
}

extension ModelAvailabilityStateLabel on ModelAvailabilityState {
  String get label {
    switch (this) {
      case ModelAvailabilityState.notInstalled:
        return 'まだ';
      case ModelAvailabilityState.downloading:
        return '準備中';
      case ModelAvailabilityState.available:
        return '使える';
      case ModelAvailabilityState.updateAvailable:
        return '更新できる';
      case ModelAvailabilityState.failed:
        return 'やり直し';
    }
  }

  String localizedLabel(bool useEnglish) {
    if (!useEnglish) {
      return label;
    }
    return switch (this) {
      ModelAvailabilityState.notInstalled => 'Not yet',
      ModelAvailabilityState.downloading => 'Preparing',
      ModelAvailabilityState.available => 'Available',
      ModelAvailabilityState.updateAvailable => 'Update available',
      ModelAvailabilityState.failed => 'Retry',
    };
  }
}

class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.modelId,
    required this.displayName,
    required this.variantId,
    required this.version,
    required this.runtime,
    required this.minOsVersion,
    required this.recommendedRamMb,
    required this.diskSizeMb,
    required this.downloadSizeMb,
    required this.supportsAdapters,
    required this.license,
    required this.sha256,
    required this.signature,
    required this.artifactId,
    required this.summary,
  });

  factory ModelCatalogEntry.fromJson(Map<String, dynamic> json) {
    return ModelCatalogEntry(
      modelId: json['model_id'] as String,
      displayName: json['display_name'] as String,
      variantId: json['variant_id'] as String,
      version: json['version'] as String,
      runtime: json['runtime'] as String,
      minOsVersion: json['min_os_version'] as String,
      recommendedRamMb: _readInt(json['recommended_ram_mb']),
      diskSizeMb: _readInt(json['disk_size_mb']),
      downloadSizeMb: _readInt(json['download_size_mb']),
      supportsAdapters: json['supports_adapters'] as bool? ?? false,
      license: json['license'] as String,
      sha256: json['sha256'] as String,
      signature: _readSignature(json['signature']),
      artifactId: json['artifact_id'] as String,
      summary: json['summary'] as String? ?? '',
    );
  }

  final String modelId;
  final String displayName;
  final String variantId;
  final String version;
  final String runtime;
  final String minOsVersion;
  final int recommendedRamMb;
  final int diskSizeMb;
  final int downloadSizeMb;
  final bool supportsAdapters;
  final String license;
  final String sha256;
  final String signature;
  final String artifactId;
  final String summary;
}

class ModelManifest {
  const ModelManifest({
    required this.modelId,
    required this.version,
    required this.artifactId,
    required this.artifactFileName,
    required this.artifactSizeBytes,
    required this.sha256,
    required this.downloadPath,
    required this.signature,
  });

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    return ModelManifest(
      modelId: json['model_id'] as String,
      version: json['version'] as String,
      artifactId: json['artifact_id'] as String,
      artifactFileName: json['artifact_file_name'] as String,
      artifactSizeBytes: _readInt(json['artifact_size_bytes']),
      sha256: json['sha256'] as String,
      downloadPath: json['download_path'] as String,
      signature: _readSignature(json['signature']),
    );
  }

  final String modelId;
  final String version;
  final String artifactId;
  final String artifactFileName;
  final int artifactSizeBytes;
  final String sha256;
  final String downloadPath;
  final String signature;
}

class AdapterCatalogEntry {
  const AdapterCatalogEntry({
    required this.adapterId,
    required this.ownerAppId,
    required this.namespaceId,
    required this.modelId,
    required this.displayName,
    required this.version,
    required this.runtime,
    required this.license,
    required this.artifactId,
    required this.compatibleVariantIds,
    required this.compatibleQuantizations,
    required this.taskProfile,
    required this.supportedModalities,
    required this.summary,
  });

  factory AdapterCatalogEntry.fromJson(Map<String, dynamic> json) {
    return AdapterCatalogEntry(
      adapterId: json['adapter_id'] as String,
      ownerAppId: json['owner_app_id'] as String? ?? '',
      namespaceId: json['namespace_id'] as String? ?? '',
      modelId: json['model_id'] as String,
      displayName: json['display_name'] as String,
      version: json['version'] as String,
      runtime: json['runtime'] as String,
      license: json['license'] as String,
      artifactId: json['artifact_id'] as String,
      compatibleVariantIds:
          (json['compatible_variant_ids'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      compatibleQuantizations:
          (json['compatible_quantizations'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      taskProfile: Map<String, String>.from(
        json['task_profile'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      supportedModalities:
          (json['supported_modalities'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      summary: json['summary'] as String? ?? '',
    );
  }

  final String adapterId;
  final String ownerAppId;
  final String namespaceId;
  final String modelId;
  final String displayName;
  final String version;
  final String runtime;
  final String license;
  final String artifactId;
  final List<String> compatibleVariantIds;
  final List<String> compatibleQuantizations;
  final Map<String, String> taskProfile;
  final List<String> supportedModalities;
  final String summary;
}

class AdapterManifest {
  const AdapterManifest({
    required this.adapterId,
    required this.ownerAppId,
    required this.namespaceId,
    required this.modelId,
    required this.displayName,
    required this.version,
    required this.runtime,
    required this.artifactId,
    required this.artifactFileName,
    required this.artifactSizeBytes,
    required this.sha256,
    required this.downloadPath,
    required this.compatibility,
    required this.quantizationCompatibility,
    required this.taskProfile,
    required this.supportedModalities,
    required this.signature,
  });

  factory AdapterManifest.fromJson(Map<String, dynamic> json) {
    return AdapterManifest(
      adapterId: json['adapter_id'] as String,
      ownerAppId: json['owner_app_id'] as String? ?? '',
      namespaceId: json['namespace_id'] as String? ?? '',
      modelId: json['model_id'] as String,
      displayName:
          json['display_name'] as String? ?? json['adapter_id'] as String,
      version: json['version'] as String,
      runtime: json['runtime'] as String,
      artifactId: json['artifact_id'] as String,
      artifactFileName: json['artifact_file_name'] as String,
      artifactSizeBytes: _readInt(json['artifact_size_bytes']),
      sha256: json['sha256'] as String,
      downloadPath: json['download_path'] as String,
      compatibility: json['compatibility'] as String? ?? '',
      quantizationCompatibility:
          (json['quantization_compatibility'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      taskProfile: Map<String, String>.from(
        json['task_profile'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      supportedModalities:
          (json['supported_modalities'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      signature: _readSignature(json['signature']),
    );
  }

  final String adapterId;
  final String ownerAppId;
  final String namespaceId;
  final String modelId;
  final String displayName;
  final String version;
  final String runtime;
  final String artifactId;
  final String artifactFileName;
  final int artifactSizeBytes;
  final String sha256;
  final String downloadPath;
  final String compatibility;
  final List<String> quantizationCompatibility;
  final Map<String, String> taskProfile;
  final List<String> supportedModalities;
  final String signature;
}

class BundleNode {
  const BundleNode({
    required this.nodeId,
    required this.modelId,
    required this.type,
    required this.runtime,
    required this.format,
    required this.artifactId,
    required this.artifactFileName,
    required this.artifactSizeBytes,
    required this.sha256,
    required this.downloadPath,
    required this.modality,
    required this.compatibleWith,
    required this.required,
  });

  factory BundleNode.fromJson(Map<String, dynamic> json) {
    return BundleNode(
      nodeId: json['node_id'] as String,
      modelId: json['model_id'] as String,
      type: json['type'] as String,
      runtime: json['runtime'] as String,
      format: json['format'] as String,
      artifactId: json['artifact_id'] as String,
      artifactFileName: json['artifact_file_name'] as String,
      artifactSizeBytes: _readInt(json['artifact_size_bytes']),
      sha256: json['sha256'] as String,
      downloadPath: json['download_path'] as String,
      modality: json['modality'] as String? ?? 'text',
      compatibleWith:
          (json['compatible_with'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      required: json['required'] as bool? ?? true,
    );
  }

  final String nodeId;
  final String modelId;
  final String type;
  final String runtime;
  final String format;
  final String artifactId;
  final String artifactFileName;
  final int artifactSizeBytes;
  final String sha256;
  final String downloadPath;
  final String modality;
  final List<String> compatibleWith;
  final bool required;
}

class BundleEdge {
  const BundleEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.relationType,
    required this.required,
  });

  factory BundleEdge.fromJson(Map<String, dynamic> json) {
    return BundleEdge(
      fromNodeId: json['from_node_id'] as String,
      toNodeId: json['to_node_id'] as String,
      relationType: json['relation_type'] as String,
      required: json['required'] as bool? ?? true,
    );
  }

  final String fromNodeId;
  final String toNodeId;
  final String relationType;
  final bool required;
}

class BundleCatalogEntry {
  const BundleCatalogEntry({
    required this.bundleId,
    required this.displayName,
    required this.version,
    required this.runtimeFamily,
    required this.taskProfiles,
    required this.recommendedRamMb,
    required this.storageSizeMb,
    required this.downloadSizeMb,
    required this.summary,
    required this.nodes,
  });

  factory BundleCatalogEntry.fromJson(Map<String, dynamic> json) {
    return BundleCatalogEntry(
      bundleId: json['bundle_id'] as String,
      displayName: json['display_name'] as String,
      version: json['version'] as String,
      runtimeFamily: json['runtime_family'] as String,
      taskProfiles:
          (json['task_profiles'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      recommendedRamMb: _readInt(json['recommended_ram_mb']),
      storageSizeMb: _readInt(json['storage_size_mb']),
      downloadSizeMb: _readInt(json['download_size_mb']),
      summary: json['summary'] as String? ?? '',
      nodes: (json['nodes'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) => BundleNode.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final String bundleId;
  final String displayName;
  final String version;
  final String runtimeFamily;
  final List<String> taskProfiles;
  final int recommendedRamMb;
  final int storageSizeMb;
  final int downloadSizeMb;
  final String summary;
  final List<BundleNode> nodes;
}

class BundleManifest {
  const BundleManifest({
    required this.bundleId,
    required this.displayName,
    required this.version,
    required this.runtimeFamily,
    required this.taskProfiles,
    required this.recommendedRamMb,
    required this.storageSizeMb,
    required this.downloadSizeMb,
    required this.summary,
    required this.nodes,
    required this.edges,
  });

  factory BundleManifest.fromJson(Map<String, dynamic> json) {
    return BundleManifest(
      bundleId: json['bundle_id'] as String,
      displayName: json['display_name'] as String,
      version: json['version'] as String,
      runtimeFamily: json['runtime_family'] as String,
      taskProfiles:
          (json['task_profiles'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      recommendedRamMb: _readInt(json['recommended_ram_mb']),
      storageSizeMb: _readInt(json['storage_size_mb']),
      downloadSizeMb: _readInt(json['download_size_mb']),
      summary: json['summary'] as String? ?? '',
      nodes: (json['nodes'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) => BundleNode.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) => BundleEdge.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final String bundleId;
  final String displayName;
  final String version;
  final String runtimeFamily;
  final List<String> taskProfiles;
  final int recommendedRamMb;
  final int storageSizeMb;
  final int downloadSizeMb;
  final String summary;
  final List<BundleNode> nodes;
  final List<BundleEdge> edges;
}

class BundleResolution {
  const BundleResolution({
    required this.executable,
    required this.selectedBundleId,
    required this.selectedNodes,
    required this.missingNodes,
    required this.incompatibilities,
    required this.fallbackBundleId,
  });

  factory BundleResolution.fromJson(Map<String, dynamic> json) {
    return BundleResolution(
      executable: json['executable'] as bool? ?? false,
      selectedBundleId: json['selected_bundle_id'] as String,
      selectedNodes:
          (json['selected_nodes'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      missingNodes:
          (json['missing_nodes'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      incompatibilities:
          (json['incompatibilities'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      fallbackBundleId: json['fallback_bundle_id'] as String?,
    );
  }

  final bool executable;
  final String selectedBundleId;
  final List<String> selectedNodes;
  final List<String> missingNodes;
  final List<String> incompatibilities;
  final String? fallbackBundleId;
}

class InstalledModelRecord {
  const InstalledModelRecord({
    required this.modelId,
    required this.displayName,
    required this.version,
    required this.activePath,
    required this.sizeBytes,
    required this.sha256,
    required this.isPinned,
    required this.installedAt,
    required this.lastUsedAt,
  });

  factory InstalledModelRecord.fromJson(Map<String, dynamic> json) {
    return InstalledModelRecord(
      modelId: json['model_id'] as String,
      displayName: json['display_name'] as String,
      version: json['version'] as String,
      activePath: json['active_path'] as String,
      sizeBytes: _readInt(json['size_bytes']),
      sha256: json['sha256'] as String,
      isPinned: json['is_pinned'] as bool? ?? false,
      installedAt: DateTime.parse(json['installed_at'] as String),
      lastUsedAt: DateTime.parse(json['last_used_at'] as String),
    );
  }

  final String modelId;
  final String displayName;
  final String version;
  final String activePath;
  final int sizeBytes;
  final String sha256;
  final bool isPinned;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  InstalledModelRecord copyWith({
    String? version,
    String? activePath,
    int? sizeBytes,
    String? sha256,
    bool? isPinned,
    DateTime? installedAt,
    DateTime? lastUsedAt,
  }) {
    return InstalledModelRecord(
      modelId: modelId,
      displayName: displayName,
      version: version ?? this.version,
      activePath: activePath ?? this.activePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      isPinned: isPinned ?? this.isPinned,
      installedAt: installedAt ?? this.installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'model_id': modelId,
      'display_name': displayName,
      'version': version,
      'active_path': activePath,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'is_pinned': isPinned,
      'installed_at': installedAt.toIso8601String(),
      'last_used_at': lastUsedAt.toIso8601String(),
    };
  }
}

class InstalledAdapterRecord {
  const InstalledAdapterRecord({
    required this.adapterId,
    required this.ownerAppId,
    required this.namespaceId,
    required this.baseModelId,
    required this.displayName,
    required this.version,
    required this.activePath,
    required this.sizeBytes,
    required this.sha256,
    required this.compatibleVariantIds,
    required this.compatibleQuantizations,
    required this.taskProfile,
    required this.installedAt,
    required this.lastUsedAt,
  });

  factory InstalledAdapterRecord.fromJson(Map<String, dynamic> json) {
    return InstalledAdapterRecord(
      adapterId: json['adapter_id'] as String,
      ownerAppId: json['owner_app_id'] as String? ?? '',
      namespaceId: json['namespace_id'] as String? ?? '',
      baseModelId: json['base_model_id'] as String,
      displayName: json['display_name'] as String,
      version: json['version'] as String,
      activePath: json['active_path'] as String,
      sizeBytes: _readInt(json['size_bytes']),
      sha256: json['sha256'] as String,
      compatibleVariantIds:
          (json['compatible_variant_ids'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      compatibleQuantizations:
          (json['compatible_quantizations'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      taskProfile: Map<String, String>.from(
        json['task_profile'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      installedAt: DateTime.parse(json['installed_at'] as String),
      lastUsedAt: DateTime.parse(json['last_used_at'] as String),
    );
  }

  final String adapterId;
  final String ownerAppId;
  final String namespaceId;
  final String baseModelId;
  final String displayName;
  final String version;
  final String activePath;
  final int sizeBytes;
  final String sha256;
  final List<String> compatibleVariantIds;
  final List<String> compatibleQuantizations;
  final Map<String, String> taskProfile;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  InstalledAdapterRecord copyWith({
    String? version,
    String? activePath,
    int? sizeBytes,
    String? sha256,
    DateTime? installedAt,
    DateTime? lastUsedAt,
  }) {
    return InstalledAdapterRecord(
      adapterId: adapterId,
      ownerAppId: ownerAppId,
      namespaceId: namespaceId,
      baseModelId: baseModelId,
      displayName: displayName,
      version: version ?? this.version,
      activePath: activePath ?? this.activePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      compatibleVariantIds: compatibleVariantIds,
      compatibleQuantizations: compatibleQuantizations,
      taskProfile: taskProfile,
      installedAt: installedAt ?? this.installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'adapter_id': adapterId,
      'owner_app_id': ownerAppId,
      'namespace_id': namespaceId,
      'base_model_id': baseModelId,
      'display_name': displayName,
      'version': version,
      'active_path': activePath,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'compatible_variant_ids': compatibleVariantIds,
      'compatible_quantizations': compatibleQuantizations,
      'task_profile': taskProfile,
      'installed_at': installedAt.toIso8601String(),
      'last_used_at': lastUsedAt.toIso8601String(),
    };
  }
}

class InstalledBundleComponentRecord {
  const InstalledBundleComponentRecord({
    required this.modelId,
    required this.nodeId,
    required this.type,
    required this.bundleIds,
    required this.runtime,
    required this.format,
    required this.modality,
    required this.activePath,
    required this.sizeBytes,
    required this.sha256,
    required this.installedAt,
    required this.lastUsedAt,
  });

  factory InstalledBundleComponentRecord.fromJson(Map<String, dynamic> json) {
    return InstalledBundleComponentRecord(
      modelId: json['model_id'] as String,
      nodeId: json['node_id'] as String,
      type: json['type'] as String,
      bundleIds: (json['bundle_ids'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic item) => item.toString())
          .toList(),
      runtime: json['runtime'] as String,
      format: json['format'] as String,
      modality: json['modality'] as String? ?? 'text',
      activePath: json['active_path'] as String,
      sizeBytes: _readInt(json['size_bytes']),
      sha256: json['sha256'] as String,
      installedAt: DateTime.parse(json['installed_at'] as String),
      lastUsedAt: DateTime.parse(json['last_used_at'] as String),
    );
  }

  final String modelId;
  final String nodeId;
  final String type;
  final List<String> bundleIds;
  final String runtime;
  final String format;
  final String modality;
  final String activePath;
  final int sizeBytes;
  final String sha256;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  InstalledBundleComponentRecord copyWith({
    List<String>? bundleIds,
    String? activePath,
    int? sizeBytes,
    String? sha256,
    DateTime? installedAt,
    DateTime? lastUsedAt,
  }) {
    return InstalledBundleComponentRecord(
      modelId: modelId,
      nodeId: nodeId,
      type: type,
      bundleIds: bundleIds ?? this.bundleIds,
      runtime: runtime,
      format: format,
      modality: modality,
      activePath: activePath ?? this.activePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      installedAt: installedAt ?? this.installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'model_id': modelId,
      'node_id': nodeId,
      'type': type,
      'bundle_ids': bundleIds,
      'runtime': runtime,
      'format': format,
      'modality': modality,
      'active_path': activePath,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'installed_at': installedAt.toIso8601String(),
      'last_used_at': lastUsedAt.toIso8601String(),
    };
  }
}

class InstalledBundleRecord {
  const InstalledBundleRecord({
    required this.bundleId,
    required this.displayName,
    required this.version,
    required this.taskProfiles,
    required this.componentModelIds,
    required this.installedAt,
    required this.lastUsedAt,
  });

  factory InstalledBundleRecord.fromJson(Map<String, dynamic> json) {
    return InstalledBundleRecord(
      bundleId: json['bundle_id'] as String,
      displayName: json['display_name'] as String,
      version: json['version'] as String,
      taskProfiles:
          (json['task_profiles'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      componentModelIds:
          (json['component_model_ids'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      installedAt: DateTime.parse(json['installed_at'] as String),
      lastUsedAt: DateTime.parse(json['last_used_at'] as String),
    );
  }

  final String bundleId;
  final String displayName;
  final String version;
  final List<String> taskProfiles;
  final List<String> componentModelIds;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  InstalledBundleRecord copyWith({
    List<String>? componentModelIds,
    DateTime? installedAt,
    DateTime? lastUsedAt,
  }) {
    return InstalledBundleRecord(
      bundleId: bundleId,
      displayName: displayName,
      version: version,
      taskProfiles: taskProfiles,
      componentModelIds: componentModelIds ?? this.componentModelIds,
      installedAt: installedAt ?? this.installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'bundle_id': bundleId,
      'display_name': displayName,
      'version': version,
      'task_profiles': taskProfiles,
      'component_model_ids': componentModelIds,
      'installed_at': installedAt.toIso8601String(),
      'last_used_at': lastUsedAt.toIso8601String(),
    };
  }
}

class StorageSnapshot {
  const StorageSnapshot({
    required this.usedBytes,
    required this.quotaBytes,
    required this.installedCount,
    required this.sharedComponentCount,
  });

  static const empty = StorageSnapshot(
    usedBytes: 0,
    quotaBytes: 0,
    installedCount: 0,
    sharedComponentCount: 0,
  );

  final int usedBytes;
  final int quotaBytes;
  final int installedCount;
  final int sharedComponentCount;

  double get usageRatio {
    if (quotaBytes == 0) {
      return 0;
    }
    return (usedBytes / quotaBytes).clamp(0, 1);
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double get fraction {
    if (totalBytes == 0) {
      return 0;
    }
    return (receivedBytes / totalBytes).clamp(0, 1);
  }
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  return int.parse(value.toString());
}

String _readSignature(Object? value) {
  if (value is Map<String, dynamic>) {
    return value['value']?.toString() ?? '';
  }
  return value?.toString() ?? '';
}
