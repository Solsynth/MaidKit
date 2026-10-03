import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/container_management_tab.dart';
import 'package:maid_kit/containers/project_repository.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_providers.dart';

/// A daemon session that answers the two calls the container list makes, with
/// the payloads the Go daemon serves. Everything else stays unimplemented, so a
/// tab that reaches for another member fails loudly.
class _StubSession implements MaidCafeStreamSession {
  _StubSession({this.updates = const {}});

  /// The `/api/v1/updates` payload, empty by default.
  final Map<String, dynamic> updates;

  @override
  bool get isClosed => false;

  @override
  Future<Map<String, dynamic>> containers() async => {
    'runtimes': [
      {
        'runtime': 'docker',
        'available': true,
        'containers': [
          {
            'id': 'abcdef123456',
            'name': 'web',
            'image': 'nginx:1.25',
            'state': 'running',
            'status': 'Up 3 hours',
          },
        ],
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> containerUpdates() async => updates;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'the container tab reached for ${invocation.memberName}',
  );
}

/// A registry that hands out one prepared session and counts its references,
/// which is all the tab needs from it.
class _StubRegistry implements MaidCafeSessionRegistry {
  _StubRegistry(this.session);

  final MaidCafeStreamSession session;
  var retains = 0;
  var releases = 0;

  @override
  void retain(Server server) => retains++;

  @override
  void release(Server server) => releases++;

  @override
  void invalidate(Server server) {}

  @override
  void close() {}

  @override
  Future<MaidCafeStreamSession?> sessionFor(
    Server server, {
    int? port,
    bool force = false,
  }) async => session;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    required MaidCafeSessionRegistry registry,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            maidCafeSessionRegistryProvider.overrideWithValue(registry),
            // The project links are a database stream, and drift's isolate
            // executor deadlocks inside a widget test's fake-async zone.
            composeProjectLinksProvider.overrideWith(
              (ref) => Stream.value(const <ComposeProjectLink>[]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ContainerManagementTab(
                server: Server(
                  id: 1,
                  name: 'Build host',
                  host: 'build.example',
                  port: 22,
                  username: 'builder',
                  collectStats: true,
                  collectSystemInfo: true,
                  connectionType: 'ssh',
                  maidCafeTerminalViaCloud: false,
                ),
                connected: true,
                connectionError: null,
                onConnect: () async {},
                refreshInterval: const Duration(minutes: 5),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the list comes from the daemon and badged rows say why', (
    tester,
  ) async {
    final registry = _StubRegistry(
      _StubSession(
        updates: {
          'interval_seconds': 3600,
          'containers': [
            {
              'container': 'abcdef123456',
              'name': 'web',
              'runtime': 'docker',
              'image': 'nginx:1.25',
              'outdated': true,
            },
          ],
        },
      ),
    );

    await pump(tester, registry: registry);

    // The row and its image come from the daemon's payload, not from SSH.
    expect(find.text('web'), findsOneWidget);
    expect(find.text('nginx:1.25'), findsOneWidget);
    // The daemon's update answer paints a badge on that row.
    expect(find.text('containerUpdateAvailable'.tr()), findsOneWidget);
    // The banner names the source, since this list did not come from SSH.
    expect(find.text('containerDataSourceMaidCafe'.tr()), findsOneWidget);
    // The tab retained the shared session while it was mounted.
    expect(registry.retains, 1);
  });

  testWidgets('a daemon with no update route draws no badge', (tester) async {
    await pump(tester, registry: _StubRegistry(_StubSession()));

    expect(find.text('web'), findsOneWidget);
    expect(find.text('containerUpdateAvailable'.tr()), findsNothing);
    expect(find.text('containerRestartToUpdate'.tr()), findsNothing);
  });
}
