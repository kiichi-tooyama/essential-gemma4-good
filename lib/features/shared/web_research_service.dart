import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WebSource {
  const WebSource({
    required this.title,
    required this.url,
    this.snippet = '',
    this.excerpt = '',
  });

  factory WebSource.fromJson(Map<String, dynamic> json) {
    return WebSource(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      excerpt: json['excerpt'] as String? ?? '',
    );
  }

  final String title;
  final String url;
  final String snippet;
  final String excerpt;

  bool get isUseful => title.trim().isNotEmpty || snippet.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'url': url,
      'snippet': snippet,
      'excerpt': excerpt,
    };
  }
}

class WebResearchResult {
  const WebResearchResult({
    required this.query,
    required this.sources,
    this.locationContext = '',
    this.locationNotice = '',
  });

  final String query;
  final List<WebSource> sources;
  final String locationContext;
  final String locationNotice;

  bool get hasSources => sources.isNotEmpty;

  String buildPromptContext({int maxRunes = 1800}) {
    if (sources.isEmpty &&
        locationContext.trim().isEmpty &&
        locationNotice.trim().isEmpty) {
      return '';
    }
    final buffer = StringBuffer('Web検索結果（検索クエリ: $query）:');
    if (locationContext.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('ユーザーの現在地情報: ${locationContext.trim()}');
    }
    if (locationNotice.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('位置情報について: ${locationNotice.trim()}');
    }
    if (sources.isEmpty) {
      buffer
        ..writeln()
        ..writeln('検索結果は取得できませんでした。位置情報の制約がある場合は回答本文で自然に伝えてください。');
      return _takeRunes(buffer.toString(), maxRunes);
    }
    for (final source in sources.take(5)) {
      buffer.writeln();
      buffer.writeln('- ${source.title}');
      if (source.snippet.trim().isNotEmpty) {
        buffer.writeln('  ${source.snippet.trim()}');
      }
      if (source.url.trim().isNotEmpty) {
        buffer.writeln('  URL: ${source.url.trim()}');
      }
      if (source.excerpt.trim().isNotEmpty) {
        buffer.writeln('  本文抜粋: ${_takeRunes(source.excerpt.trim(), 520)}');
      }
    }
    return _takeRunes(buffer.toString(), maxRunes);
  }
}

class WebResearchService {
  WebResearchService({
    MethodChannel channel = const MethodChannel('essential/web_research'),
    MethodChannel connectivityChannel = const MethodChannel(
      'essential/connectivity',
    ),
  }) : _channel = channel,
       _connectivityChannel = connectivityChannel;

  final MethodChannel _channel;
  final MethodChannel _connectivityChannel;

