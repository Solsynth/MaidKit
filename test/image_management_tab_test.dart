import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/container_ui.dart';
import 'package:maid_kit/containers/image_management_tab.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_providers.dart';

/// A daemon session that answers the one call the image list makes.
class _StubSession implements MaidCafeStreamSession {
  @override
  bool get isClosed => false;

  @override
  Future<Map<String, dynamic>> images() async => {
    'runtimes': [
      {
        'runtime': 'docker',
        'available': true,
        'store': 'own',
        'images': [
          {
            'id': 'sha256:aaaa1111',
            'tags': ['nginx:1.25'],
            'size': 187000000,
            'created': 1730000000,
          },
          {
            'id': 'sha256:bbbb2222',
            'tags': ['postgres:16'],
            'size': 421000000,
            'created': 1729000000,
          },
        ],
      },
      {
        'runtime': 'podman',
        'available': true,
        'store': 'root',
        'images': <Object?>[],
      },
    ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('reached ${invocation.memberName}');
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

  testWidgets('an image environment is the same group a container is', (
    tester,
  ) async {
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            maidCafeSessionRegistryProvider.overrideWithValue(
              _StubRegistry(_StubSession()),
            ),
          ],
          child: MaterialApp(
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Scaffold(
                    body: ImageManagementTab(
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

    // The toolbar names the transport, and each environment is the same object
    // a container environment is: identity, a mono line of facts, rows.
    expect(find.byType(ContainerListToolbar), findsOneWidget);
    expect(find.text('containerListSourceDaemon'.tr()), findsOneWidget);
    final groups = tester
        .widgetList<ContainerGroup>(find.byType(ContainerGroup))
        .toList();
    expect(groups.map((group) => group.title), [
      'runtimeDocker',
      'runtimePodman',
    ]);
    expect(groups.first.spec, contains('containersStoreDaemon'.tr()));
    expect(groups.last.spec, contains('containersStoreRoot'.tr()));
    expect(groups.first.children, hasLength(2));
    // An environment with nothing in it says so inside its own card.
    expect(groups.last.children, hasLength(1));
    expect(find.text('nginx:1.25'), findsOneWidget);
  });
}
