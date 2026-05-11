import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../app/app_config.dart';

class HuggingFaceAuthException implements Exception {
  const HuggingFaceAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HuggingFaceAccessToken {
  const HuggingFaceAccessToken({
    required this.accessToken,
    required this.expiresAtMs,
    this.refreshToken,
  });

  factory HuggingFaceAccessToken.fromJson(Map<String, dynamic> json) {
    return HuggingFaceAccessToken(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresAtMs: json['expires_at_ms'] as int? ?? 0,
    );
  }

  final String accessToken;
  final String? refreshToken;
  final int expiresAtMs;

  bool get isUsable {
    if (accessToken.isEmpty) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return now < expiresAtMs - const Duration(minutes: 5).inMilliseconds;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at_ms': expiresAtMs,
  };
}

class HuggingFaceAuthService {
  HuggingFaceAuthService({
    MethodChannel channel = const MethodChannel('essential/huggingface_auth'),
    HttpClient? httpClient,
  }) : _channel = channel,
       _httpClient = httpClient ?? HttpClient();

  static const _authorizationEndpoint =
      'https://huggingface.co/oauth/authorize';
  static const _tokenEndpoint = 'https://huggingface.co/oauth/token';

  final MethodChannel _channel;
  final HttpClient _httpClient;

  Future<String?> storedAccessToken() async {
    final token = await _readToken();
    return token?.isUsable == true ? token!.accessToken : null;
  }

  Future<String> ensureAccessToken() async {
    final existing = await storedAccessToken();
    if (existing != null) {
      return existing;
    }

    final clientId = AppConfig.huggingFaceOAuthClientId.trim();
    if (clientId.isEmpty) {
      throw const HuggingFaceAuthException(
        'Hugging Face authentication is required, but ESSENTIAL_HF_OAUTH_CLIENT_ID is not configured. '
        'Create a Hugging Face OAuth app, set redirect URI essential://hf-auth, then rebuild with '
        '--dart-define=ESSENTIAL_HF_OAUTH_CLIENT_ID=<client_id>.',
      );
    }

    final redirectUri = AppConfig.huggingFaceOAuthRedirectUri.trim();
    final state = _randomBase64Url(24);
    final codeVerifier = _randomBase64Url(64);
    final codeChallenge = _base64UrlNoPadding(
      sha256.convert(utf8.encode(codeVerifier)).bytes,
    );
    final authUri = Uri.parse(_authorizationEndpoint).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': 'read-repos',
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    final redirect = await _channel
        .invokeMethod<String>('authorize', <String, Object?>{
          'url': authUri.toString(),
          'redirectUri': redirectUri,
        })
        .timeout(const Duration(minutes: 5));
    if (redirect == null || redirect.isEmpty) {
      throw const HuggingFaceAuthException('Hugging Face login was cancelled.');
    }

    final redirectResult = Uri.parse(redirect);
    final returnedState = redirectResult.queryParameters['state'];
    final code = redirectResult.queryParameters['code'];
    final error = redirectResult.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      throw HuggingFaceAuthException('Hugging Face login failed: $error');
    }
    if (returnedState != state || code == null || code.isEmpty) {
      throw const HuggingFaceAuthException(
        'Hugging Face login returned an invalid authorization response.',
      );
    }

    final token = await _exchangeCode(
      clientId: clientId,
      redirectUri: redirectUri,
      code: code,
      codeVerifier: codeVerifier,
    );
    await _writeToken(token);
    return token.accessToken;
  }

  Future<int> responseCode(Uri uri, {String? accessToken}) async {
    final request = await _httpClient.openUrl('HEAD', uri);
    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    if (response.statusCode == HttpStatus.methodNotAllowed) {
      return _rangeResponseCode(uri, accessToken: accessToken);
    }
    return response.statusCode;
  }

  Future<int> _rangeResponseCode(Uri uri, {String? accessToken}) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    return response.statusCode;
  }

  Future<void> openModelPage(Uri downloadUri) async {
    final modelPage = _modelPageFor(downloadUri) ?? downloadUri;
    await _channel.invokeMethod<void>('openUrl', <String, Object?>{
      'url': modelPage.toString(),
    });
  }

  Future<HuggingFaceAccessToken> _exchangeCode({
    required String clientId,
    required String redirectUri,
    required String code,
    required String codeVerifier,
  }) async {
    final request = await _httpClient.postUrl(Uri.parse(_tokenEndpoint));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(
      Uri(
        queryParameters: <String, String>{
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'code': code,
          'code_verifier': codeVerifier,
        },
      ).query,
    );
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HuggingFaceAuthException(
        'Hugging Face token exchange failed (${response.statusCode}): $body',
      );
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String? ?? '';
    if (accessToken.isEmpty) {
      throw const HuggingFaceAuthException(
        'Hugging Face token exchange did not return an access token.',
      );
    }
    final expiresIn = json['expires_in'] as int? ?? 3600;
    return HuggingFaceAccessToken(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAtMs:
          DateTime.now().millisecondsSinceEpoch +
          Duration(seconds: expiresIn).inMilliseconds,
    );
  }

  Future<File> _tokenFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'huggingface_oauth_token.json'));
  }

  Future<HuggingFaceAccessToken?> _readToken() async {
    final file = await _tokenFile();
    if (!await file.exists()) {
      return null;
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return HuggingFaceAccessToken.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToken(HuggingFaceAccessToken token) async {
    final file = await _tokenFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(token.toJson()), flush: true);
  }

  Uri? _modelPageFor(Uri downloadUri) {
    if (downloadUri.host != 'huggingface.co') {
      return null;
    }
    final segments = downloadUri.pathSegments;
    if (segments.length < 2) {
      return null;
    }
    return Uri.https('huggingface.co', '/${segments[0]}/${segments[1]}');
  }

  String _randomBase64Url(int bytes) {
    final random = Random.secure();
    return _base64UrlNoPadding(
      List<int>.generate(bytes, (_) => random.nextInt(256)),
    );
  }

  String _base64UrlNoPadding(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}
