import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_stats.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

/// Pins which route a server card's numbers come from.
///
/// The MaidCafe daemon snapshot is the *no-session* route: it fills a card
/// while nothing is connected, and a browser has nothing else. It must never
/// outrank a session the user opened, because that reads as a connection they
/// did not make — and, on a native build, it used to hide Connect behind a live
/// daemon, leaving the SSH route unreachable on a host whose daemon answers.
class _FakeStatsNotifier extends MaidCafeStatsNotifier {
  _FakeStatsNotifier(this._initial);

  final Map<int, MaidCafeServerStats> _initial;

  @override
  Map<int, MaidCafeServerStats> build() => _initial;
}

class _StubConnectionManager extends SshConnectionManager {
  _StubConnectionManager() : super(() => throw UnimplementedError());
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

ServerStats _stats({required double load}) => ServerStats(
  collectorId: 'collector',
  updatedAt: DateTime(2026, 10, 7, 12),
  loadAverage: load,
  cpuCount: 8,
  memoryTotalKb: 16777216,
  memoryAvailableKb: 8388608,
  diskTotalKb: 41943040,
  diskAvailableKb: 20971520,
  uptime: const Duration(days: 3),
);

final _daemonSnapshot = MaidCafeServerStats(
  stats: _stats(load: 4.5),
  endpoint: 'http://build.example:8747',
  fetchedAt: DateTime(2026, 10, 7, 12),
);

SshSessionInfo _session(SessionStatus status, {Duration? latency}) =>
    SshSessionInfo(
      serverId: 1,
      serverName: 'Build host',
      connectedAt: DateTime(2026, 10, 7, 12),
      status: status,
      stats: _stats(load: 0.2),
      networkLatency: latency,
    );

/// The same feed entry the daemon's own terminal publishes.
final _daemonTerminalSession = SshSessionInfo(
  serverId: 1,
  serverName: 'Build host',
  connectedAt: DateTime(2026, 10, 7, 12),
  status: SessionStatus.connected,
  transport: SessionTransport.maidcafe,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    // Drift's driftDatabase() asks path_provider for a temp dir.
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

  Future<void> pumpDashboard(
    WidgetTester tester, {
    List<SshSessionInfo> sessions = const <SshSessionInfo>[],
    Map<int, MaidCafeServerStats> daemonStats = const {},
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            serversProvider.overrideWith((ref) => Stream.value([_server])),
            sessionsProvider.overrideWith((ref) => Stream.value(sessions)),
            maidCafeStatsProvider.overrideWith(
              () => _FakeStatsNotifier(daemonStats),
            ),
            savedCredentialsProvider.overrideWith(
              (ref) => Stream.value(<SavedCredential>[]),
            ),
            scriptSnippetsProvider.overrideWith(
              (ref) => Stream.value(<ScriptSnippet>[]),
            ),
            biometricUnlockEnabledProvider.overrideWith(
              (ref) => Future.value(false),
            ),
            connectionManagerProvider.overrideWithValue(
              _StubConnectionManager(),
            ),
            cloudUserProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: const SessionsWorkspace(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final connectButton = find.widgetWithText(TextButton, 'Connect');

  testWidgets('a connected session owns the card over a daemon snapshot', (
    tester,
  ) async {
    // Both routes answer at once, which is the normal case on a native build
    // with a daemon installed. The session is the connection the user made and
    // the only one that measures a round trip, so the card reports it.
    await pumpDashboard(
      tester,
      sessions: [
        _session(
          SessionStatus.connected,
          latency: const Duration(milliseconds: 12),
        ),
      ],
      daemonStats: {1: _daemonSnapshot},
    );

    expect(find.text('12 ms'), findsOneWidget);
    expect(connectButton, findsNothing);
  });

  testWidgets('a daemon-fed card still offers Connect on a native build', (
    tester,
  ) async {
    // The daemon snapshot is not a session this client opened: a native build
    // has an SSH route to offer, and hiding Connect behind the daemon is what
    // made it unreachable.
    await pumpDashboard(tester, daemonStats: {1: _daemonSnapshot});

    expect(connectButton, findsOneWidget);
  });

  testWidgets('a card with neither route offers Connect and no numbers', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(connectButton, findsOneWidget);
    expect(find.text('12 ms'), findsNothing);
  });

  testWidgets('a daemon terminal is not the SSH session the card reads', (
    tester,
  ) async {
    // "Open terminal via daemon" puts a `connected` entry on the same feed. It
    // carries no readings and cannot run the SSH-shaped work, so the card keeps
    // offering Connect rather than reading it as a session.
    await pumpDashboard(
      tester,
      sessions: [_daemonTerminalSession],
      daemonStats: {1: _daemonSnapshot},
    );

    expect(find.text('12 ms'), findsNothing);
    expect(connectButton, findsOneWidget);
  });

  testWidgets('the detail page names the daemon while it is the source', (
    tester,
  ) async {
    await pumpDashboard(tester, daemonStats: {1: _daemonSnapshot});
    await tester.tap(find.text('Build host').first);
    await tester.pumpAndSettle();

    expect(find.text('serversStatsSourceDaemon'.tr()), findsOneWidget);
  });

  testWidgets('the detail page never names the daemon over a live session', (
    tester,
  ) async {
    // The label is the detail page's own statement of where the numbers came
    // from, so it follows the card's rule: a live session is not the daemon's.
    await pumpDashboard(
      tester,
      sessions: [
        _session(
          SessionStatus.connected,
          latency: const Duration(milliseconds: 12),
        ),
      ],
      daemonStats: {1: _daemonSnapshot},
    );
    await tester.tap(find.text('Build host').first);
    // A live session drives the overview's refresh timer, so the tree never
    // settles: pump a fixed frame instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('serversStatsSourceDaemon'.tr()), findsNothing);
  });
}
