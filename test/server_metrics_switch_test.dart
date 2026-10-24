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
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_stats.dart';
import 'package:maid_kit/servers/maidcafe_stats_scheduler.dart';
import 'package:maid_kit/servers/metrics_refresh_preferences.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/tabs_screen.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

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
  maidCafeTerminalUrl: 'https://build.example',
  maidCafeTerminalViaCloud: false,
);

final _daemonSnapshot = MaidCafeServerStats(
  stats: ServerStats(
    collectorId: 'collector',
    updatedAt: DateTime(2026, 10, 7, 12),
    loadAverage: 4.5,
    cpuCount: 8,
    memoryTotalKb: 16777216,
    memoryAvailableKb: 8388608,
    diskTotalKb: 41943040,
    diskAvailableKb: 20971520,
    uptime: const Duration(days: 3),
  ),
  endpoint: 'http://build.example:8747',
  fetchedAt: DateTime(2026, 10, 7, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'the switch defaults to on and round-trips through preferences',
    () async {
      final loaded = await MetricsRefreshPreferences.load();
      expect(loaded.serverMetricsEnabled, isTrue);

      await loaded.saveServerMetricsEnabled(false);
      expect(
        (await MetricsRefreshPreferences.load()).serverMetricsEnabled,
        isFalse,
      );
    },
  );

  test('the provider restores and saves the switch', () async {
    final settings = InMemoryMetricsRefreshSettings(
      serverMetricsEnabled: false,
    );
    final container = ProviderContainer(
      overrides: [metricsRefreshSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(container.read(serverMetricsEnabledProvider), isFalse);

    await container
        .read(serverMetricsEnabledProvider.notifier)
        .setEnabled(true);

    expect(settings.serverMetricsEnabled, isTrue);
    expect(container.read(serverMetricsEnabledProvider), isTrue);
  });

  test('the daemon scheduler serves nothing while the switch is off', () async {
    // The provider emptying the served set is what stops the polling timers;
    // the scheduler itself is only handed the servers it may dial.
    final scheduler = MaidCafeStatsScheduler(
      collect: (_) async => _daemonSnapshot,
      onSnapshot: (_, _) {},
    );
    addTearDown(scheduler.dispose);

    scheduler.update(interval: const Duration(seconds: 30), servers: [_server]);
    expect(scheduler.serverIds, {1});

    scheduler.update(
      interval: const Duration(seconds: 30),
      servers: const <Server>[],
    );
    expect(scheduler.serverIds, isEmpty);
  });

  test(
    'the SSH manager refuses an activity probe while metrics are off',
    () async {
      final manager = SshConnectionManager(
        () => throw UnimplementedError(),
        metricsEnabled: () => false,
      );
      addTearDown(manager.dispose);

      await expectLater(
        manager.collectActivityCounters(1),
        throwsA(isA<StateError>()),
      );
    },
  );

  group('dashboard', () {
    setUpAll(() async {
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
      bool metricsEnabled = true,
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
              sessionsProvider.overrideWith(
                (ref) => Stream.value(const <SshSessionInfo>[]),
              ),
              maidCafeStatsProvider.overrideWith(
                () => _FakeStatsNotifier(daemonStats),
              ),
              metricsRefreshSettingsProvider.overrideWithValue(
                InMemoryMetricsRefreshSettings(
                  serverMetricsEnabled: metricsEnabled,
                ),
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

    testWidgets('shows the readings while the switch is on', (tester) async {
      await pumpDashboard(tester, daemonStats: {1: _daemonSnapshot});

      expect(find.text('4.50'), findsOneWidget);
    });

    testWidgets('hides every reading once the switch is off', (tester) async {
      await pumpDashboard(
        tester,
        metricsEnabled: false,
        daemonStats: {1: _daemonSnapshot},
      );

      expect(find.text('serversMetricsDisabled'.tr()), findsOneWidget);
      expect(find.text('4.50'), findsNothing);
    });
  });
}
