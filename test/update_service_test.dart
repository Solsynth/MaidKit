import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/shared/services/update_service.dart';

/// Dio adapter that answers every request with a canned HTTP response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UpdateService _serviceWith(int statusCode, String body) {
  return UpdateService(
    dio: Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _FakeAdapter(statusCode, body),
    distributionApiBaseUrl: 'https://distribution.example/api',
    distributionProductId: 'product-id',
  );
}

void main() {
  group('fetchLatestRelease', () {
    test(
      'parses a Solsynth Express release and compatible artifacts',
      () async {
        final release = await _serviceWith(
          200,
          jsonEncode({
            'data': [
              {
                'version': '1.1.0',
                'title': 'MaidKit 1.1.0',
                'release_notes': '## Changelog\n- Fixed things',
                'published_at': '2026-08-01T12:00:00Z',
                'artifacts': [
                  {
                    'platform': 'linux',
                    'architecture': 'amd64',
                    'file_name': 'maidkit-linux.zip',
                    'download_url': 'https://cdn.example/linux.zip',
                  },
                  {
                    'platform': 'macos',
                    'architecture': 'arm64',
                    'file_name': 'maidkit-macos.zip',
                    'download_url': 'https://cdn.example/macos.zip',
                  },
                ],
              },
            ],
          }),
        ).fetchLatestRelease();

        expect(release, isNotNull);
        expect(release!.tagName, '1.1.0');
        expect(release.name, 'MaidKit 1.1.0');
        expect(release.body, '## Changelog\n- Fixed things');
        expect(release.htmlUrl, isNull);
        expect(release.createdAt, DateTime.utc(2026, 8, 1, 12));
        expect(
          release.artifactFor('macos', 'arm64')?.downloadUrl,
          'https://cdn.example/macos.zip',
        );
        expect(release.artifactFor('windows', 'amd64'), isNull);
      },
    );

    test('falls back to version when title is absent', () async {
      final release = await _serviceWith(
        200,
        jsonEncode({
          'data': [
            {
              'version': '1.0.1',
              'artifacts': [
                {
                  'platform': 'macos',
                  'architecture': 'arm64',
                  'download_url': 'https://cdn.example/macos.zip',
                },
              ],
            },
          ],
        }),
      ).fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.name, '1.0.1');
      expect(release.body, isEmpty);
    });

    test('returns null on non-200 responses', () async {
      final release = await _serviceWith(
        500,
        '{"message": "boom"}',
      ).fetchLatestRelease();

      expect(release, isNull);
    });

    test('returns null when the response has no usable release', () async {
      final missingVersion = await _serviceWith(
        200,
        jsonEncode({
          'data': [
            {
              'artifacts': [
                {
                  'platform': 'macos',
                  'architecture': 'arm64',
                  'download_url': 'https://cdn.example/macos.zip',
                },
              ],
            },
          ],
        }),
      ).fetchLatestRelease();
      expect(missingVersion, isNull);

      final missingArtifact = await _serviceWith(
        200,
        jsonEncode({
          'data': [
            {'version': '1.0.1', 'artifacts': []},
          ],
        }),
      ).fetchLatestRelease();
      expect(missingArtifact, isNull);
    });

    test('queries the Solsynth Express release listing endpoint', () async {
      final adapter = _FakeAdapter(
        200,
        jsonEncode({
          'data': [
            {
              'version': '1.0.1',
              'artifacts': [
                {
                  'platform': 'macos',
                  'architecture': 'arm64',
                  'download_url': 'https://cdn.example/macos.zip',
                },
              ],
            },
          ],
        }),
      );
      await UpdateService(
        dio: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
        distributionApiBaseUrl: 'https://distribution.example/api/',
        distributionProductId: 'product-id',
      ).fetchLatestRelease();

      expect(
        adapter.requests.single.uri.toString(),
        'https://distribution.example/api/products/product-id/releases'
        '?channel=stable&platform=macos&architecture=arm64&limit=1',
      );
    });
  });
}
