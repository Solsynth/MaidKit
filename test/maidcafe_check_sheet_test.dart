import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart' as ez;
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/server_repository.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/vault_service.dart';
import 'package:material_ui/material_ui.dart';

/// A repository whose reads never touch the network; only the credential and
/// secret lookups the check makes are needed.
class _FakeRepository extends ServerRepository {
  _FakeRepository(AppDatabase database)
    : super(database, VaultService(database));

  @override
  Future<ServerCredential> credentialFor(Server server) async =>
      const ServerCredential.password('test-password');

  @override
  Future<String?> maidCafeMetricsSecretFor(Server server) async => null;

  @override
  Future<String?> maidCafeTerminalSecretFor(Server server) async => null;
}

Server _server() => Server(
  id: 1,
  name: 'Build host',
  host: 'build.example',
  port: 22,
  username: 'builder',
  collectStats: false,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalPort: 8747,
  maidCafeTerminalUrl: 'http://127.0.0.1:8747',
  maidCafeTerminalEnabled: true,
  maidCafeTerminalViaCloud: false,
);

void main() {
  late Directory directory;
  late AppDatabase database;

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Directory.systemTemp.path;
        });
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('maidcafe-check-test');
    database = AppDatabase(filePath: '${directory.path}/test.sqlite');
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('the connectivity sheet opens before the slow reads finish', (
    WidgetTester tester,
  ) async {
    // The check first reads the daemon's terminal switch — over SSH, which is
    // slow — and the cloud workspace. Neither is needed to show the sheet, and
    // awaiting them first left the menu item doing nothing for that whole time
    // with no indicator anywhere. This future never completes, so the only way
    // the spinner can be on screen is that the sheet was shown first.
    final pending = Completer<List<CloudWorkspace>>();

    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWithValue(
            SshConnectionManager(() => throw UnimplementedError()),
          ),
          serverRepositoryProvider.overrideWithValue(_FakeRepository(database)),
          cloudWorkspacesProvider.overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    unawaited(
      checkMaidCafeConnectivity(capturedContext, capturedRef, _server()),
    );
    // One frame: the sheet route is pushed and paints.
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'the sheet must be up with its spinner while the reads run',
    );
    // The slow read is still outstanding, which is the point.
    expect(pending.isCompleted, isFalse);
  });
}
