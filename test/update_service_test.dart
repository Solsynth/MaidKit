import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/shared/services/maidkit_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:solsynth_express/solsynth_express.dart';

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

SolsynthExpressApi _apiWith(int statusCode, String body) {
  return SolsynthExpressApi(
    dio: Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _FakeAdapter(statusCode, body),
    baseUrl: 'https://distribution.example/api',
    productId: 'product-id',
  );
}

void main() {
  group('MaidKit update version checks', () {
    test('includes the platform build number in update requests', () {
      final info = PackageInfo(
        appName: 'MaidKit',
        packageName: 'dev.solsynth.maidkit',
        version: '1.3.0',
        buildNumber: '20',
      );

      expect(installedUpdateVersion(info), '1.3.0+20');
    });

    test('does not offer the installed or an older build', () {
      expect(isDistributionReleaseNewer('1.3.0+20', '1.3.0+20'), isFalse);
      expect(isDistributionReleaseNewer('1.3.0+19', '1.3.0+20'), isFalse);
      expect(isDistributionReleaseNewer('1.3.0', '1.3.0+20'), isFalse);
    });

    test('offers a newer build or app version', () {
      expect(isDistributionReleaseNewer('1.3.0+21', '1.3.0+20'), isTrue);
      expect(isDistributionReleaseNewer('1.4.0+1', '1.3.0+20'), isTrue);
    });
  });

  group('SolsynthExpressApi releases', () {
    test('parses a release and compatible artifacts', () async {
      final release = await _apiWith(
        200,
        jsonEncode({
          'data': [
            {
              'version': '1.1.0',
              'title': 'MaidKit 1.1.0',
              'release_notes': '## Changelog\n- Fixed things',
              'created_at': '2026-08-01T12:00:00Z',
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
      ).fetchLatestRelease(platform: 'macos', architecture: 'arm64');

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
    });

    test('returns no release when response has no usable release', () async {
      final release = await _apiWith(
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
      ).fetchLatestRelease(platform: 'macos', architecture: 'arm64');
      expect(release, isNull);
    });

    test('queries the release listing endpoint', () async {
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
      await SolsynthExpressApi(
        dio: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
        baseUrl: 'https://distribution.example/api/',
        productId: 'product-id',
      ).fetchLatestRelease(platform: 'macos', architecture: 'arm64');

      expect(
        adapter.requests.single.uri.toString(),
        'https://distribution.example/api/products/product-id/releases'
        '?channel=stable&platform=macos&architecture=arm64&limit=1&offset=0',
      );
    });
  });
}
