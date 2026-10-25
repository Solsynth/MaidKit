import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/vault_gate.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Directory.systemTemp.path;
        });
  });

  testWidgets('offers opening another vault file on restricted platforms', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            vaultExistsProvider.overrideWith((ref) async => false),
            biometricUnlockEnabledProvider.overrideWith((ref) async => false),
            cloudSyncConfigurationProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: VaultGate(child: SizedBox())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('vaultCreateTitle'.tr()), findsOneWidget);
    expect(
      find.text('vaultOpenFileAction'.tr()),
      findsOneWidget,
      reason:
          'importing copies into managed storage, so every native platform '
          'offers it — not only platforms that support external vaults',
    );
  });
}
