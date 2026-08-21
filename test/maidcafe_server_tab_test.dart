import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_server_tab.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/server_repository.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/vault_service.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solsynth_express/solsynth_express.dart';

const _testChannels = [
  DistributionChannel(
    id: 'stable-id',
    name: 'stable',
    displayName: 'Stable',
    displayNames: {},
    description: '',
    descriptions: {},
    latest: null,
  ),
  DistributionChannel(
    id: 'beta-id',
    name: 'beta',
    displayName: 'Beta',
    displayNames: {},
    description: '',
    descriptions: {},
    latest: null,
  ),
];

// ---------------------------------------------------------------------------
// Fake SSH stack: the payload workspace only reaches the running state after
// a probe that walks manager.withClient -> client.execute -> config read ->
// stream session. These fakes serve canned daemon responses so widget tests
// can drive the real actions/audit UI without a live SSH tunnel.
// ---------------------------------------------------------------------------

class _FakeSSHSession implements SSHSession {
  _FakeSSHSession(this._stdout);

  final String _stdout;

  @override
  Stream<Uint8List> get stdout =>
      Stream.value(Uint8List.fromList(utf8.encode(_stdout)));

  @override
  Future<void> get done => Future<void>.value();

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSSHClient implements SSHClient {
  _FakeSSHClient(this._onCommand);

  final SSHSession Function(String command) _onCommand;

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async => _onCommand(command);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSshManager extends SshConnectionManager {
  _FakeSshManager(this._onCommand) : super(() => throw UnimplementedError());

  final SSHSession Function(String command) _onCommand;
  late final _FakeSSHClient _client = _FakeSSHClient(_onCommand);

  @override
  Future<T> withClient<T>(
    int serverId,
    Future<T> Function(SSHClient client) run,
  ) => run(_client);
}

class _FakeRepository extends ServerRepository {
  _FakeRepository(AppDatabase database)
    : super(database, VaultService(database));

  @override
  Future<ServerCredential> credentialFor(Server server) async =>
      const ServerCredential.password('test-password');

  @override
  Future<String?> maidCafeMetricsSecretFor(Server server) async =>
      'test-secret';

  @override
  Future<void> updateMaidCafeConfig(
    Server server, {
    required String daemonUrl,
    String? webhookSecret,
    bool clearWebhookSecret = false,
    String? metricsSecret,
    bool clearMetricsSecret = false,
  }) async {}
}

class _FakeStreamSession implements MaidCafeStreamSession {
  _FakeStreamSession({required this.auditEntries});

  final List<MaidCafeAuditEntry> auditEntries;

  @override
  String? get version => '1.2.3';

  @override
  String? get apiSecret => 'test-secret';

  @override
  Future<Map<String, dynamic>> health() async => {'version': '1.2.3'};

  @override
  Future<Map<String, dynamic>> metrics() async => {};

  @override
  Future<Map<String, dynamic>> config() async => {
    'config': {
      'status_upload_enabled': false,
      'managed_containers': <String>[],
      'managed_composes': <String>[],
    },
  };

  @override
  Future<Map<String, dynamic>> patchConfig(Map<String, Object?> patch) async =>
      {'ok': true};

  @override
  Future<List<MaidCafeAuditEntry>> audit({int limit = 50}) async =>
      auditEntries;

  @override
  Stream<MaidCafeStreamEvent> openStream({
    Set<MaidCafeStreamEventType> events = maidCafeStreamAllEvents,
    int processesLimit = 0,
  }) => const Stream.empty();

  @override
  Future<void> sendTestNotification() async {}

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSessionRegistry extends MaidCafeSessionRegistry {
  _FakeSessionRegistry({
    required this.session,
    required super.manager,
    required super.serverRepository,
  });

  final MaidCafeStreamSession? session;

  @override
  void retain(Server server) {}

  @override
  void release(Server server) {}

  @override
  void invalidate(Server server) {}

  @override
  Future<MaidCafeStreamSession?> sessionFor(
    Server server, {
    int? port,
    bool force = false,
  }) async => session;
}

String _hexEncode(String text) => utf8
    .encode(text)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// A read-back `/etc/maidcafe/config.toml` payload with one inline action
/// (`deploy`) and its deployed script, matching the marker format the daemon
/// read-back uses.
String _daemonConfigPayload() {
  const daemon = '''
[daemon]
id = "maidkit-1"
listen = "127.0.0.1:8747"
metricsSecret = "test-secret"
transport = "http"
[[daemon.actions]]
name = "deploy"
command = "deploy.sh"
enabled = true
notifyOnSuccess = false
notifyOnFailure = false
displayName = "Deploy"
''';
  const script = '#!/bin/sh\necho deploy\n';
  return '$daemon'
      '\n###MAIDKIT-FULL-CONFIG###\n'
      '${_hexEncode(daemon)}\n'
      '###MAIDKIT-ACTION-CONFIGS###\n'
      '###MAIDKIT-ACTION-SCRIPTS###\n'
      '###FILE:deploy.sh###\n'
      '${_hexEncode(script)}\n';
}

SSHSession _fakeRemoteCommand(String command) {
  if (command.contains('maidkit-managed')) {
    return _FakeSSHSession('managed\n');
  }
  if (command.contains('/etc/maidcafe/config.toml')) {
    return _FakeSSHSession(_daemonConfigPayload());
  }
  throw StateError('Unexpected remote command: $command');
}

/// Pumps a MaidCafe tab into the running state against the fake SSH stack:
/// the probe reads a managed install plus the daemon config, opens the shared
/// session, and exposes either the installation actions or payload tabs.
Future<void> pumpRunningPayloadTab(
  WidgetTester tester, {
  bool daemonReachable = true,
  MaidCafeTabMode mode = MaidCafeTabMode.payload,
}) async {
  // testWidgets bodies run in a FakeAsync zone where real I/O futures never
  // complete; the temp dir and the (lazily opened) drift database must be
  // created through runAsync.
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('maidcafe-test'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  // drift_flutter resolves the sqlite temporary directory through the
  // path_provider platform channel even when a database path is supplied;
  // the channel is dead in widget tests, so stub it with the temp dir. The
  // database itself is never queried by the fakes.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      if (call.method == 'getTemporaryDirectory' ||
          call.method == 'getApplicationDocumentsDirectory') {
        return directory.path;
      }
      return null;
    },
  );
  final database = (await tester.runAsync(
    () async => AppDatabase(filePath: '${directory.path}/test.sqlite'),
  ))!;
  addTearDown(database.close);
  final manager = _FakeSshManager(_fakeRemoteCommand);
  final repository = _FakeRepository(database);
  final registry = _FakeSessionRegistry(
    session: daemonReachable
        ? _FakeStreamSession(auditEntries: const [])
        : null,
    manager: manager,
    serverRepository: repository,
  );
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final server = Server(
    id: 1,
    name: 'Build host',
    host: 'build.example',
    port: 22,
    username: 'builder',
    collectStats: true,
    collectSystemInfo: true,
    connectionType: 'ssh',
  );
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWithValue(manager),
          serverRepositoryProvider.overrideWithValue(repository),
          maidCafeSessionRegistryProvider.overrideWithValue(registry),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          home: Scaffold(
            body: DefaultTabController(
              length: 2,
              child: TabBarView(
                children: [
                  // The outer TabBarView is a theme LookupBoundary, so the
                  // payload TabBar inside MaidCafeServerTab would not see the
                  // Scaffold's Material when its tabs rebuild during a
                  // switch. A page-local Material mirrors the real detail
                  // page and keeps the inner TabBar's lookup satisfied.
                  Material(
                    child: MaidCafeServerTab(
                      server: server,
                      connected: true,
                      connectionError: null,
                      onConnect: () async {},
                      mode: mode,
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpInstallSheet(
    WidgetTester tester, {
    required bool updating,
    required void Function(String?) onChosen,
  }) async {
    // `.tr()` resolves to the raw key in widget tests, so button labels are
    // long; widen the surface so the sheet's action row lays out on screen.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: MaterialApp(
          localizationsDelegates: [
            ...material_ui.GlobalMaterialLocalizations.delegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    onChosen(
                      await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        constraints: const BoxConstraints(maxWidth: 1400),
                        builder: (_) => MaidCafeInstallSheet(
                          channels: _testChannels,
                          updating: updating,
                          transport: 'http',
                          scriptBuilder: (channel) async =>
                              'script-for-$channel',
                        ),
                      ),
                    );
                  },
                  child: const Text('open-sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'install sheet locks the install button until every step is reviewed',
    (WidgetTester tester) async {
      String? chosen;
      await pumpInstallSheet(
        tester,
        updating: false,
        onChosen: (v) {
          chosen = v;
        },
      );

      await tester.tap(find.text('open-sheet'));
      await tester.pumpAndSettle();

      // Step 1 (channel): Next is disabled until a channel is picked.
      final nextButton = find.widgetWithText(
        FilledButton,
        'maidCafeInstallNext'.tr(),
      );
      expect(tester.widget<FilledButton>(nextButton).onPressed, isNull);

      // Picking a channel advances to step 2 (what the script does).
      await tester.tap(find.text('stable'));
      await tester.pumpAndSettle();
      expect(find.text('maidCafeInstallStepCurlTitle'.tr()), findsOneWidget);
      expect(tester.widget<FilledButton>(nextButton).onPressed, isNotNull);

      // Step 3 (script): the exact script is shown and install unlocks.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.text('script-for-stable'), findsOneWidget);
      final installButton = find.widgetWithText(
        FilledButton,
        'maidCafeInstallApplication'.tr(),
      );
      expect(tester.widget<FilledButton>(installButton).onPressed, isNotNull);

      await tester.tap(installButton);
      await tester.pumpAndSettle();
      expect(chosen, 'stable');
    },
  );

  testWidgets('update sheet needs only a channel, not the review walkthrough', (
    WidgetTester tester,
  ) async {
    String? chosen;
    await pumpInstallSheet(
      tester,
      updating: true,
      onChosen: (v) {
        chosen = v;
      },
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();

    expect(find.text('maidCafeUpdateApplication'.tr()), findsOneWidget);

    await tester.tap(find.text('stable'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'maidCafeInstallNext'.tr()),
    );
    await tester.pumpAndSettle();

    final installButton = find.widgetWithText(
      FilledButton,
      'maidCafeUpdateApplication'.tr(),
    );
    expect(tester.widget<FilledButton>(installButton).onPressed, isNotNull);

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    expect(chosen, 'stable');
  });

  Future<void> pumpDetailTabs(WidgetTester tester) async {
    final server = Server(
      id: 1,
      name: 'Build host',
      host: 'build.example',
      port: 22,
      username: 'builder',
      collectStats: true,
      collectSystemInfo: true,
      connectionType: 'ssh',
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'US')],
            home: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Cafe'),
                      Tab(text: 'Other'),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    MaidCafeServerTab(
                      server: server,
                      connected: false,
                      connectionError: null,
                      onConnect: () async {},
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'MaidCafe tab state survives detail page tab switches so the tunnel '
    'stays up until the page closes',
    (WidgetTester tester) async {
      await pumpDetailTabs(tester);

      final before = tester.state<State<MaidCafeServerTab>>(
        find.byType(MaidCafeServerTab),
      );

      // The server detail page's TabBarView must keep the MaidCafe tab
      // mounted: disposing it would tear down the SSH tunnel to the daemon.
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(
        tester.state<State<MaidCafeServerTab>>(
          find.byType(MaidCafeServerTab, skipOffstage: false),
        ),
        same(before),
      );

      await tester.tap(find.text('Cafe'));
      await tester.pumpAndSettle();
      expect(
        tester.state<State<MaidCafeServerTab>>(find.byType(MaidCafeServerTab)),
        same(before),
      );
    },
  );

  testWidgets(
    'an unreachable installed daemon surfaces as a failure, not a spinner',
    (WidgetTester tester) async {
      // A null shared session means the registry could not open the stream
      // (e.g. the daemon refuses to start); the probe must leave `checking`
      // and explain the state instead of spinning forever.
      await pumpRunningPayloadTab(tester, daemonReachable: false);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('maidCafeInstallationUnavailable'.tr()), findsOneWidget);
      expect(find.text('maidCafeInstallApplication'.tr()), findsOneWidget);
    },
  );
  testWidgets('running installation exposes the payload workspace action', (
    WidgetTester tester,
  ) async {
    await pumpRunningPayloadTab(tester, mode: MaidCafeTabMode.installation);

    final openPayloadButton = find.widgetWithText(
      OutlinedButton,
      'maidCafeOpenPayloadTab'.tr(),
    );
    expect(openPayloadButton, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(openPayloadButton).onPressed,
      isNotNull,
    );
    await tester.tap(openPayloadButton);
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaidCafeServerTab)),
    );
    expect(
      container
          .read(terminalTabsProvider)
          .tabs
          .whereType<MaidCafePayloadSessionTab>(),
      hasLength(1),
    );
  });

  testWidgets('alarms are edited in their own payload tab', (
    WidgetTester tester,
  ) async {
    await pumpRunningPayloadTab(tester);

    await tester.tap(find.text('maidCafeAlarms'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('maidCafeNoAlarms'.tr()), findsOneWidget);
    expect(find.text('maidCafeAddAlarm'.tr()), findsOneWidget);
    expect(find.text('maidCafeSaveAlarms'.tr()), findsOneWidget);

    await tester.tap(find.text('maidCafeAddAlarm'.tr()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'maidCafeThreshold'.tr()),
      '85',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'maidCafeSave'.tr()));
    await tester.pumpAndSettle();

    // The chip shows the metric and threshold (labels resolve to raw keys in
    // this harness, so only the numbers are asserted).
    expect(find.textContaining('85%'), findsOneWidget);
  });

  testWidgets('send test notification runs from the actions tab', (
    WidgetTester tester,
  ) async {
    await pumpRunningPayloadTab(tester);

    await tester.tap(find.text('maidCafeActions'.tr()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('maidCafeSendTestNotification'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('maidCafeTestNotificationSent'.tr()), findsOneWidget);
  });
}
