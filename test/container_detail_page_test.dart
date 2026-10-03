import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/container_detail_page.dart';
import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';

/// A daemon session that answers the per-container reads with the payloads the
/// Go daemon serves, and counts them so the test can prove which transport the
/// page actually used.
class _StubSession implements MaidCafeStreamSession {
  var inspectCalls = 0;
  var statsCalls = 0;
  var logCalls = 0;

  @override
  bool get isClosed => false;

  @override
  Future<Map<String, dynamic>> containerInspect(String id) async {
    inspectCalls++;
    return {
      'container': 'abcdef123456',
      'name': 'web',
      'runtime': 'docker',
      'inspect': {
        'Id': 'abcdef1234567890',
        'Name': '/web',
        'Image': 'sha256:deadbeef',
        'State': {
          'Status': 'running',
          'StartedAt': '2026-10-01T10:00:05Z',
          'ExitCode': 0,
        },
        'Config': {
          'Image': 'nginx:1.25',
          'Env': ['TZ=UTC'],
        },
        'HostConfig': {
          'NetworkMode': 'bridge',
          'RestartPolicy': {'Name': 'unless-stopped'},
        },
        'NetworkSettings': {
          'Networks': {
            'myapp_default': {'IPAddress': '172.18.0.2'},
          },
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> containerStats(String id) async {
    statsCalls++;
    return {
      'container': 'abcdef123456',
      'name': '/web',
      'runtime': 'docker',
      'cpu_percent': 12.5,
      'memory_usage_bytes': 20 * 1024 * 1024,
      'memory_limit_bytes': 1024 * 1024 * 1024,
      'memory_percent': 2.0,
      'pids': 7,
    };
  }

  @override
  Future<Map<String, dynamic>> containerUpdates() async => {
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
  };

  @override
  Future<Map<String, dynamic>> containerLogs(
    String id, {
    String source = 'captured',
    int lines = 200,
  }) async {
    logCalls++;
    return {
      'container': id,
      'source': source,
      'lines': [
        {'ts': '2026-10-03T02:00:00Z', 'line': 'listening on 80'},
      ],
    };
  }

  @override
  Stream<MaidCafeStreamEvent> openStream({
    Set<MaidCafeStreamEventType> events = maidCafeStreamAllEvents,
    int processesLimit = 0,
  }) => const Stream<MaidCafeStreamEvent>.empty();

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'the detail page reached for ${invocation.memberName}',
  );
}

class _StubRegistry implements MaidCafeSessionRegistry {
  _StubRegistry(this.session);

  final MaidCafeStreamSession session;

  @override
  void retain(Server server) {}

  @override
  void release(Server server) {}

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

  final server = Server(
    id: 1,
    name: 'Build host',
    host: 'build.example',
    port: 22,
    username: 'builder',
    collectStats: true,
    collectSystemInfo: true,
    connectionType: 'ssh',
    maidCafeTerminalViaCloud: false,
  );

  Future<void> pump(WidgetTester tester, _StubSession session) async {
    // A desktop-sized surface: the narrow layout stacks the overview above a
    // tall inspector panel, and a lazy list view never builds the panel that
    // sits below the fold.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            maidCafeSessionRegistryProvider.overrideWithValue(
              _StubRegistry(session),
            ),
            // No SSH session at all: every panel below has to come from the
            // daemon, exactly as it must in a browser.
            sessionsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            home: ContainerDetailPage(
              server: server,
              runtime: ContainerRuntime.docker,
              scope: ContainerScope.root,
              containerId: 'abcdef123456',
              containerName: 'web',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inspect, stats and logs come from the daemon when SSH is absent',
    (tester) async {
      final session = _StubSession();

      await pump(tester, session);

      // Every read went to the daemon: there is no SSH session to fall back on,
      // so an SSH attempt would have failed the render.
      expect(session.inspectCalls, greaterThan(0));
      expect(session.statsCalls, greaterThan(0));

      // The identity block renders the daemon's inspect payload (the app bar
      // carries the same name).
      expect(find.text('web'), findsWidgets);
      expect(find.text('nginx:1.25'), findsOneWidget);
      // A field only inspect carries, rendered by the details panel.
      expect(find.text('unless-stopped'), findsOneWidget);
      // The resource chips come from the daemon's normalized stats.
      expect(find.text('12.5%'), findsOneWidget);
      expect(find.text('20.0 MB / 1.0 GB'), findsOneWidget);
      // ... and its update answer paints the badge.
      expect(find.text('containerUpdateAvailable'.tr()), findsOneWidget);
      // No SSH session exists, so the page must not offer an SSH-only surface.
      expect(find.text('commonConnect'.tr()), findsNothing);
    },
  );

  testWidgets('the log pane follows the daemon tail without SSH', (
    tester,
  ) async {
    final session = _StubSession();

    await pump(tester, session);

    expect(session.logCalls, greaterThan(0));
    final view = tester.widget<AnsiLogView>(find.byType(AnsiLogView));
    expect(view.text, contains('listening on 80'));
  });
}
