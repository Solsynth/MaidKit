import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_push.dart';

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
}
