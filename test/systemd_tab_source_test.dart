import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/systemd_models.dart';
import 'package:maid_kit/servers/systemd_tab.dart';
import 'package:maid_kit/theme.dart';

/// Pins which transport answers the services tab.
///
/// The MaidCafe daemon leads: its unit list arrives on a stream and costs the
/// host no exec. A live SSH session used to take the list over, which is the
/// bug this file guards — SSH now answers only a route with no daemon, or one
/// too old for `/api/v1/systemd`.
class _StubSession implements MaidCafeStreamSession {
  var systemdCalls = 0;

  @override
  bool get isClosed => false;

  @override
  Future<Map<String, dynamic>> systemd() async {
    systemdCalls++;
    return {
      'available': true,
      'units': [
        {
          'name': 'nginx.service',
          'load_state': 'loaded',
          'active_state': 'active',
          'sub_state': 'running',
          'description': 'A high performance web server',
          'unit_file_state': 'enabled',
        },
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
    'the services tab reached for ${invocation.memberName}',
  );
}

class _StubRegistry implements MaidCafeSessionRegistry {
  _StubRegistry(this.session);

  final MaidCafeStreamSession? session;

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

/// Records any SSH unit read. Every member throws: the daemon leads, so a list
/// that reached SSH is the failure the test is looking for.
class _RecordingManager extends SshConnectionManager {
  _RecordingManager() : super(() => throw UnimplementedError());

  final sshReads = <String>[];

  @override
  Future<SystemdUnitsSnapshot> listSystemdUnits(
    int serverId, {
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    sshReads.add('list');
    throw StateError('SSH listed units the daemon owns.');
  }
}

final _server = Server(
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

SshSessionInfo _sshSession() => SshSessionInfo(
  serverId: 1,
  serverName: 'Build host',
  connectedAt: DateTime(2026, 10, 7),
  status: SessionStatus.connected,
  transport: SessionTransport.ssh,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    required MaidCafeStreamSession? session,
    required List<SshSessionInfo> sessions,
    required SshConnectionManager manager,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
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
            connectionManagerProvider.overrideWithValue(manager),
            sessionsProvider.overrideWith((ref) => Stream.value(sessions)),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: Scaffold(
              body: SystemdTab(
                server: _server,
                connected: true,
                connectionError: null,
                onConnect: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the daemon owns the unit list while a session is live', (
    tester,
  ) async {
    // Both routes answer at once, which is the normal case on a native build
    // with a daemon installed. The daemon wins — its list costs the host no
    // exec — so the SSH reader never runs.
    final session = _StubSession();
    final manager = _RecordingManager();

    await pump(
      tester,
      session: session,
      sessions: [_sshSession()],
      manager: manager,
    );

    expect(session.systemdCalls, greaterThan(0));
    expect(manager.sshReads, isEmpty);
    expect(find.text('nginx.service'), findsOneWidget);
  });

  testWidgets('a host with no daemon route reads the list over SSH', (
    tester,
  ) async {
    // The fallback is what makes a host without a daemon usable at all, so it
    // has to still reach the session when there is nothing to ask instead.
    final manager = _RecordingManager();
    await pump(
      tester,
      session: null,
      sessions: [_sshSession()],
      manager: manager,
    );

    expect(manager.sshReads, ['list']);
  });
}
