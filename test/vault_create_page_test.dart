import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/vault_create_page.dart';
import 'package:maid_kit/servers/vault_file_storage.dart';

class _FailingCloudSyncService extends CloudSyncService {
  _FailingCloudSyncService() : super(vaultId: 'test');

  @override
  Future<List<CloudWorkspace>> signInAndListWorkspaces() async {
    throw const CloudSyncException('Sign-in unavailable.');
  }
}

class _PendingCloudSyncService extends CloudSyncService {
  _PendingCloudSyncService() : super(vaultId: 'test');

  @override
  Future<List<CloudWorkspace>> signInAndListWorkspaces() =>
      Completer<List<CloudWorkspace>>().future;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('shows the sign-in error on the cloud choices view', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            cloudSyncServiceProvider.overrideWithValue(
              _FailingCloudSyncService(),
            ),
          ],
          child: const MaterialApp(home: VaultCreatePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('vaultCreateFromCloudAction'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in unavailable.'), findsOneWidget);
    expect(find.text('commonCancel'.tr()), findsOneWidget);
  });

  testWidgets('shows progress while the cloud sign-in is in flight', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            cloudSyncServiceProvider.overrideWithValue(
              _PendingCloudSyncService(),
            ),
          ],
          child: const MaterialApp(home: VaultCreatePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('vaultCreateFromCloudAction'.tr()));
    // The sign-in future never completes; a single frame is enough for the
    // busy state to render, and pumpAndSettle would hang on the spinner.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('settingsCloudSigningIn'.tr()), findsOneWidget);
  });

  testWidgets('hides external vault creation on restricted platforms', (
    tester,
  ) async {
    if (externalVaultsSupported) return;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: const ProviderScope(child: MaterialApp(home: VaultCreatePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('vaultCreateExternalAction'.tr()), findsNothing);
  });

  testWidgets('internal creation does not show a folder picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: const ProviderScope(child: MaterialApp(home: VaultCreatePage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('vaultCreateFileAction'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('vaultChooseFolder'.tr()), findsNothing);
    expect(find.text('vaultChangeFolder'.tr()), findsNothing);
  });
}
