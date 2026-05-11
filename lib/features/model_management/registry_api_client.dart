import 'dart:convert';
import 'dart:io';

import '../../app/app_config.dart';
import 'model_management_models.dart';

class RegistryApiClient {
  RegistryApiClient({Uri? baseUrl, HttpClient? httpClient})
    : _baseUrl = baseUrl ?? _defaultRegistryBaseUrl(),
      _httpClient = httpClient ?? HttpClient();

  final Uri _baseUrl;
  final HttpClient _httpClient;

  Uri get baseUrl => _baseUrl;

  Future<List<ModelCatalogEntry>> fetchCatalog() async {
    final json = await _getJson(_resolve('/essential/v1/catalog'));
    final models = json['items'] as List<dynamic>? ?? <dynamic>[];
    final entries = models
        .map(
          (dynamic item) =>
              ModelCatalogEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    entries.removeWhere(_isRemovedVisionLabelModel);
    for (final local in _localCatalogEntries) {
      if (!entries.any((entry) => entry.modelId == local.modelId)) {
        entries.add(local);
      }
    }
    return entries;
  }

  Future<List<AdapterCatalogEntry>> fetchAdapters({String? modelId}) async {
    final uri = modelId == null
        ? _resolve('/essential/v1/adapters')
        : _resolve('/essential/v1/adapters?model_id=$modelId');
    final json = await _getJson(uri);
    final items = json['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .map(
          (dynamic item) =>
              AdapterCatalogEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<BundleCatalogEntry>> fetchBundles({String? taskType}) async {
    final uri = taskType == null
        ? _resolve('/essential/v1/bundles')
        : _resolve('/essential/v1/bundles?task_type=$taskType');
    final json = await _getJson(uri);
    final items = json['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .map(
          (dynamic item) =>
              BundleCatalogEntry.fromJson(item as Map<String, dynamic>),
        )
        .where((entry) => !_isRemovedVisionBundle(entry))
        .toList();
  }

  Future<ModelManifest> fetchManifest(String modelId) async {
    final local = _localManifests[modelId];
    if (local != null) {
      return local;
    }
    final json = await _getJson(
      _resolve('/essential/v1/models/$modelId/manifest'),
    );
    return ModelManifest.fromJson(json);
  }

  Future<AdapterManifest> fetchAdapterManifest(String adapterId) async {
    final json = await _getJson(
      _resolve('/essential/v1/adapters/$adapterId/manifest'),
    );
    return AdapterManifest.fromJson(json);
  }

  Future<BundleManifest> fetchBundleManifest(String bundleId) async {
    final json = await _getJson(
      _resolve('/essential/v1/bundles/$bundleId/manifest'),
    );
    return BundleManifest.fromJson(json);
  }

  Future<BundleResolution> resolveBundle(
    String bundleId, {
    List<String> installedComponentIds = const <String>[],
  }) async {
    final params = installedComponentIds
        .map((String modelId) => 'installed_component_ids=$modelId')
        .join('&');
    final suffix = params.isEmpty ? '' : '?$params';
    final json = await _getJson(
      _resolve('/essential/v1/bundles/$bundleId/resolve$suffix'),
    );
    return BundleResolution.fromJson(json);
  }

  Uri resolveArtifactUri(String artifactPathOrId) {
    if (artifactPathOrId.startsWith('http://') ||
        artifactPathOrId.startsWith('https://')) {
      return Uri.parse(artifactPathOrId);
    }
    final baseUrl = _artifactBaseUrl();
    if (artifactPathOrId.startsWith('/')) {
      return baseUrl.resolve(artifactPathOrId);
    }
    return baseUrl.resolve('/essential/v1/artifacts/$artifactPathOrId');
  }

  bool _isRemovedVisionLabelModel(ModelCatalogEntry entry) {
    return entry.modelId == 'ssd-mobilenet-v2' ||
        entry.modelId == 'coco-labels';
  }

  bool _isRemovedVisionBundle(BundleCatalogEntry entry) {
    return entry.bundleId == 'essential-vision-detection-bundle' ||
        entry.nodes.any((node) => _isRemovedVisionModelId(node.modelId));
  }

  bool _isRemovedVisionModelId(String modelId) {
    return modelId == 'ssd-mobilenet-v2' || modelId == 'coco-labels';
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Registry API request failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Uri _resolve(String path) {
    return _baseUrl.resolve(path);
  }

  Uri _artifactBaseUrl() {
    if (_baseUrl.port == 8100) {
      return _baseUrl.replace(port: 8102);
    }
    return _baseUrl;
  }

  static Uri _defaultRegistryBaseUrl() {
    return Uri.parse(AppConfig.registryApiUrl);
  }
}

const _localCatalogEntries = <ModelCatalogEntry>[];

const _localManifests = <String, ModelManifest>{};