  bool shouldUseWeb(String query) {
    final normalized = query.trim();
    if (normalized.runes.length <= 12 &&
        RegExp(
          r'^(こんにちは|こんばんは|おはよう|hello|hi|hey|やあ|テスト)$',
          caseSensitive: false,
        ).hasMatch(normalized)) {
      return false;
    }
    final hasExplicitWebNeed = RegExp(
      r'(今日|現在|最新|ニュース|天気|気温|雨|価格|株価|為替|いつ|どこ|誰|検索|調べ|確認|発売|評判|近く|周辺|現在地|概要|人口|観光|交通|歴史|行政|today|latest|news|weather|price)',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (hasExplicitWebNeed) {
      return true;
    }
    if (normalized.length < 8) {
      return false;
    }
    if (_looksLikeFactualLookup(normalized)) {
      return true;
    }
    return false;
  }

  Future<bool> isOnlineForFeatures() => _isOnline();

  Future<WebResearchResult> researchIfUseful(
    String query, {
    String locationContext = '',
    String locationNotice = '',
  }) async {
    if (!shouldUseWeb(query)) {
      debugPrint('[WebSearch] skipped: "$query"');
      return WebResearchResult(
        query: query,
        sources: const <WebSource>[],
        locationContext: locationContext,
        locationNotice: locationNotice,
      );
    }
    return research(
      _searchQueryWithLocation(query, locationContext),
      locationContext: locationContext,
      locationNotice: locationNotice,
    );
  }

  Future<WebResearchResult> research(
    String query, {
    int maxResults = 5,
    bool readPages = true,
    int? maxPageReads,
    int pageMaxChars = 1200,
    String locationContext = '',
    String locationNotice = '',
  }) async {
    final effectiveQuery = _searchQueryWithLocation(query, locationContext);
    if (!await _isOnline()) {
      debugPrint('[WebSearch] skipped: device is offline');
      return WebResearchResult(
        query: effectiveQuery,
        sources: const <WebSource>[],
        locationContext: '',
        locationNotice:
            'オフラインのため、Web検索と位置情報を使わずに端末内の情報だけで回答します。'
            '${locationNotice.trim().isEmpty ? '' : '\n${locationNotice.trim()}'}',
      );
    }
    final isNewsQuery = RegExp(
      r'(ニュース|news|最新|速報)',
      caseSensitive: false,
    ).hasMatch(query);
    final resultLimit = isNewsQuery ? maxResults.clamp(6, 10) : maxResults;
    try {
      debugPrint('[WebSearch] search start: query="$effectiveQuery"');
      final response = await _channel.invokeMethod<List<Object?>>(
        'search',
        <String, Object?>{'query': effectiveQuery, 'maxResults': resultLimit},
      );
      final rows = response ?? const <Object?>[];
      final sources = <WebSource>[];
      for (final row in rows.whereType<Map<Object?, Object?>>()) {
        final title = row['title']?.toString() ?? '';
        final url = row['url']?.toString() ?? '';
        final snippet = row['snippet']?.toString() ?? '';
        if (title.trim().isEmpty && snippet.trim().isEmpty) {
          continue;
        }
        if (!_isUsefulSourceUrl(url)) {
          continue;
        }
        var excerpt = '';
        final pageReadLimit = maxPageReads ?? (isNewsQuery ? 5 : 3);
        if (readPages &&
            url.trim().isNotEmpty &&
            sources.length < pageReadLimit) {
          try {
            final page = await _channel.invokeMethod<Map<Object?, Object?>>(
              'read',
              <String, Object?>{'url': url, 'maxChars': pageMaxChars},
            );
            excerpt = page?['text']?.toString().trim() ?? '';
          } catch (error) {
            debugPrint('[WebSearch] page read failed: $error');
          }
        }
        sources.add(
          WebSource(title: title, url: url, snippet: snippet, excerpt: excerpt),
        );
      }
      debugPrint('[WebSearch] search done: ${sources.length} sources');
      return WebResearchResult(
        query: effectiveQuery,
        sources: sources,
        locationContext: locationContext,
        locationNotice: locationNotice,
      );
    } catch (error) {
      debugPrint('[WebSearch] search failed: $error');
      return WebResearchResult(
        query: effectiveQuery,
        sources: const <WebSource>[],
        locationContext: locationContext,
        locationNotice: locationNotice,
      );
    }
  }

  Future<bool> _isOnline() async {
    try {
      return await _connectivityChannel.invokeMethod<bool>('isOnline') ?? true;
    } catch (error) {
      debugPrint('[WebSearch] connectivity check unavailable: $error');
      return true;
    }
  }

  String _searchQueryWithLocation(String query, String locationContext) {
    final compact = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    final location = _bestLocationSearchText(locationContext);
    if (RegExp(r'(ニュース|news|最新|速報)', caseSensitive: false).hasMatch(compact)) {
      if (location.isNotEmpty &&
          RegExp(
            r'(近く|周辺|現在地|地元|local|near)',
            caseSensitive: false,
          ).hasMatch(compact)) {
        return '$location 最新ニュース 主要ニュース 今日';
      }
      return '日本 最新ニュース 主要ニュース 今日 政治 経済 テクノロジー 国際 社会';
    }
    if (location.isEmpty) {
      return compact;
    }
    if (RegExp(r'(天気|気温|雨|weather)', caseSensitive: false).hasMatch(compact)) {
      return '$location 天気 現在 気温 降水確率';
    }
    return '$compact 現在地周辺 $location';
  }
}

String _bestLocationSearchText(String locationContext) {
  final normalized = locationContext.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '';
  }
  final addressMatch = RegExp(r'住所\s+([^(]+)').firstMatch(normalized);
  final address = addressMatch?.group(1)?.trim() ?? '';
  if (address.isNotEmpty) {
    final parts = address
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      return parts.take(2).join(' ');
    }
  }
  return normalized;
}

bool _isUsefulSourceUrl(String url) {
  final normalized = url.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return !normalized.contains('duckduckgo.com/y.js') &&
      !normalized.contains('bing.com/aclick') &&
      !normalized.contains('ad_domain=') &&
      !normalized.contains('/aclick?');
}

String _takeRunes(String text, int count) {
  if (text.runes.length <= count) {
    return text;
  }
  return String.fromCharCodes(text.runes.take(count));
}

bool _looksLikeFactualLookup(String text) {
  return RegExp(
    r'([一-龥ぁ-んァ-ン]{2,}(市|区|町|村|県|府|都|道|駅|大学|会社|施設|病院|学校|公園).*(について|教えて|とは|情報|概要|どんな|どこ)|[A-Za-z0-9][A-Za-z0-9 ._-]{2,}.*(about|info|overview|where|what))',
    caseSensitive: false,
  ).hasMatch(text);
}
