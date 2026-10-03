import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/container_list_tile.dart';
import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/containers/container_update_badge.dart';

ContainerUpdateStatus _status({
  bool? outdated,
  bool pinned = false,
  bool restartRequired = false,
  String image = 'nginx:1.25',
}) => ContainerUpdateStatus(
  container: 'abcdef123456',
  name: 'web',
  runtime: 'docker',
  image: image,
  outdated: outdated,
  pinned: pinned,
  restartRequired: restartRequired,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the badge names a registry update and a restart-only one', (
    tester,
  ) async {
    await pump(tester, ContainerUpdateBadge(status: _status(outdated: true)));
    expect(find.text('containerUpdateAvailable'.tr()), findsOneWidget);

    // The local image store already holds a newer image: the answer is a
    // recreate, not a download, and the badge says so.
    await pump(
      tester,
      ContainerUpdateBadge(
        status: _status(outdated: false, restartRequired: true),
      ),
    );
    expect(find.text('containerRestartToUpdate'.tr()), findsOneWidget);
    expect(find.text('containerUpdateAvailable'.tr()), findsNothing);
  });

  testWidgets('an unanswered or current check draws nothing', (tester) async {
    // Null is not false: the daemon could not answer, so claiming "current"
    // would be a guess.
    await pump(tester, ContainerUpdateBadge(status: _status()));
    expect(find.byType(ContainerUpdateBadge), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);

    await pump(tester, ContainerUpdateBadge(status: _status(outdated: false)));
    expect(find.byType(Tooltip), findsNothing);

    // A digest-pinned container is never outdated, whatever the registry says.
    await pump(
      tester,
      ContainerUpdateBadge(status: _status(outdated: false, pinned: true)),
    );
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('the list row carries the badge next to the image', (
    tester,
  ) async {
    const container = ServerContainer(
      id: 'abcdef123456',
      name: 'web',
      image: 'nginx:1.25',
      state: 'running',
      status: 'Up 3 hours',
    );

    await pump(
      tester,
      ContainerListTile(
        container: container,
        onOpen: () {},
        updateStatus: _status(outdated: true),
      ),
    );
    expect(find.text('web'), findsOneWidget);
    expect(find.text('containerUpdateAvailable'.tr()), findsOneWidget);

    await pump(tester, ContainerListTile(container: container, onOpen: () {}));
    expect(find.text('containerUpdateAvailable'.tr()), findsNothing);
  });
}
