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

  bool get _usesRemoteRegistry =>
      _baseUrl.hasScheme && _baseUrl.host.trim().isNotEmpty;

  Future<List<ModelCatalogEntry>> fetchCatalog() async {
    if (!_usesRemoteRegistry) {
      return _localCatalogEntries;
    }
    try {
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
    } on Object {
      return _localCatalogEntries;
    }
  }

  Future<List<AdapterCatalogEntry>> fetchAdapters({String? modelId}) async {
    if (!_usesRemoteRegistry) {
      return const <AdapterCatalogEntry>[];
    }
    final uri = modelId == null
        ? _resolve('/essential/v1/adapters')
        : _resolve('/essential/v1/adapters?model_id=$modelId');
    try {
      final json = await _getJson(uri);
      final items = json['items'] as List<dynamic>? ?? <dynamic>[];
      return items
          .map(
            (dynamic item) =>
                AdapterCatalogEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } on Object {
      return const <AdapterCatalogEntry>[];
    }
  }

  Future<List<BundleCatalogEntry>> fetchBundles({String? taskType}) async {
    if (!_usesRemoteRegistry) {
      return const <BundleCatalogEntry>[];
    }
    final uri = taskType == null
        ? _resolve('/essential/v1/bundles')
        : _resolve('/essential/v1/bundles?task_type=$taskType');
    try {
      final json = await _getJson(uri);
      final items = json['items'] as List<dynamic>? ?? <dynamic>[];
      return items
          .map(
            (dynamic item) =>
                BundleCatalogEntry.fromJson(item as Map<String, dynamic>),
          )
          .where((entry) => !_isRemovedVisionBundle(entry))
          .toList();
    } on Object {
      return const <BundleCatalogEntry>[];
    }
  }

  Future<ModelManifest> fetchManifest(String modelId) async {
    final local = _localManifests[modelId];
    if (local != null) {
      return local;
    }
    if (!_usesRemoteRegistry) {
      throw StateError('No Hugging Face manifest is configured for $modelId.');
    }
    final json = await _getJson(
      _resolve('/essential/v1/models/$modelId/manifest'),
    );
    return ModelManifest.fromJson(json);
  }

  Future<AdapterManifest> fetchAdapterManifest(String adapterId) async {
    if (!_usesRemoteRegistry) {
      throw StateError('No Hugging Face adapter manifest is configured.');
    }
    final json = await _getJson(
      _resolve('/essential/v1/adapters/$adapterId/manifest'),
    );
    return AdapterManifest.fromJson(json);
  }

  Future<BundleManifest> fetchBundleManifest(String bundleId) async {
    if (!_usesRemoteRegistry) {
      throw StateError('No Hugging Face bundle manifest is configured.');
    }
    final json = await _getJson(
      _resolve('/essential/v1/bundles/$bundleId/manifest'),
    );
    return BundleManifest.fromJson(json);
  }

  Future<BundleResolution> resolveBundle(
    String bundleId, {
    List<String> installedComponentIds = const <String>[],
  }) async {
    if (!_usesRemoteRegistry) {
      throw StateError('No Hugging Face bundle resolution is configured.');
    }
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
    if (!_usesRemoteRegistry) {
      throw StateError('No registry artifact base URL is configured.');
    }
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

const _localCatalogEntries = <ModelCatalogEntry>[
  ModelCatalogEntry(
    modelId: 'gemma-4-e2b-litertlm-it',
    displayName: 'Gemma 4 E2B LiteRT-LM',
    variantId: 'litertlm',
    version: '1.0.0',
    runtime: 'litert-lm',
    minOsVersion: 'Android 12',
    recommendedRamMb: 4096,
    diskSizeMb: 2469,
    downloadSizeMb: 2469,
    supportsAdapters: false,
    license: 'Gemma Terms of Use',
    sha256:
        '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    signature: 'hugging-face',
    artifactId: 'gemma-4-e2b-litertlm-it',
    summary: 'Balanced on-device chat model downloaded from Hugging Face.',
  ),
  ModelCatalogEntry(
    modelId: 'gemma-4-e4b-litertlm-it',
    displayName: 'Gemma 4 E4B LiteRT-LM',
    variantId: 'litertlm',
    version: '1.0.0',
    runtime: 'litert-lm',
    minOsVersion: 'Android 12',
    recommendedRamMb: 6144,
    diskSizeMb: 3491,
    downloadSizeMb: 3491,
    supportsAdapters: false,
    license: 'Gemma Terms of Use',
    sha256:
        '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
    signature: 'hugging-face',
    artifactId: 'gemma-4-e4b-litertlm-it',
    summary: 'Higher accuracy on-device chat model downloaded from Hugging Face.',
  ),
  ModelCatalogEntry(
    modelId: 'essential-mini',
    displayName: 'Essential Mini',
    variantId: 'q4_k_m',
    version: '1.0.0',
    runtime: 'llama.cpp',
    minOsVersion: 'Android 12',
    recommendedRamMb: 4096,
    diskSizeMb: 638,
    downloadSizeMb: 638,
    supportsAdapters: false,
    license: 'Apache-2.0',
    sha256:
        '9fecc3b3cd76bba89d504f29b616eedf7da85b96540e490ca5824d3f7d2776a0',
    signature: 'hugging-face',
    artifactId: 'essential-mini',
    summary: 'Small fallback chat model downloaded from Hugging Face.',
  ),
  ModelCatalogEntry(
    modelId: 'whisper-tiny',
    displayName: 'Whisper Tiny',
    variantId: 'ggml',
    version: '1.0.0',
    runtime: 'whisper.cpp',
    minOsVersion: 'Android 12',
    recommendedRamMb: 2048,
    diskSizeMb: 75,
    downloadSizeMb: 75,
    supportsAdapters: false,
    license: 'MIT',
    sha256:
        'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    signature: 'hugging-face',
    artifactId: 'whisper-tiny',
    summary: 'Compact speech transcription model downloaded from Hugging Face.',
  ),
  ModelCatalogEntry(
    modelId: 'whisper-base',
    displayName: 'Whisper Base',
    variantId: 'ggml',
    version: '1.0.0',
    runtime: 'whisper.cpp',
    minOsVersion: 'Android 12',
    recommendedRamMb: 2048,
    diskSizeMb: 142,
    downloadSizeMb: 142,
    supportsAdapters: false,
    license: 'MIT',
    sha256:
        '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    signature: 'hugging-face',
    artifactId: 'whisper-base',
    summary: 'Speech transcription model downloaded from Hugging Face.',
  ),
];

const _localManifests = <String, ModelManifest>{
  'gemma-4-e2b-litertlm-it': ModelManifest(
    modelId: 'gemma-4-e2b-litertlm-it',
    version: '1.0.0',
    artifactId: 'gemma-4-e2b-litertlm-it',
    artifactFileName: 'gemma-4-E2B-it.litertlm',
    artifactSizeBytes: 2588147712,
    sha256:
        '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    downloadPath: 'huggingface://litert-community/gemma-4-E2B-it-litert-lm',
    signature: 'hugging-face',
  ),
  'gemma-4-e4b-litertlm-it': ModelManifest(
    modelId: 'gemma-4-e4b-litertlm-it',
    version: '1.0.0',
    artifactId: 'gemma-4-e4b-litertlm-it',
    artifactFileName: 'gemma-4-E4B-it.litertlm',
    artifactSizeBytes: 3659530240,
    sha256:
        '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
    downloadPath: 'huggingface://litert-community/gemma-4-E4B-it-litert-lm',
    signature: 'hugging-face',
  ),
  'essential-mini': ModelManifest(
    modelId: 'essential-mini',
    version: '1.0.0',
    artifactId: 'essential-mini',
    artifactFileName: 'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
    artifactSizeBytes: 668788096,
    sha256:
        '9fecc3b3cd76bba89d504f29b616eedf7da85b96540e490ca5824d3f7d2776a0',
    downloadPath: 'huggingface://TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
    signature: 'hugging-face',
  ),
  'whisper-tiny': ModelManifest(
    modelId: 'whisper-tiny',
    version: '1.0.0',
    artifactId: 'whisper-tiny',
    artifactFileName: 'ggml-tiny.bin',
    artifactSizeBytes: 77691713,
    sha256:
        'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    downloadPath: 'huggingface://ggerganov/whisper.cpp/ggml-tiny.bin',
    signature: 'hugging-face',
  ),
  'whisper-base': ModelManifest(
    modelId: 'whisper-base',
    version: '1.0.0',
    artifactId: 'whisper-base',
    artifactFileName: 'ggml-base.bin',
    artifactSizeBytes: 147951465,
    sha256:
        '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    downloadPath: 'huggingface://ggerganov/whisper.cpp/ggml-base.bin',
    signature: 'hugging-face',
  ),
};
