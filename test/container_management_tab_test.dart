import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/container_management_tab.dart';
import 'package:maid_kit/containers/container_ui.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/theme.dart';

/// A daemon session that answers the two calls the container list makes, with
/// the payloads the Go daemon serves. Everything else stays unimplemented, so a
/// tab that reaches for another member fails loudly.
class _StubSession implements MaidCafeStreamSession {
  _StubSession({
    this.updates = const {},
    this.stacks = const {},
    this.containersPayload,
  });

  /// The `/api/v1/updates` payload, empty by default.
  final Map<String, dynamic> updates;

  /// The `/api/v1/compose/stacks` payload, empty by default.
  final Map<String, dynamic> stacks;

  /// The `/api/v1/containers` payload, when a test needs its own.
  final Map<String, dynamic>? containersPayload;

  /// The scan requests this session was asked to make, as `path|depth`.
  final scans = <String>[];

  /// The compose actions this session was asked to run, as
  /// `project|verb|directory`.
  final composeActions = <String>[];

  /// Projects whose stack update should fail, with the daemon's message.
  final failures = <String, String>{};

  @override
  bool get isClosed => false;

  @override
  Future<Map<String, dynamic>> containers() async =>
      containersPayload ??
      {
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
  Future<Map<String, dynamic>> composeStacks() async => stacks;

  @override
  Future<Map<String, dynamic>> scanComposeStacks({
    String? path,
    List<String>? roots,
    int? depth,
  }) async {
    scans.add('${path ?? ''}|${depth ?? 0}');
    return {
      'ok': true,
      'roots': [path ?? ''],
      'found': 2,
      'added': ['storefront', 'blog'],
      'updated': <String>[],
      'removed': <String>[],
      'stacks': [
        {
          'project': 'storefront',
          'directory': '/opt/stacks/web',
          'services': ['web'],
          'running': 1,
          'total': 2,
        },
      ],
    };
  }

  @override
  Future<MaidCafeTask> startComposeAction(
    String project,
    String verb,
    String directory, {
    String? invokedBy,
  }) async {
    composeActions.add('$project|$verb|$directory');
    // What the daemon answers a stack update with: a task following a plan,
    // not a result — the update takes minutes and the client does not wait.
    return MaidCafeTask.parse({
      'task': {
        'id': 'task-$project',
        'name': 'compose.$verb',
        'display_name': 'Update compose stack',
        'target': project,
        'status': 'running',
        'stages': [
          {'label': 'pull', 'status': 'running'},
          {'label': 'recreate', 'status': 'pending'},
        ],
        'ok': false,
        'exit_code': 0,
        'output_bytes': 0,
      },
      'output': '',
      'output_from': 0,
    });
  }

  @override
  Future<MaidCafeTask> followTask(
    MaidCafeTask task, {
    void Function(String chunk)? onOutput,
    void Function(String label)? onStage,
    Duration interval = const Duration(seconds: 1),
  }) async {
    if (!task.isRunning) return task;
    final failure = failures[task.target];
    onStage?.call('pull');
    onOutput?.call('Pulling web\n');
    if (failure == null) {
      onStage?.call('recreate');
      onOutput?.call('Recreating web\n');
    }
    return MaidCafeTask.parse({
      'task': {
        'id': task.id,
        'name': task.name,
        'target': task.target,
        'status': failure == null ? 'succeeded' : 'failed',
        'ok': failure == null,
        'exit_code': failure == null ? 0 : 1,
        'stdout': failure == null ? 'Recreating web\n' : '',
        'stderr': failure ?? '',
        'stages': [
          {'label': 'pull', 'status': 'succeeded'},
          {
            'label': 'recreate',
            'status': failure == null ? 'succeeded' : 'pending',
          },
        ],
      },
      'output': '',
      'output_from': 0,
    });
  }

  @override
  Future<MaidCafeOpResult> runComposeAction(
    String project,
    String verb,
    String directory, {
    String? invokedBy,
  }) async {
    composeActions.add('$project|$verb|$directory');
    final failure = failures[project];
    if (failure != null) {
      return MaidCafeOpResult.parse({
        'ok': false,
        'exit_code': 1,
        'stderr': failure,
      });
    }
    return MaidCafeOpResult.parse({'ok': true, 'exit_code': 0});
  }

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
    ThemeData? theme,
  }) async {
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            maidCafeSessionRegistryProvider.overrideWithValue(registry),
          ],
          child: MaterialApp(
            theme: theme,
            // The app's confirmations render through IslandUIFoundation's
            // overlay, so a test that taps one has to install the key the
            // app installs at startup.
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Scaffold(
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
              ],
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
    // The toolbar's stamp names the source, since this list did not come from
    // the SSH poller.
    expect(find.text('containerListSourceDaemon'.tr()), findsOneWidget);
    // The tab retained the shared session while it was mounted.
    expect(registry.retains, 1);
  });

  testWidgets('a daemon with no update route draws no badge', (tester) async {
    await pump(tester, registry: _StubRegistry(_StubSession()));

    expect(find.text('web'), findsOneWidget);
    expect(find.text('containerUpdateAvailable'.tr()), findsNothing);
    expect(find.text('containerRestartToUpdate'.tr()), findsNothing);
  });

  testWidgets('a managed stack is a project in the list, not a section', (
    tester,
  ) async {
    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'myapp',
            'directory': '/opt/myapp',
            'files': ['/opt/myapp/compose.yaml'],
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
      containersPayload: {
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
                'compose_project': 'myapp',
              },
            ],
          },
        ],
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    // The stack heads a project row the daemon's registry supplied, so the
    // container is grouped under it rather than listed as a bare environment.
    expect(find.text('myapp'), findsOneWidget);
    // Its directory is the one the daemon runs compose in — the fact the
    // containers themselves do not carry.
    expect(find.text('/opt/myapp'), findsOneWidget);
    // The group's mono line carries the assignment along with where it runs.
    expect(find.textContaining('composeStacksManaged'.tr()), findsOneWidget);
    // The container row is inside the project, with its daemon actions.
    expect(find.text('web'), findsOneWidget);
    expect(find.text('containersStandalone'.tr()), findsNothing);
  });

  testWidgets('the header scan assigns projects through the daemon', (
    tester,
  ) async {
    final session = _StubSession(
      stacks: {
        'stacks': <Object?>[],
        'scan': {
          'roots': ['/opt', '/srv'],
          'depth': 3,
          'max_files': 400,
        },
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    await tester.tap(find.byIcon(Symbols.scan));
    await tester.pumpAndSettle();
    // The dialog names what the daemon would scan with no starting point, so
    // leaving the field empty is a decision.
    expect(
      find.text('composeStacksScanPolicy'.tr(args: ['/opt, /srv', '3'])),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, '/opt/stacks');
    await tester.tap(
      find.widgetWithText(FilledButton, 'composeStacksScan'.tr()),
    );
    // The dialog closes, the scan runs, and the outcome is reported while the
    // snackbar is up — before its own timeout can take it away.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(session.scans, ['/opt/stacks|0']);
    await tester.pumpAndSettle();
    // The registry the scan answered with is what the list now shows, which is
    // the outcome flowing back; the counts themselves go to the app's standard
    // snackbar, which this harness cannot observe.
    expect(find.text('storefront'), findsOneWidget);
    expect(find.text('/opt/stacks/web'), findsOneWidget);
  });

  testWidgets('a scanned stack is the project row, update and all', (
    tester,
  ) async {
    // The row exists because a scan assigned the project — no local record of
    // it, and no container list to derive it from: this is also the regression
    // guard for a project that used to lose its update control once the app
    // had a local copy of the same project.
    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'myapp',
            'directory': '/opt/myapp',
            'files': ['/opt/myapp/compose.yaml'],
            'services': ['web', 'worker'],
            'running': 0,
            'total': 0,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
      containersPayload: {
        'runtimes': [
          {'runtime': 'docker', 'available': true, 'containers': <Object?>[]},
        ],
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    // Assigned, nothing running: still a project, still updatable, and it says
    // which directory the daemon will run compose in.
    expect(find.text('myapp'), findsOneWidget);
    expect(find.text('/opt/myapp'), findsOneWidget);
    expect(find.textContaining('composeStacksManaged'.tr()), findsOneWidget);
    expect(find.text('composeStacksNoContainers'.tr()), findsOneWidget);
    expect(find.byIcon(Symbols.upgrade), findsOneWidget);
  });

  testWidgets('one managed stack is updated whole, from its own row', (
    tester,
  ) async {
    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'myapp',
            'directory': '/opt/myapp',
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
      containersPayload: {
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
                'compose_project': 'myapp',
              },
            ],
          },
        ],
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    await tester.tap(find.byIcon(Symbols.upgrade));
    await tester.pumpAndSettle();
    // The confirmation names what the update does before anything runs.
    expect(
      find.text('composeStacksUpdateConfirm'.tr(args: ['myapp'])),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // No directory is sent: the daemon runs the project where its registry
    // says it lives, which is what makes an unassigned project a refusal
    // rather than an update somewhere this app guessed.
    expect(session.composeActions, ['myapp|update|']);
    // The update is watched in the task terminal; close it so the next test
    // starts from a clean overlay.
    await tester.tap(find.text('commonDone'.tr()));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a refusal that names a sudo grant opens the guide, not a snackbar',
    (tester) async {
      const refusal =
          'project "myapp" lives in podman in root\'s store, and the compose '
          'tool that runs there — /usr/local/bin/podman-compose — may not be run '
          'through `sudo -n` on this host; grant it (for example `maidcafe '
          'ALL=(root) NOPASSWD: /usr/local/bin/podman-compose` in a file under '
          '/etc/sudoers.d/) or run the step yourself as root';
      final session = _StubSession(
        stacks: {
          'stacks': [
            {
              'project': 'myapp',
              'directory': '/opt/myapp',
              'services': ['web'],
              'running': 1,
              'total': 1,
            },
          ],
          'scan': {
            'roots': ['/opt'],
            'depth': 3,
            'max_files': 400,
          },
        },
      )..failures['myapp'] = refusal;

      await pump(tester, registry: _StubRegistry(session));

      await tester.tap(find.byIcon(Symbols.upgrade));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // The refusal is a paragraph and the rule it asks for is a line; both are
      // readable and copyable in the guide, which is what a snackbar cannot be.
      expect(find.text('containerSudoGuideTitle'.tr()), findsOneWidget);
      expect(
        find.text(
          'maidcafe ALL=(root) NOPASSWD: /usr/local/bin/podman-compose',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('may not be run through `sudo -n` on this host'),
        findsOneWidget,
      );
      // Nothing is connected here, so the guide offers the command and says why
      // it cannot install it.
      expect(find.text('containerSudoGuideNoSsh'.tr()), findsOneWidget);
      final install = tester.widget<FilledButton>(
        find.widgetWithText(
          FilledButton,
          'containerSudoGuideInstall'.tr(args: ['Build host']),
        ),
      );
      expect(install.onPressed, isNull);

      // Close the guide and the task terminal so the next test starts from a
      // clean navigator.
      await tester.tap(find.text('commonClose'.tr()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('commonDone'.tr()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a stack update is a task the terminal follows', (tester) async {
    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'myapp',
            'directory': '/opt/myapp',
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    await tester.tap(find.byIcon(Symbols.upgrade));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The update runs as the daemon's task, and the terminal is where it is
    // watched: what the daemon runs, the stage it is on, and the run's own
    // output — which is the whole point, since a pull takes minutes and this
    // client's read timeout is ten seconds.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ContainerManagementTab)),
    );
    final sessions = container.read(deploySessionsProvider);
    expect(sessions, hasLength(1));
    final run = sessions.single;
    expect(run.subtitle, 'myapp');
    expect(run.command, contains('compose -p myapp pull'));
    expect(run.command, contains('up -d --force-recreate'));
    expect(run.log, contains('==> ${'composeStacksStagePull'.tr()}'));
    expect(run.log, contains('Pulling web'));
    expect(run.log, contains('Recreating web'));
    expect(run.status, DeploySessionStatus.succeeded);

    await tester.tap(find.text('commonDone'.tr()));
    await tester.pumpAndSettle();
  });

  testWidgets('every managed stack is updated one at a time', (tester) async {
    Map<String, dynamic> stack(String project, String directory) => {
      'project': project,
      'directory': directory,
      'services': ['web'],
      'running': 1,
      'total': 1,
    };
    final session = _StubSession(
      stacks: {
        'stacks': [stack('alpha', '/opt/alpha'), stack('beta', '/opt/beta')],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    await tester.tap(find.byIcon(Symbols.update));
    await tester.pumpAndSettle();
    expect(
      find.text('composeStacksUpdateAllConfirm'.tr(args: ['2'])),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Sequential, in registry order, and each one whole-stack.
    expect(session.composeActions, ['alpha|update|', 'beta|update|']);
    // The dialog reports per stack and stays up for reading.
    expect(find.text('alpha'), findsWidgets);
    expect(find.text('beta'), findsWidgets);
    expect(
      find.text('composeStacksUpdateSummary'.tr(args: ['2', '0'])),
      findsOneWidget,
    );
  });

  testWidgets('a stack that fails does not stop the rest', (tester) async {
    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'alpha',
            'directory': '/opt/alpha',
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
          {
            'project': 'beta',
            'directory': '/opt/beta',
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
    )..failures['alpha'] = 'project "alpha" is not a stack this daemon manages';

    await pump(tester, registry: _StubRegistry(session));

    await tester.tap(find.byIcon(Symbols.update));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(session.composeActions, ['alpha|update|', 'beta|update|']);
    // The daemon's own words explain the failure, and the summary counts it.
    expect(
      find.textContaining('is not a stack this daemon manages'),
      findsOneWidget,
    );
    expect(
      find.text('composeStacksUpdateSummary'.tr(args: ['1', '1'])),
      findsOneWidget,
    );
  });

  testWidgets('the toolbar carries the counts, the transport and the actions', (
    tester,
  ) async {
    await pump(tester, registry: _StubRegistry(_StubSession()));

    // One toolbar instead of a full-bleed banner plus a row of icons: what the
    // list holds, who answered it, and what can be done to all of it.
    final toolbar = tester.widget<ContainerListToolbar>(
      find.byType(ContainerListToolbar),
    );
    expect(toolbar.summary, hasLength(1));
    expect(toolbar.source, ContainerListSource.daemon);
    expect(find.text('containerListSourceDaemon'.tr()), findsOneWidget);
  });

  testWidgets('a project and an environment are built from the same group', (
    tester,
  ) async {
    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'myapp',
            'directory': '/opt/myapp',
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
      containersPayload: {
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
                'compose_project': 'myapp',
              },
              {
                'id': 'fedcba654321',
                'name': 'caddy',
                'image': 'caddy:2.8',
                'state': 'running',
                'status': 'Up 6 days',
              },
            ],
          },
        ],
      },
    );

    await pump(tester, registry: _StubRegistry(session));

    // A project and a runtime store read as the same object: identity, one
    // line of machine facts, rows — no second anatomy to learn.
    final groups = tester
        .widgetList<ContainerGroup>(find.byType(ContainerGroup))
        .toList();
    expect(groups.map((group) => group.title), ['myapp', 'runtimeDocker']);
    for (final group in groups) {
      expect(group.spec, isNotEmpty);
      expect(group.children, isNotEmpty);
    }
    // The project's line says where its containers run and that the daemon
    // owns the stack; the environment's line says which store it is.
    expect(groups.first.spec, containsAll(['docker', 'containersStoreRoot']));
    expect(groups.first.spec, contains('composeStacksManaged'.tr()));
    expect(groups.last.spec, contains('containersStoreRoot'.tr()));

    // Each section heading carries how many containers are under it, and the
    // two add up to the toolbar's total.
    final labels = tester
        .widgetList<ContainerSectionLabel>(find.byType(ContainerSectionLabel))
        .toList();
    expect(labels.map((label) => label.count), [1, 1]);
  });

  testWidgets('the list holds together narrow, in the light theme', (
    tester,
  ) async {
    // A narrow pane is where the toolbar, a monospace fact line and a long
    // directory have to give way in a defined order; an overflow fails here.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(560, 720);
    addTearDown(tester.view.reset);

    final session = _StubSession(
      stacks: {
        'stacks': [
          {
            'project': 'myapp',
            'directory': '/opt/stacks/myapp/some/deep/directory',
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
        'scan': {
          'roots': ['/opt'],
          'depth': 3,
          'max_files': 400,
        },
      },
      containersPayload: {
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
                'compose_project': 'myapp',
              },
            ],
          },
        ],
      },
    );

    await pump(
      tester,
      registry: _StubRegistry(session),
      theme: createMaidKitTheme(Brightness.light),
    );

    expect(find.byType(ContainerListToolbar), findsOneWidget);
    expect(find.byType(ContainerGroup), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
  });
}
