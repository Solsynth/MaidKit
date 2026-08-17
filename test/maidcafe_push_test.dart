import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/maidcafe_push.dart';
import 'package:maid_kit/servers/maidcafe_preferences.dart';
import 'package:maid_kit/servers/server_providers.dart';

void main() {
  group('maidCafeCloudSupportsPush', () {
    test('accepts Solsynth-hosted clouds', () {
      expect(maidCafeCloudSupportsPush('https://mk.solsynth.dev'), isTrue);
      expect(maidCafeCloudSupportsPush('https://cloud.solian.app'), isTrue);
      expect(maidCafeCloudSupportsPush('https://solsynth.dev'), isTrue);
      expect(maidCafeCloudSupportsPush('https://api.solian.app'), isTrue);
      expect(maidCafeCloudSupportsPush('https://MK.SOLSYNTH.DEV'), isTrue);
    });

    test('rejects self-hosted and lookalike clouds', () {
      expect(maidCafeCloudSupportsPush('http://127.0.0.1:8080'), isFalse);
      expect(maidCafeCloudSupportsPush('https://mk.example.com'), isFalse);
      expect(
        maidCafeCloudSupportsPush('https://solsynth.dev.evil.com'),
        isFalse,
      );
      expect(maidCafeCloudSupportsPush('https://solsynth.devx'), isFalse);
      expect(maidCafeCloudSupportsPush(''), isFalse);
      expect(maidCafeCloudSupportsPush('not a url'), isFalse);
    });
  });

  test(
    'push provider defers status mutation until after initialization',
    () async {
      final container = ProviderContainer(
        overrides: [
          maidCafeSettingsProvider.overrideWithValue(
            InMemoryMaidCafeSettings(cloudUrl: 'http://127.0.0.1:8747'),
          ),
          cloudUserProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(maidCafePushProvider), isA<MaidCafePushService>());
      expect(
        container.read(maidCafePushStatusProvider),
        MaidCafePushRegistrationStatus.unknown,
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(maidCafePushStatusProvider),
        MaidCafePushRegistrationStatus.unavailable,
      );
    },
  );
}
