import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_preferences.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';

void main() {
  test('defaults and normalizes cloud endpoint', () {
    final settings = InMemoryMaidCafeSettings(
      cloudUrl: 'https://mk.solsynth.dev///',
    );
    expect(settings.cloudUrl, maidCafeDefaultCloudUrl);
  });

  test('accepts HTTPS cloud endpoints', () async {
    final settings = InMemoryMaidCafeSettings();
    await settings.saveCloudUrl('https://custom.example/');
    expect(settings.cloudUrl, 'https://custom.example');
  });

  test('rejects insecure non-loopback endpoints', () {
    expect(
      () => normalizeMaidCafeCloudUrl('http://custom.example'),
      throwsA(isA<MaidCafeException>()),
    );
    expect(
      () => normalizeMaidCafeLocalDaemonUrl('http://10.0.0.5:8747'),
      throwsA(isA<MaidCafeException>()),
    );
    expect(
      () => normalizeMaidCafeUrl('/relative'),
      throwsA(isA<MaidCafeException>()),
    );
  });
}
