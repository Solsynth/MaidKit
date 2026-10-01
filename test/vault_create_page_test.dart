import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
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
  Future<List<CloudWorkspace>> signInAndListWorkspaces({
    CloudDeviceCodeCallback? onDeviceCode,
  }) async {
    throw const CloudSyncException('Sign-in unavailable.');
  }
}

class _PendingCloudSyncService extends CloudSyncService {
  _PendingCloudSyncService() : super(vaultId: 'test');

  @override
  Future<List<CloudWorkspace>> signInAndListWorkspaces({
    CloudDeviceCodeCallback? onDeviceCode,
  }) => Completer<List<CloudWorkspace>>().future;
}

/// Records the link the download flow makes without touching secure storage.
class _LinkingCloudSyncService extends CloudSyncService {
  _LinkingCloudSyncService() : super(vaultId: 'test');

  CloudSyncConfiguration? linked;

  @override
  Future<CloudSyncConfiguration?> configuration() async => linked;

  @override
  Future<List<CloudWorkspace>> signInAndListWorkspaces({
    CloudDeviceCodeCallback? onDeviceCode,
  }) async => const [
    CloudWorkspace(id: 'ws-1', slug: 'workspace', name: 'Workspace'),
  ];

  @override
  Future<List<CloudVaultBlob>> listVaultBlobs(CloudWorkspace workspace) async =>
      const [CloudVaultBlob(id: 'blob-1', revision: 2, updatedAt: null)];

  @override
  Future<CloudSyncConfiguration> enable(
    CloudWorkspace workspace, {
    CloudVaultBlob? existingBlob,
  }) async {
    linked = CloudSyncConfiguration(
      workspaceId: workspace.id,
      workspaceName: workspace.name,
      workspaceSlug: workspace.slug,
      blobId: existingBlob?.id ?? 'blob-local',
      revision: 0,
      pendingDownload: existingBlob != null,
    );
    return linked!;
  }
}

/// Vault storage without filesystem calls: a widget test's fake-async zone
/// never completes real `dart:io` futures.
class _TempVaultStorage extends VaultFileStorage {
  @override
  Future<String> createVaultPath({String? name, String? directoryPath}) async =>
      '${Directory.systemTemp.path}/${name ?? 'vault'}.maidkit';

  @override
  Future<bool> isExternalPath(String path) async => false;

  @override
  Future<String> persistentPath(String path) async => path;
}

/// The cloud download keeps a spinner on screen, which stops `pumpAndSettle`
/// from ever returning; pump a transition worth of frames instead.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('a linked cloud vault reaches the gate configuration', (
    tester,
  ) async {
    final service = _LinkingCloudSyncService();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            cloudSyncServiceProvider.overrideWithValue(service),
            cloudSyncServiceForVaultProvider.overrideWith((ref, _) => service),
            vaultFileStorageProvider.overrideWithValue(_TempVaultStorage()),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final configuration = ref
                    .watch(cloudSyncConfigurationProvider)
                    .asData
                    ?.value;
                return Scaffold(
                  body: Column(
                    children: [
                      Text('linked:${configuration?.blobId ?? 'none'}'),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const VaultCreatePage(),
                          ),
                        ),
                        child: const Text('open'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('linked:none'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vaultCreateFromCloudAction'.tr()));
    // The page shows a busy spinner for the whole flow, so pumpAndSettle never
    // returns: pump the sheet transitions and the future frames by hand.
    await _pumpFrames(tester);
    await tester.tap(find.text('Workspace'));
    await _pumpFrames(tester);
    await tester.tap(find.text('blob-1'));
    await _pumpFrames(tester);
    await tester.tap(find.text('commonContinue'.tr()));
    await _pumpFrames(tester);
    await _pumpFrames(tester);

    expect(
      find.text('linked:blob-1'),
      findsOneWidget,
      reason: 'the gate reads this provider and must see the new cloud link',
    );
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
