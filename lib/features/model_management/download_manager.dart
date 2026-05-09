import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'model_management_models.dart';

class DownloadManager {
  DownloadManager({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  static const _maxAttempts = 12;
  static const _retryDelay = Duration(seconds: 2);

  final HttpClient _httpClient;

  Future<void> downloadArtifact({
    required Uri artifactUri,
    required File destinationFile,
    required String expectedSha256,
    int? expectedSizeBytes,
    String? authorizationBearerToken,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    await destinationFile.parent.create(recursive: true);

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        if (expectedSizeBytes != null && await destinationFile.exists()) {
          final existingBytes = await destinationFile.length();
          if (existingBytes == expectedSizeBytes) {
            final digest = await _computeSha256(destinationFile);
            if (digest == expectedSha256) {
              onProgress(
                DownloadProgress(
                  receivedBytes: existingBytes,
                  totalBytes: expectedSizeBytes,
                ),
              );
              return;
            }
            await destinationFile.delete();
          }
        }

        await _downloadAttempt(
          artifactUri: artifactUri,
          destinationFile: destinationFile,
          expectedSizeBytes: expectedSizeBytes,
          authorizationBearerToken: authorizationBearerToken,
          onProgress: onProgress,
        );

        if (expectedSizeBytes != null &&
            await destinationFile.length() != expectedSizeBytes) {
          throw HttpException(
            'Download ended before expected size '
            '(${await destinationFile.length()} / $expectedSizeBytes).',
            uri: artifactUri,
          );
        }

        final digest = await _computeSha256(destinationFile);
        if (digest != expectedSha256) {
          throw StateError(
            'SHA-256 mismatch for ${destinationFile.path}: '
            'expected=$expectedSha256 actual=$digest',
          );
        }
        return;
      } catch (error) {
        lastError = error;
        if (_isHashMismatch(error) && await destinationFile.exists()) {
          await destinationFile.delete();
        }
        if (!_isRetryable(error) || attempt == _maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelay * attempt);
      }
    }

    throw StateError('Download failed: $lastError');
  }

  Future<void> _downloadAttempt({
    required Uri artifactUri,
    required File destinationFile,
    required int? expectedSizeBytes,
    required String? authorizationBearerToken,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    var existingBytes = 0;
    if (await destinationFile.exists()) {
      existingBytes = await destinationFile.length();
      if (expectedSizeBytes != null && existingBytes > expectedSizeBytes) {
        await destinationFile.writeAsBytes(<int>[], flush: true);
        existingBytes = 0;
      }
    }

    final request = await _httpClient.getUrl(artifactUri);
    if (authorizationBearerToken != null &&
        authorizationBearerToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $authorizationBearerToken',
      );
    }
    if (existingBytes > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
    }

    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      final body = await response.transform(SystemEncoding().decoder).join();
      throw HttpException(
        'Download failed (${response.statusCode}): $body',
        uri: artifactUri,
      );
    }

    final serverAcceptedResume =
        response.statusCode == HttpStatus.partialContent && existingBytes > 0;
    if (!serverAcceptedResume && existingBytes > 0) {
      await destinationFile.writeAsBytes(<int>[], flush: true);
      existingBytes = 0;
    }

    final totalBytes = response.contentLength >= 0
        ? response.contentLength + existingBytes
        : expectedSizeBytes ?? existingBytes;
    onProgress(
      DownloadProgress(receivedBytes: existingBytes, totalBytes: totalBytes),
    );

    final sink = destinationFile.openWrite(
      mode: existingBytes > 0 ? FileMode.append : FileMode.write,
    );
    var receivedBytes = existingBytes;

    try {
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(
          DownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (expectedSizeBytes != null && receivedBytes < expectedSizeBytes) {
      throw HttpException(
        'Download interrupted at $receivedBytes / $expectedSizeBytes bytes.',
        uri: artifactUri,
      );
    }
  }

  bool _isRetryable(Object error) {
    return error is SocketException ||
        error is HttpException ||
        error is TlsException ||
        error is TimeoutException ||
        _isHashMismatch(error) ||
        error.toString().toLowerCase().contains('connection closed') ||
        error.toString().toLowerCase().contains('connection reset') ||
        error.toString().toLowerCase().contains('broken pipe');
  }

  bool _isHashMismatch(Object error) {
    return error.toString().contains('SHA-256 mismatch');
  }

  Future<String> _computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<bool> verifyArtifactSha256({
    required File file,
    required String expectedSha256,
  }) async {
    if (!await file.exists()) {
      return false;
    }
    final digest = await _computeSha256(file);
    return digest == expectedSha256;
  }
}
