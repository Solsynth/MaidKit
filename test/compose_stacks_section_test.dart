import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/compose_stacks_section.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';

/// A daemon session answering only the compose-registry calls the section
/// makes. Everything else stays unimplemented, so a section that reaches for
/// another member fails loudly.
class _StubSession implements MaidCafeStreamSession {
  _StubSession({required this.composeStacksJson, this.scanJson});

  /// Answers `GET /api/v1/compose/stacks`.
  Map<String, dynamic> Function() composeStacksJson;

  /// Answers `POST /api/v1/compose/stacks/scan`; unused when null.
  Map<String, dynamic> Function(String? path, int? depth)? scanJson;

  final scanPaths = <String?>[];
  final composeActions = <String>[];

  @override
  bool get isClosed => false;

  @override
  Future<Map<String, dynamic>> composeStacks() async {
    return composeStacksJson();
  }

  @override
  Future<Map<String, dynamic>> scanComposeStacks({
    String? path,
    List<String>? roots,
    int? depth,
  }) async {
    scanPaths.add(path);
    final json = scanJson;
    if (json != null) return json(path, depth);
    return const {
      'ok': true,
      'roots': <String>[],
      'found': 0,
      'added': <String>[],
      'updated': <String>[],
      'removed': <String>[],
      'stacks': {
        'stacks': <Map<String, dynamic>>[],
        'scan': {'roots': <String>[], 'depth': 3, 'max_files': 400},
      },
    };
  }

  @override
  Future<Map<String, dynamic>> unassignComposeStack(String project) async {
    return const {'ok': true};
  }

  @override
  Future<MaidCafeOpResult> runComposeAction(
    String project,
    String verb,
    String directory, {
    String? invokedBy,
  }) async {
    composeActions.add('$project|$verb|$directory');
    return const MaidCafeOpResult(ok: true, exitCode: 0);
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'the compose stacks section reached for ${invocation.memberName}',
  );
}

Map<String, dynamic> _stack({
  required String project,
  int running = 0,
  int total = 0,
}) => {
  'project': project,
  'directory': '/srv/$project',
  'files': ['compose.yaml'],
  'services': ['svc-$project'],
  'scanned_at': '2026-10-01T00:00:00Z',
  'running': running,
  'total': total,
  'containers': <Map<String, dynamic>>[],
};

Map<String, dynamic> _snapshot(List<Map<String, dynamic>> stacks) => {
  'ok': true,
  'stacks': stacks,
  'scan': {
    'roots': ['/srv'],
    'depth': 3,
    'max_files': 400,
  },
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<_StubSession> pump(
    WidgetTester tester, {
    required Map<String, dynamic> Function() composeStacksJson,
    Map<String, dynamic> Function(String? path, int? depth)? scanJson,
  }) async {
    final session = _StubSession(
      composeStacksJson: composeStacksJson,
      scanJson: scanJson,
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ComposeStacksSection(
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
                ensureSession: () async => session,
                refreshToken: 0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> expand(WidgetTester tester, int count) async {
    await tester.tap(find.text('composeStacksTitle'.tr(args: ['$count'])));
    await tester.pumpAndSettle();
  }

  testWidgets('renders each managed stack with its health counts', (
    tester,
  ) async {
    await pump(
      tester,
      composeStacksJson: () => _snapshot([
        _stack(project: 'web', running: 2, total: 2),
        _stack(project: 'api', running: 1, total: 2),
      ]),
    );
    await expand(tester, 2);

    expect(find.text('web'), findsOneWidget);
    expect(find.text('api'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('a scan sends the chosen path and paints the fresh list', (
    tester,
  ) async {
    final session = await pump(
      tester,
      composeStacksJson: () =>
          _snapshot([_stack(project: 'web', running: 2, total: 2)]),
      scanJson: (path, depth) => {
        'ok': true,
        'roots': ['/srv'],
        'found': 2,
        'added': ['cache'],
        'updated': <String>[],
        'removed': <String>[],
        'stacks': [
          _stack(project: 'web', running: 2, total: 2),
          _stack(project: 'cache', running: 1, total: 1),
        ],
      },
    );

    await tester.tap(find.byIcon(Symbols.scan));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '/srv/extra');
    await tester.tap(find.text('composeStacksScan'.tr()));
    await tester.pumpAndSettle();

    expect(session.scanPaths, ['/srv/extra']);

    await expand(tester, 2);
    expect(find.text('web'), findsOneWidget);
    expect(find.text('cache'), findsOneWidget);
  });

  testWidgets('the Upgrade menu item runs the daemon compose update', (
    tester,
  ) async {
    final session = await pump(
      tester,
      composeStacksJson: () =>
          _snapshot([_stack(project: 'web', running: 2, total: 2)]),
    );
    await expand(tester, 1);

    await tester.tap(find.byIcon(Symbols.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('composeStacksUpgrade'.tr()));
    await tester.pumpAndSettle();

    expect(session.composeActions, ['web|update|']);
  });
}
